# HtmlDialog controller.
require 'json'

module BanianStudio
  module FloorStudio
    module Studio
      PREF = 'BanianFloorStudio'.freeze

      class SelObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(_sel)
          Studio.selection_changed
        end

        def onSelectionCleared(_sel)
          Studio.selection_changed
        end

        def onSelectionAdded(_sel, _ent)
          Studio.selection_changed
        end

        def onSelectionRemoved(_sel, _ent)
          Studio.selection_changed
        end
      end

      # Picks a start point in the model (with inference snapping).
      class PickTool
        def activate
          @ip = Sketchup::InputPoint.new
          Sketchup.status_text = 'Banian Floor Studio: click the start point of the pattern (Esc = cancel)'
        end

        def deactivate(view)
          view.invalidate
        end

        def onMouseMove(_flags, x, y, view)
          @ip.pick(view, x, y)
          view.tooltip = @ip.tooltip if @ip.valid?
          view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @ip.valid?
          Studio.anchor_picked(@ip.position)
          Sketchup.active_model.select_tool(nil)
        end

        def onCancel(_reason, _view)
          Sketchup.active_model.select_tool(nil)
        end

        def draw(view)
          @ip.draw(view) if @ip && @ip.valid?
        end

        def getExtents
          Sketchup.active_model.bounds
        end
      end

      module_function

      def model
        Sketchup.active_model
      end

      def open(mode = nil)
        @want_mode = mode
        if @dlg && @dlg.visible?
          send_js('mode', 'mode' => mode) if mode
          @dlg.bring_to_front
          return
        end
        @dlg = UI::HtmlDialog.new(
          :dialog_title => 'Banian Floor Studio',
          :preferences_key => PREF,
          :scrollable => false,
          :resizable => true,
          :width => 420, :height => 820,
          :min_width => 360, :min_height => 520,
          :style => UI::HtmlDialog::STYLE_DIALOG
        )
        @dlg.set_file(File.join(PATH, 'ui', 'html', 'index.html'))
        register(@dlg)
        @dlg.set_on_closed { detach_observer } if @dlg.respond_to?(:set_on_closed)
        @dlg.show
      end

      def register(d)
        d.add_action_callback('ready') { |_c, _a| on_ready }
        d.add_action_callback('preview') { |_c, a| safe { on_preview(parse(a)) } }
        d.add_action_callback('apply') { |_c, a| safe { on_apply(parse(a)) } }
        d.add_action_callback('materials') { |_c, _a| send_js('materials', 'list' => Materials.list(model)) }
        d.add_action_callback('texture_data') { |_c, a| safe { on_texture_data(parse(a)) } }
        d.add_action_callback('apply_texture') { |_c, a| safe { on_apply_texture(parse(a)) } }
        d.add_action_callback('save_state') { |_c, a| save_state(a.to_s) }
        d.add_action_callback('close') { |_c, _a| d.close }
        d.add_action_callback('pick_point') { |_c, _a| model.select_tool(PickTool.new) }
        d.add_action_callback('set_anchor_local') { |_c, a| safe { on_set_anchor_local(parse(a)) } }
      end

      def parse(a)
        a.is_a?(String) ? JSON.parse(a) : (a || {})
      end

      def safe
        yield
      rescue TooManyTiles => e
        send_js('error', 'code' => 'too_many', 'detail' => e.message)
      rescue StandardError => e
        puts "[Banian Floor Studio] #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        send_js('error', 'code' => 'error', 'detail' => "#{e.class}: #{e.message}")
      end

      def send_js(type, data = {})
        return unless @dlg
        @dlg.execute_script("FS.recv(#{JSON.generate(data.merge('type' => type))})")
      end

      def on_ready
        attach_observer
        units = 'mm'
        begin
          lu = model.options['UnitsOptions']['LengthUnit']
          units = { 0 => 'in', 1 => 'in', 2 => 'mm', 3 => 'cm', 4 => 'm' }[lu] || 'mm'
        rescue StandardError
          units = 'mm'
        end
        send_js('init', 'state' => load_state, 'units' => units, 'mode' => @want_mode,
                        'materials' => Materials.list(model), 'version' => VERSION)
        selection_changed
      end

      def attach_observer
        return if @obs_model == model
        detach_observer
        @obs = SelObserver.new
        model.selection.add_observer(@obs)
        @obs_model = model
      end

      def detach_observer
        @obs_model.selection.remove_observer(@obs) if @obs_model && @obs
      rescue StandardError
        nil
      ensure
        @obs_model = nil
      end

      def selection_changed
        return unless @dlg && @dlg.visible?
        return if @sel_timer
        @sel_timer = UI.start_timer(0.15, false) do
          @sel_timer = nil
          safe { send_selection }
        end
      end

      def send_selection
        g = edit_target
        if g
          params = JSON.parse(g.get_attribute(Builder::DICT, 'params').to_s) rescue {}
          send_js('source', 'kind' => 'group', 'params' => params)
        else
          n = model.selection.grep(Sketchup::Face).length
          send_js('source', 'kind' => n > 0 ? 'face' : 'none', 'count' => n)
        end
      end

      def edit_target
        sel = model.selection
        return nil unless sel.length == 1
        e = sel.first
        Builder.generated?(e) ? e : nil
      end

      def source(p)
        g = edit_target
        return group_source(g) if g
        faces = model.selection.grep(Sketchup::Face)
        unless faces.empty?
          list = sources(faces, p)
          return list.first.merge(:count => faces.length, :nsrc => list.length)
        end
        { :kind => 'none', :region => Region.sample, :world_origin => [0, 0], :frame => Geom::Transformation.new }
      end

      # Selected faces -> work units. Faces joined by soft/smooth/hidden edges
      # (curved surfaces) or coplanar neighbours become ONE unrolled surface.
      def sources(faces, p)
        Surface.components(faces).map do |comp|
          if comp.length == 1
            Region.from_face(comp[0], p).merge(:kind => 'face', :face => comp[0], :faces => comp)
          else
            sf = Surface.from_faces(comp, p)
            base = { :kind => 'face', :face => sf.root, :faces => comp, :region => sf.region,
                     :world_origin => sf.world_origin }
            sf.planar ? base.merge(:frame => sf.facets[0].inv) : base.merge(:surface => sf, :frame => nil)
          end
        end
      end

      def group_source(g)
        reg = Region.from_json_h(JSON.parse(g.get_attribute(Builder::DICT, 'region')))
        sj = g.get_attribute(Builder::DICT, 'surface')
        if sj
          sf = Surface.from_h(JSON.parse(sj), reg)
          return { :kind => 'group', :group => g, :region => reg, :surface => sf, :gxf => g.transformation,
                   :world_origin => sf.world_origin }
        end
        wo = ORIGIN.transform(g.transformation.inverse)
        { :kind => 'group', :group => g, :region => reg, :world_origin => [wo.x.to_f, wo.y.to_f],
          :frame => g.transformation }
      end

      # context coords <-> unrolled/local 2D for any source
      def src_to2d(src, pt)
        if src[:surface]
          q = src[:gxf] ? pt.transform(src[:gxf].inverse) : pt
          return src[:surface].to2d(q)
        end
        q = pt.transform(src[:frame].inverse)
        [q.x.to_f, q.y.to_f]
      end

      def src_to3d(src, x, y)
        if src[:surface]
          q = src[:surface].to3d([x, y])
          return src[:gxf] ? q.transform(src[:gxf]) : q
        end
        Geom::Point3d.new(x, y, 0).transform(src[:frame])
      end

      # Colour palette matching Builder.material_ctx ordering, without
      # touching the model.
      def palette(p)
        base = []
        p[:materials].each_with_index do |n, i|
          m = model.materials[n]
          base << [m, Materials.hex(m.color), (p[:weights][i] || 1.0).to_f] if m
        end
        base = [[nil, '#d9d4cc', 1.0]] if base.empty?
        cols = []
        wts = []
        base.each do |m, hx, w|
          k = (p[:shades] > 1 && !(m && m.texture)) ? p[:shades] : 1
          k.times do |j|
            f = 1.0
            if j > 0
              f = 1.0 + p[:shade_amount] * ((j.to_f / (k - 1)) * 2 - 1)
              f = 1.0 + p[:shade_amount] * 0.5 if (f - 1.0).abs < 1.0e-3
            end
            cols << shade_hex(hx, f)
            wts << w / k
          end
        end
        [cols, wts]
      end

      def shade_hex(hx, f)
        r, g, b = Materials.parse_color(hx, [200, 200, 200])
        format('#%02x%02x%02x', Materials.clamp255(r * f), Materials.clamp255(g * f), Materials.clamp255(b * f))
      end

      def grout_hex(p)
        n = p[:grout_mat].to_s
        m = n.empty? ? nil : model.materials[n]
        return Materials.hex(m.color) if m
        rgb = Materials.parse_color(p[:grout_color], [138, 133, 128])
        format('#%02x%02x%02x', *rgb)
      end

      # Custom start point (stored in the parent/context coords) -> local 2D.
      def custom_local(src, p)
        ap = p[:anchor_pt]
        return nil unless ap
        src_to2d(src, Geom::Point3d.new(ap[0], ap[1], ap[2]))
      end

      def lay_opts(src, p, world_origin = nil)
        { :world_origin => world_origin || src[:world_origin], :custom => custom_local(src, p) }
      end

      # Point picked in the model (world coords) -> active context coords.
      def anchor_picked(world_pt)
        pt = world_pt.transform(model.edit_transform.inverse)
        send_js('anchor', 'pt' => [mm(pt.x.to_f), mm(pt.y.to_f), mm(pt.z.to_f)])
        @dlg.bring_to_front if @dlg && @dlg.respond_to?(:bring_to_front)
      end

      # Click on the 2D preview (local mm) -> context coords of current source.
      def on_set_anchor_local(data)
        p = Params.from_ui(data['state'] || {})
        src = source(p)
        q = src_to3d(src, data['x'].to_f / 25.4, data['y'].to_f / 25.4)
        send_js('anchor', 'pt' => [mm(q.x.to_f), mm(q.y.to_f), mm(q.z.to_f)])
      end

      def mm(v)
        (v * 25.4).round(1)
      end

      def on_preview(ui)
        p = Params.from_ui(ui)
        src = source(p)
        lay = Patterns.layout(src[:region], p, lay_opts(src, p, src[:world_origin]))
        tiles = lay[:tiles]
        cols, wts = palette(p)
        Materials.assign(tiles, Patterns.norm(p).merge(:mat_mode => p[:mat_mode]), wts, 1)
        reg = src[:region]
        out = {
          'source' => src[:kind],
          'count' => src[:count] || 0,
          'curved' => !src[:surface].nil?,
          'overlap' => src[:surface] ? src[:surface].overlap : false,
          'region' => { 'outer' => reg[:outer].map { |q| [mm(q[0]), mm(q[1])] },
                        'holes' => reg[:holes].map { |h| h.map { |q| [mm(q[0]), mm(q[1])] } } },
          'palette' => cols,
          'grout' => grout_hex(p),
          'full' => tiles.count { |t| t.state == :inside },
          'cut' => tiles.count { |t| t.state == :boundary },
          'area' => (region_area(reg) * 0.00064516).round(2),
          'marker' => [mm(lay[:marker][0]), mm(lay[:marker][1])]
        }
        if tiles.length <= 15_000
          out['tiles'] = tiles.map do |t|
            a = [t.state == :inside ? 0 : 1, t.mat]
            t.poly.each { |q| a << mm(q[0]) << mm(q[1]) }
            a
          end
        else
          out['tiles'] = []
          out['dense'] = true
        end
        send_js('preview', out)
      end

      def region_area(reg)
        a = Geom2D.area(reg[:outer])
        reg[:holes].each { |h| a -= Geom2D.area(h) }
        a
      end

      # ---------------- apply ----------------
      def on_apply(ui)
        p = Params.from_ui(ui)
        mode = p[:mode].to_s
        if mode == 'texture'
          on_texture_data(ui)
          return
        end
        g = edit_target
        faces = model.selection.grep(Sketchup::Face)
        if g.nil? && faces.empty?
          send_js('error', 'code' => 'no_face')
          return
        end
        t0 = Time.now
        stats = { 'full' => 0, 'cut' => 0 }
        model.start_operation('Floor Studio', true)
        begin
          if g
            stats = rebuild(g, ui)
          else
            created = []
            list = sources(faces, p)
            list.each_with_index do |s, i|
              f = s[:face]
              next unless f.valid?
              Sketchup.status_text = "Banian Floor Studio: #{i + 1}/#{list.length}"
              lay = Patterns.layout(s[:region], p, lay_opts(s, p))
              ents = f.parent.entities
              r =
                if mode == 'divide'
                  if s[:surface]
                    Builder.divide_surface(model, ents, s[:surface], lay, s[:region], p)
                  else
                    Builder.divide(model, f, s[:frame], lay, s[:region], p)
                  end
                else
                  grp = ents.add_group
                  grp.transformation = s[:frame] if s[:frame]
                  grp.name = "Floor Studio - #{Patterns.norm(p)[:pattern]}"
                  rr = Builder.build_3d(model, grp.entities, lay, s[:region], p, s[:surface])
                  Builder.store(grp, s[:region], ui, '3d', s[:surface])
                  s[:faces].each { |ff| ff.hidden = true } unless p[:keep_face]
                  created << grp
                  rr
                end
              stats['full'] += r['full'].to_i
              stats['cut'] += r['cut'].to_i
            end
            unless created.empty?
              model.selection.clear
              model.selection.add(created)
            end
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        ensure
          Sketchup.status_text = ''
        end
        stats['time'] = (Time.now - t0).round(2)
        send_js('done', stats)
      end

      def rebuild(g, ui)
        p = Params.from_ui(ui)
        src = group_source(g)
        reg = src[:region]
        lay = Patterns.layout(reg, p, lay_opts(src, p))
        ents = g.respond_to?(:definition) ? g.definition.entities : g.entities
        ents.clear!
        r = Builder.build_3d(model, ents, lay, reg, p, src[:surface])
        g.name = "Floor Studio - #{Patterns.norm(p)[:pattern]}"
        Builder.store(g, reg, ui, '3d', src[:surface])
        Builder.purge_tile_defs(model)
        r
      end

      # Re-generate selected layouts with a new random seed (no dialog).
      def shuffle
        groups = model.selection.select { |e| Builder.generated?(e) }
        return UI.beep if groups.empty?
        model.start_operation('Floor Studio Shuffle', true)
        groups.each do |g|
          ui = JSON.parse(g.get_attribute(Builder::DICT, 'params').to_s)
          ui['seed'] = rand(1..99_999)
          rebuild(g, ui)
        end
        model.commit_operation
        selection_changed
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("Banian Floor Studio: #{e.message}")
      end

      # ---------------- texture mode ----------------
      def on_texture_data(ui)
        p = Params.from_ui(ui)
        w, h, tiles, seamless, np = Patterns.texture_tiles(p)
        cols, wts = palette(p)
        Materials.assign(tiles, np.merge(:mat_mode => p[:mat_mode], :seed => p[:seed]), wts, 1)
        send_js('texture_data',
                'w' => mm(w), 'h' => mm(h), 'seamless' => seamless, 'palette' => cols, 'grout' => grout_hex(p),
                'tiles' => tiles.map { |t| a = [t.mat]; t.poly.each { |q| a << mm(q[0]) << mm(q[1]) }; a })
      end

      def on_apply_texture(data)
        ui = data['state'] || {}
        p = Params.from_ui(ui)
        faces = model.selection.grep(Sketchup::Face)
        if faces.empty?
          send_js('error', 'code' => 'no_face')
          return
        end
        png = data['png'].to_s.sub(%r{\Adata:image/png;base64,}, '')
        dir = Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir : (require('tmpdir') && Dir.tmpdir)
        file = File.join(dir, "bfs_pattern_#{Time.now.to_i}_#{rand(1000)}.png")
        File.open(file, 'wb') { |f| f.write(png.unpack('m').first) }
        w = data['w'].to_f / 25.4
        h = data['h'].to_f / 25.4
        name = "BFS Pattern #{Patterns.norm(p)[:pattern]}"
        model.start_operation('Floor Studio Texture', true)
        begin
          mat = Builder.texture_material(model, file, w, h, name)
          sources(faces, p).each do |s|
            o = texture_origin(s, p)
            if s[:surface]
              s[:surface].facets.each do |fc|
                Builder.map_texture(fc.face, fc.inv, o, p[:angle], mat, w, h) if fc.face && fc.face.valid?
              end
            else
              s[:faces].each { |f| Builder.map_texture(f, s[:frame], o, p[:angle], mat, w, h) }
            end
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        File.delete(file) rescue nil
        send_js('done', 'full' => 0, 'cut' => 0, 'texture' => true)
      end

      def texture_origin(s, p)
        np = Patterns.norm(p)
        Patterns.origin_for(s[:region], np, lay_opts(s, p))[0]
      end

      # ---------------- state ----------------
      def save_state(json)
        Sketchup.write_default(PREF, 'state', [json].pack('m0'))
      end

      def load_state
        s = Sketchup.read_default(PREF, 'state', nil)
        return nil if s.nil? || s.to_s.empty?
        JSON.parse(s.to_s.unpack('m').first.force_encoding('UTF-8'))
      rescue StandardError
        nil
      end
    end
  end
end
