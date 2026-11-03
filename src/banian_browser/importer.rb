module BanianStudio
  module BanianBrowser
    # Skimp-style importer and polygon reducer.
    #
    #  * Import GLB/glTF, FBX, OBJ(+MTL), DAE, 3DS, STL, PLY, VRML, USDZ and SKP with a
    #    3D preview: units, up axis, polygon reduction (percent or error tolerance),
    #    flat shading, placeholder UV texture, components for repeated meshes.
    #  * Simplify groups / components already in the model (hierarchy preserved).
    #  * Build accurate decimated proxies for Enscape.
    #
    # Parsing, preview and reduction run in the dialog's JavaScript engine (three.js +
    # decimate.js); Ruby streams files to it and builds the final SketchUp geometry with
    # Geom::PolygonMesh, so there is no compiled code and it works on every version.
    module Importer
      MESH_EXTS = %w[.glb .gltf .fbx .obj .dae .3ds .stl .ply .wrl .vrml .usdz].freeze
      CHUNK = 768 * 1024
      SMOOTH = 12 # AUTO_SOFTEN | SMOOTH_SOFT_EDGES

      class << self
        def model
          Sketchup.active_model
        end

        def importable?(path)
          ext = File.extname(path.to_s).downcase
          MESH_EXTS.include?(ext) || ext == '.skp'
        end

        # ---- entry points --------------------------------------------------------------
        def open_file(path)
          path = Util.norm(path)
          return UI.messagebox(I18n.t(:not_found)) unless File.file?(path)
          ext = File.extname(path).downcase
          if ext == '.skp'
            return unless ModelOps.check_version(path)
            d = model.definitions.load(path)
            return unless d
            d.set_attribute(DICT, 'source', path)
            show('mode' => 'skp', 'path' => path, 'definition' => d)
          else
            show('mode' => 'file', 'path' => path)
          end
        end

        def browse_and_open
          filter = 'Models|*.glb;*.gltf;*.fbx;*.obj;*.dae;*.3ds;*.stl;*.ply;*.wrl;*.vrml;*.usdz;*.skp||'
          f = UI.openpanel(I18n.t(:import_title), Settings['last_save_dir'].to_s, filter)
          open_file(f) if f
        end

        # purpose: 'simplify' (replace geometry) or 'proxy' (build decimated proxies)
        def open_selection(purpose)
          insts = Util.instances_in(model.selection.to_a)
          if insts.empty?
            UI.messagebox(I18n.t(:select_components))
            return
          end
          show('mode' => purpose, 'instances' => insts)
        end

        # ---- dialog --------------------------------------------------------------------------
        def show(ctx)
          close
          @ctx = ctx
          @reads = {}
          @geoms = {}
          @dlg = UI::HtmlDialog.new(
            :dialog_title => 'Banian Import',
            :preferences_key => 'BanianStudio_BanianImport',
            :scrollable => false, :resizable => true,
            :width => 1160, :height => 760, :min_width => 720, :min_height => 480,
            :style => UI::HtmlDialog::STYLE_DIALOG
          )
          @dlg.set_file(File.join(PLUGIN_DIR, 'ui', 'importer.html'))
          @dlg.add_action_callback('bi_call') { |_c, payload| handle(payload) }
          @dlg.set_on_closed { on_closed } if @dlg.respond_to?(:set_on_closed)
          @dlg.show
        end

        def close
          return unless @dlg
          d = @dlg
          @dlg = nil
          d.close if d.visible?
          on_closed
        end

        def on_closed
          ctx = @ctx
          @ctx = nil
          @reads = {}
          @geoms = {}
          return unless ctx && ctx['mode'] == 'skp' && !ctx['done']
          Proxy.remove_definition(ctx['definition']) if ctx['definition'] && ctx['definition'].valid?
        end

        def js(code)
          @dlg.execute_script(code) if @dlg && @dlg.visible?
        end

        def emit(event, data)
          js("window.BI && BI.emit(#{Dialog.to_js(event)}, #{Dialog.to_js(data)});")
        end

        def handle(payload)
          msg = JSON.parse(payload)
          id = msg['id']
          res = send("cmd_#{msg['cmd']}", msg['args'] || {})
          js("BI.reply(#{Dialog.to_js(id)}, #{Dialog.to_js('ok' => true, 'data' => res)});") if id
        rescue StandardError => e
          Util.log_error(e, "import #{msg ? msg['cmd'] : '?'}")
          js("BI.reply(#{Dialog.to_js(id)}, #{Dialog.to_js('ok' => false, 'error' => e.message)});") if id
        end

        # ---- commands -----------------------------------------------------------------------
        def cmd_init(_a)
          ctx = @ctx || {}
          info = {
            'mode' => ctx['mode'],
            'lang' => Settings['language'],
            'theme' => Settings['theme'],
            'settings' => Settings.data.select { |k, _| k =~ /\A(import|simplify|proxy)_/ },
            'su' => Util.su_major
          }
          if ctx['path']
            p = ctx['path']
            info['file'] = { 'path' => p, 'name' => File.basename(p), 'ext' => File.extname(p).delete('.').downcase,
                             'size' => File.size(p), 'dir' => Util.norm(File.dirname(p)) }
          end
          info
        end

        def cmd_settings(a)
          Settings.update(a['values'] || {})
          true
        end

        # Streams a file as base64 chunks: emits 'chunk' {req, data, last}.
        def cmd_read(a)
          path = find_file(a['path'].to_s, a['base'])
          return { 'missing' => true } unless path
          req = a['req']
          size = File.size(path)
          f = File.open(path, 'rb')
          timer = nil
          timer = UI.start_timer(0.005, true) do
            begin
              data = f.read(CHUNK) || ''.b
              last = f.eof?
              emit('chunk', 'req' => req, 'data' => [data].pack('m0'), 'last' => last)
              if last
                UI.stop_timer(timer)
                f.close
              end
            rescue StandardError => e
              UI.stop_timer(timer)
              f.close unless f.closed?
              emit('chunk', 'req' => req, 'error' => e.message, 'last' => true)
            end
          end
          { 'size' => size, 'path' => path }
        end

        # Textures in FBX/OBJ often point to other machines' folders: look next to the model.
        def find_file(path, base)
          p = Util.norm(path)
          return p if File.file?(p)
          base = Util.norm(base.to_s)
          name = File.basename(p.tr('\\', '/'))
          return nil if base.empty? || !File.directory?(base)
          cand = Util.join(base, name)
          return cand if File.file?(cand)
          down = name.downcase
          Dir.glob(File.join(base.gsub(/[\[\]{}*?]/) { |c| "\\#{c}" }, '**', '*')).each do |f|
            return Util.norm(f) if File.basename(f).downcase == down
          end
          nil
        end

        def cmd_thumb(a)
          path = a['path'].to_s
          return false unless File.file?(path)
          File.open(Thumbnails.cache_file(path), 'wb') { |f| f.write(a['png'].to_s.unpack('m0')[0]) }
          Dialog.emit('thumbs', path => Thumbnails.resolve(path))
          true
        end

        def cmd_close(_a)
          UI.start_timer(0.05, false) { close }
          true
        end

        # ---- model data for simplify / skp / proxy -----------------------------------------
        def cmd_model_data(_a)
          ctx = @ctx
          @mats = []
          @mat_index = {}
          @keys = {}
          @payload_geoms = {}
          nodes = []
          case ctx['mode']
          when 'skp'
            d = ctx['definition']
            nodes << node_for(d, Geom::Transformation.new, d.name, 0, false)
          when 'simplify'
            ctx['instances'].each do |i|
              next unless i.valid?
              nodes << node_for(Util.definition_of(i), i.transformation, i.name.to_s, 0, false)
            end
          when 'proxy'
            ctx['instances'].each do |i|
              next unless i.valid?
              d = Util.definition_of(i)
              key = flat_key(d)
              nodes << { 'n' => d.name, 'm' => i.transformation.to_a, 'g' => key, 'c' => [] }
            end
          end
          { 'materials' => @mats, 'nodes' => nodes, 'geoms' => @payload_geoms }
        end

        def mat_id(mat)
          return -1 unless mat
          return @mat_index[mat] if @mat_index.key?(mat)
          tex = nil
          if mat.texture
            file = File.join(MaterialOps.thumb_dir, "tex_#{Digest::MD5.hexdigest(mat.name)}#{tex_ext(mat.texture)}")
            begin
              mat.texture.write(file) unless File.file?(file)
              tex = { 'path' => Util.norm(file) } if File.file?(file)
            rescue StandardError
              tex = nil
            end
          end
          @mats << { 'name' => Util.utf8(mat.display_name), 'color' => Util.color_hex(mat.color), 'opacity' => mat.alpha, 'tex' => tex }
          @mat_index[mat] = @mats.length - 1
        end

        def tex_ext(tex)
          e = File.extname(tex.filename.to_s).downcase
          %w[.jpg .jpeg .png .bmp].include?(e) ? e : '.png'
        end

        def node_for(d, tr, name, depth, _flat)
          key = geom_key(d)
          children = []
          if depth < 30
            d.entities.each do |e|
              next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
              children << node_for(Util.definition_of(e), e.transformation, e.name.to_s, depth + 1, false)
            end
          end
          { 'n' => Util.utf8(name.to_s.empty? ? d.name : name), 'm' => tr.to_a, 'g' => key, 'c' => children }
        end

        # One geometry per definition (its own faces only, nested instances stay nodes).
        def geom_key(d)
          return @keys[d] if @keys.key?(d)
          faces = d.entities.grep(Sketchup::Face)
          key = nil
          unless faces.empty?
            key = "d#{@keys.length}"
            @payload_geoms[key] = faces_to_parts(faces.map { |f| [f, nil, nil] })
            @geoms[key] = d
          end
          @keys[d] = key
        end

        # Whole definition flattened into one mesh in its own coordinates (for proxies).
        def flat_key(d)
          return @keys[d] if @keys.key?(d)
          list = []
          collect_flat(d.entities, Geom::Transformation.new, nil, list, 0)
          key = "p#{@keys.length}"
          @payload_geoms[key] = faces_to_parts(list)
          @geoms[key] = d
          @keys[d] = key
        end

        def collect_flat(ents, tr, inherited, list, depth)
          return if depth > 30
          ents.each do |e|
            if e.is_a?(Sketchup::Face)
              list << [e, tr, inherited]
            elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
              next if e.hidden?
              collect_flat(Util.definition_of(e).entities, tr * e.transformation, e.material || inherited, list, depth + 1)
            end
          end
        end

        # => [{ 'mat' => id, 'pts' => [...], 'uvs' => [...]|nil, 'tris' => [...] }]
        def faces_to_parts(list)
          parts = {}
          list.each do |face, tr, inherited|
            mat = face.material || inherited
            textured = mat && mat.texture
            mesh = face.mesh(textured ? 1 : 0)
            id = mat_id(mat)
            part = (parts[id] ||= { 'mat' => id, 'pts' => [], 'uvs' => (textured ? [] : nil), 'tris' => [] })
            base = part['pts'].length / 3
            mesh.points.each_with_index do |pt, i|
              p = tr ? pt.transform(tr) : pt
              part['pts'].push(p.x.to_f.round(4), p.y.to_f.round(4), p.z.to_f.round(4))
              next unless part['uvs']
              uv = mesh.uv_at(i + 1, true)
              z = uv.z.to_f.abs < 1e-9 ? 1.0 : uv.z.to_f
              part['uvs'].push((uv.x / z).round(5), (uv.y / z).round(5))
            end
            part['uvs'] = nil if part['uvs'] && part['uvs'].length / 2 != part['pts'].length / 3
            mesh.polygons.each do |poly|
              idx = poly.map { |v| v.abs - 1 + base }
              (1...(idx.length - 1)).each { |k| part['tris'].push(idx[0], idx[k], idx[k + 1]) }
            end
          end
          parts.values
        end

        # ---- receiving results ---------------------------------------------------------------
        def cmd_geom(a)
          @incoming ||= {}
          (@incoming[a['key']] ||= []).concat(a['parts'] || [])
          true
        end

        def cmd_begin(a)
          @incoming = {}
          @import_meta = a
          true
        end

        def cmd_finish(a)
          ctx = @ctx
          opts = a['options'] || {}
          res = case ctx['mode']
                when 'file' then build_import(@import_meta, @incoming, opts)
                when 'skp', 'simplify' then apply_simplify(@incoming, opts)
                when 'proxy' then build_proxies(@incoming, opts)
                end
          ctx['done'] = true
          if ctx['mode'] == 'skp' && ctx['definition'].valid?
            model.place_component(ctx['definition'], false)
          end
          @incoming = {}
          res
        end

        def smooth_flags(opts)
          opts['flat'] ? 0 : SMOOTH
        end

        # Adds faces for parts to entities. mats: array index -> Sketchup::Material|nil
        def add_parts(ents, parts, mats, flags, scale = 1.0)
          parts.each do |part|
            pts = part['pts'] || []
            tris = part['tris'] || []
            next if tris.empty?
            uvs = part['uvs']
            mat = part['mat'].to_i >= 0 ? mats[part['mat'].to_i] : nil
            use_uv = uvs && mat && mat.texture
            mesh = Geom::PolygonMesh.new(pts.length / 3, tris.length / 3)
            index = Array.new(pts.length / 3)
            (0...(pts.length / 3)).each do |i|
              index[i] = mesh.add_point(Geom::Point3d.new(pts[i * 3] * scale, pts[i * 3 + 1] * scale, pts[i * 3 + 2] * scale))
              if use_uv && mesh.respond_to?(:set_uv)
                mesh.set_uv(index[i], Geom::Point3d.new(uvs[i * 2].to_f, uvs[i * 2 + 1].to_f, 1.0), true)
              end
            end
            (0...(tris.length / 3)).each do |t|
              a = index[tris[t * 3]]
              b = index[tris[t * 3 + 1]]
              c = index[tris[t * 3 + 2]]
              next if a == b || b == c || a == c
              mesh.add_polygon(a, b, c)
            end
            next if mesh.count_polygons.zero?
            if ents.length.zero?
              ents.fill_from_mesh(mesh, true, flags, mat, mat)
            else
              ents.add_faces_from_mesh(mesh, flags, mat, mat)
            end
          end
        end

        def make_materials(list, opts)
          dir = Util.join(Util.utf8(Sketchup.temp_dir), 'banian_import')
          FileUtils.mkdir_p(dir)
          list.map do |m|
            mat = model.materials.add(m['name'].to_s.empty? ? 'Material' : m['name'].to_s)
            tex = m['tex']
            file = nil
            if tex && tex['path'] && File.file?(tex['path'].to_s)
              file = tex['path']
            elsif tex && tex['data']
              ext = tex['ext'] || '.png'
              file = File.join(dir, "#{Digest::MD5.hexdigest(tex['data'][0, 2000] + m['name'].to_s)}#{ext}")
              File.open(file, 'wb') { |f| f.write(tex['data'].unpack('m0')[0]) }
            end
            if file
              begin
                mat.texture = file
                mat.texture.size = [39.37, 39.37] if mat.texture
              rescue StandardError => e
                Util.log_error(e, 'import texture')
              end
            end
            if m['color'] && (!mat.texture || opts['tint'])
              c = m['color'].to_s.sub('#', '')
              mat.color = Sketchup::Color.new(c[0, 2].to_i(16), c[2, 2].to_i(16), c[4, 2].to_i(16)) if c.length == 6
            end
            op = m['opacity'].to_f
            mat.alpha = [[op, 0.0].max, 1.0].min if m['opacity'] && op < 0.999
            mat
          end
        end

        # ---- import from file ------------------------------------------------------------------
        def build_import(meta, geoms, opts)
          meta ||= {}
          path = @ctx['path'].to_s
          name = File.basename(path, '.*')
          k = (meta['buildScale'] || 1).to_f
          k = 1.0 if k <= 0
          faces = 0
          root = nil
          model.start_operation(I18n.t(:op_import), true)
          begin
            mats = make_materials(meta['materials'] || [], opts)
            flags = smooth_flags(opts)
            uses = Hash.new(0)
            count_uses(meta['nodes'] || [], uses)
            defs = {}
            root = model.definitions.add(name)
            (meta['nodes'] || []).each do |n|
              faces += build_node(root.entities, n, geoms, mats, flags, defs, uses, opts, k)
            end
            root.set_attribute(DICT, 'source', path)
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            raise e
          end
          Settings.record_use(path)
          ModelOps.last_definition = root
          model.place_component(root, false) if root.entities.length > 0
          { 'faces' => faces }
        end

        def count_uses(nodes, uses)
          nodes.each do |n|
            uses[n['g']] += 1 if n['g']
            count_uses(n['c'] || [], uses)
          end
        end

        def transformation(arr)
          return Geom::Transformation.new unless arr && arr.length == 16
          Geom::Transformation.new(arr.map(&:to_f))
        end

        def build_node(ents, node, geoms, mats, flags, defs, uses, opts, k)
          tr = transformation(node['m'])
          key = node['g']
          kids = node['c'] || []
          faces = 0
          shared = key && uses[key] > 1 && opts['components'] != false
          if key && kids.empty? && shared
            d = definition_for(key, node, geoms, mats, flags, defs, k)
            inst = ents.add_instance(d, tr * scale_tr(k))
            inst.name = Util.utf8(node['n'].to_s)
            return count_faces(d)
          end
          grp = ents.add_group
          grp.name = Util.utf8(node['n'].to_s)
          if key
            if shared || k != 1.0
              d = definition_for(key, node, geoms, mats, flags, defs, k)
              grp.entities.add_instance(d, scale_tr(k))
              faces += count_faces(d)
            else
              add_parts(grp.entities, geoms[key] || [], mats, flags)
              faces += grp.entities.grep(Sketchup::Face).length
            end
          end
          kids.each { |c| faces += build_node(grp.entities, c, geoms, mats, flags, defs, uses, opts, k) }
          if grp.entities.length.zero?
            grp.erase!
          else
            grp.transformation = tr
          end
          faces
        end

        def scale_tr(k)
          k == 1.0 ? Geom::Transformation.new : Geom::Transformation.scaling(1.0 / k)
        end

        def definition_for(key, node, geoms, mats, flags, defs, k)
          return defs[key] if defs[key]
          d = model.definitions.add(Util.utf8(node['n'].to_s.empty? ? 'Mesh' : node['n'].to_s))
          add_parts(d.entities, geoms[key] || [], mats, flags, k)
          defs[key] = d
        end

        def count_faces(d)
          d.entities.grep(Sketchup::Face).length
        end

        # ---- simplify definitions in place --------------------------------------------------------
        def model_materials
          list = []
          @mat_index.each { |m, i| list[i] = m }
          list
        end

        def apply_simplify(geoms, opts)
          mats = model_materials
          flags = smooth_flags(opts)
          model.start_operation(I18n.t(:op_simplify), true)
          before = 0
          after = 0
          begin
            geoms.each do |key, parts|
              d = @geoms[key]
              next unless d && d.valid?
              old = d.entities.select { |e| e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge) }
              before += old.count { |e| e.is_a?(Sketchup::Face) }
              d.entities.erase_entities(old)
              add_parts(d.entities, parts, mats, flags)
              after += count_faces(d)
            end
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            raise e
          end
          { 'before' => before, 'after' => after }
        end

        # ---- decimated proxies ---------------------------------------------------------------------
        def build_proxies(geoms, opts)
          mats = model_materials
          flags = smooth_flags(opts)
          model.start_operation(I18n.t(:op_proxy), true)
          done = 0
          begin
            geoms.each do |key, parts|
              full = @geoms[key]
              next unless full && full.valid? && !Proxy.proxy?(full)
              src = Proxy.ensure_source(full)
              pdef = model.definitions.add("#{full.name} [Proxy]")
              add_parts(pdef.entities, parts, mats, flags)
              Proxy.tag(pdef, src, 'decimated', full.name)
              full.instances.to_a.each { |i| i.definition = pdef }
              full.set_attribute(Proxy::PDICT, 'role', 'full')
              Proxy.remove_definition(full) if Settings['proxy_remove_full']
              done += 1
            end
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            raise e
          end
          Dialog.emit('proxy_stats', Proxy.stats)
          { 'proxies' => done }
        end
      end
    end
  end
end
