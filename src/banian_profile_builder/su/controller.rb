# encoding: UTF-8
# Banian Profile Builder - panel (HtmlDialog) and commands.

require 'json'

module BanianStudio
  module ProfileBuilder
    module Controller
      UI_DIR = File.join(PLUGIN_DIR, 'ui')

      MSG = {
        'en' => {
          'select_path' => 'Select edges, curves or faces to use as a path first.',
          'select_face' => 'Select one face to save as a profile.',
          'select_obj' => 'Select a Banian member or assembly first.',
          'profile_name' => 'Profile name',
          'assembly_name' => 'Assembly name',
          'error' => 'Banian Profile Builder error: '
        },
        'fa' => {
          'select_path' => 'اول خط‌ها، کمان‌ها یا سطح‌هایی که مسیر هستند را انتخاب کنید.',
          'select_face' => 'یک سطح (Face) را برای ذخیره به‌عنوان پروفایل انتخاب کنید.',
          'select_obj' => 'اول یک پروفایل یا اسمبلی بانیان را انتخاب کنید.',
          'profile_name' => 'Profile name / نام پروفایل',
          'assembly_name' => 'Assembly name / نام اسمبلی',
          'error' => 'خطای بانیان پروفایل بیلدر: '
        }
      }.freeze

      DEFAULT_MEMBER = {
        'profile' => 'rect', 'params' => { 'w' => 89, 'h' => 38 }, 'anchor' => 'mc',
        'rotation' => 0, 'flip' => false, 'offset_u' => 0, 'offset_v' => 0, 'material' => ''
      }.freeze

      module_function

      # ---------- state ---------------------------------------------------

      def lang
        Library.get('lang', 'fa')
      end

      def t(key)
        (MSG[lang] || MSG['en'])[key] || MSG['en'][key]
      end

      def mode
        @mode ||= Library.get('mode', 'member')
      end

      def spec_for(kind = mode)
        @specs ||= {}
        @specs[kind] ||= begin
          if kind == 'assembly'
            Library.get('assembly_spec', nil) || default_assembly
          else
            Library.get('member_spec', nil) || JSON.parse(JSON.generate(DEFAULT_MEMBER))
          end
        end
      end

      def default_assembly
        { 'preset' => 'stud_wall', 'preset_params' => Presets.defaults('stud_wall'),
          'rows' => Presets.rows_for('stud_wall', {}), 'openings' => [], 'flip' => false }
      end

      def set_spec(kind, spec)
        @specs ||= {}
        @specs[kind] = spec
        @mode = kind
        Library.set(kind == 'assembly' ? 'assembly_spec' : 'member_spec', spec)
        Library.set('mode', kind)
      end

      # ---------- dialog --------------------------------------------------

      def show
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          return
        end
        @ready = false
        @queue = []
        @dialog = UI::HtmlDialog.new(
          dialog_title: 'Banian Profile Builder', preferences_key: 'BanianProfileBuilder.Panel',
          scrollable: true, resizable: true, width: 410, height: 780, left: 120, top: 120,
          min_width: 340, min_height: 420, style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_file(File.join(UI_DIR, 'panel.html'))
        @dialog.add_action_callback('cmd') do |_ctx, payload|
          handle(payload)
          nil
        end
        @dialog.set_on_closed { @ready = false } if @dialog.respond_to?(:set_on_closed)
        @dialog.show
      end

      def visible?
        @dialog && @ready && @dialog.visible?
      end

      def send_js(msg)
        return unless @dialog
        js = "BPB.receive(#{JSON.generate(msg)})"
        if @ready
          @dialog.execute_script(js)
        else
          (@queue ||= []) << js
        end
      end

      def handle(payload)
        msg = payload.is_a?(String) ? JSON.parse(payload) : payload
        case msg['type']
        when 'ready'
          @ready = true
          push_init
          (@queue || []).each { |js| @dialog.execute_script(js) }
          @queue = []
          push_selection
        when 'settings'
          Library.set('lang', msg['lang']) if msg['lang']
          Library.set('units', msg['units']) if msg['units']
        when 'set_spec' then set_spec(msg['kind'], msg['spec'])
        when 'preview' then send_js('type' => 'preview', 'kind' => msg['kind'], 'data' => preview(msg['kind'], msg['spec']))
        when 'update_selected' then update_selected(msg['kind'], msg['spec'], msg['similar'])
        when 'draw'
          set_spec(msg['kind'], msg['spec']) if msg['spec']
          Sketchup.active_model.select_tool(DrawTool.new)
        when 'build_selection'
          set_spec(msg['kind'], msg['spec']) if msg['spec']
          build_on_selection
        when 'extend' then Sketchup.active_model.select_tool(ExtendTool.new)
        when 'rotate' then rotate_selected
        when 'flip' then flip_selected
        when 'save_face' then save_face_profile
        when 'save_assembly' then save_assembly(msg['spec'])
        when 'remove_library' then Library.remove(msg['id']); push_library
        when 'preset_rows'
          send_js('type' => 'preset_rows', 'rows' => Presets.rows_for(msg['preset'], msg['params']))
        when 'materials' then push_materials
        when 'quantities' then push_quantities
        when 'set_price'
          Quantities.set_price(Sketchup.active_model, msg['key'], msg['price'])
        when 'select_key' then Quantities.select_key(Sketchup.active_model, msg['key'])
        when 'export_csv' then export_csv(msg['headers'], msg['rows'])
        when 'open_url' then UI.openURL(msg['url'].to_s) if msg['url'].to_s =~ /\Ahttps?:/
        end
      rescue StandardError => e
        report_error(e)
      end

      def report_error(e)
        puts "#{e.class}: #{e.message}\n#{(e.backtrace || [])[0, 8].join("\n")}"
        send_js('type' => 'toast', 'level' => 'error', 'text' => t('error') + e.message)
      end

      def push_init
        send_js(
          'type' => 'init', 'version' => VERSION,
          'catalog' => Profiles.catalog_json, 'presets' => Presets.json,
          'lang' => lang, 'units' => Library.get('units', 'mm'), 'mode' => mode,
          'member' => spec_for('member'), 'assembly' => spec_for('assembly'),
          'library' => Library.data, 'materials' => material_names
        )
      end

      def push_library
        send_js('type' => 'library', 'library' => Library.data)
      end

      def material_names
        Sketchup.active_model.materials.map { |m| m.name }.sort
      end

      def push_materials
        send_js('type' => 'materials', 'materials' => material_names)
      end

      def push_quantities
        send_js('type' => 'quantities', 'rows' => Quantities.report(Sketchup.active_model))
      end

      # ---------- selection ----------------------------------------------

      def selected_pb(kind = nil)
        Sketchup.active_model.selection.select { |e| Builder.pb?(e) && (kind.nil? || Builder.kind(e) == kind) }
      end

      def selection_changed
        return unless visible?
        return if @sel_pending
        @sel_pending = true
        UI.start_timer(0.05, false) do
          @sel_pending = false
          push_selection
        end
      end

      def push_selection
        items = selected_pb
        if items.empty?
          send_js('type' => 'selection', 'item' => nil)
          return
        end
        info = Builder.read(items[0])
        return unless info
        len = PathOps.length(info['path'], info['closed']) * 25.4
        send_js('type' => 'selection', 'item' => {
                  'kind' => info['kind'], 'spec' => info['spec'], 'count' => items.size,
                  'closed' => info['closed'], 'length_mm' => len.round(1)
                })
      end

      # ---------- coordinates --------------------------------------------
      # Entities in an open group/component: before SketchUp 2020 the API
      # reported their positions in world space, from 2020 in local space.
      # InputPoints are always world space. New entities are always local.

      def legacy_world_positions?
        Sketchup.version.to_i < 20
      end

      def world_to_local(model)
        model.edit_transform.inverse
      end

      def entity_point(model, p)
        legacy_world_positions? ? world_to_local(model) * p : p
      end

      def entity_vector(model, v)
        legacy_world_positions? ? world_to_local(model) * v : v
      end

      # ---------- building -----------------------------------------------

      def collect_paths(model)
        sel = model.selection
        faces = sel.grep(Sketchup::Face)
        face_edges = {}
        faces.each { |f| f.edges.each { |e| face_edges[e] = true } }
        paths = []
        faces.each do |f|
          pts = f.outer_loop.vertices.map { |v| entity_point(model, v.position).to_a }
          n = entity_vector(model, f.normal).to_a
          paths << [pts, true, n]
        end
        edges = sel.grep(Sketchup::Edge).reject { |e| face_edges[e] }
        chains(edges).each do |pts, closed|
          paths << [pts.map { |p| entity_point(model, p).to_a }, closed, nil]
        end
        paths
      end

      # Splits a set of edges into connected chains (open or closed).
      def chains(edges)
        set = {}
        edges.each { |e| set[e] = true }
        adj = Hash.new { |h, k| h[k] = [] }
        edges.each { |e| adj[e.start] << e; adj[e.end] << e }
        visited = {}
        out = []
        walk = lambda do |v, e|
          pts = [v.position]
          loop do
            visited[e] = true
            v = e.other_vertex(v)
            pts << v.position
            break if adj[v].size != 2
            e = adj[v].find { |x| !visited[x] }
            break unless e
          end
          pts
        end
        adj.keys.select { |v| adj[v].size != 2 }.each do |v|
          adj[v].each { |e| out << [walk.call(v, e), false] unless visited[e] }
        end
        edges.each do |e|
          next if visited[e]
          pts = walk.call(e.start, e)
          pts.pop if pts.size > 1 && pts[0] == pts[-1]
          out << [pts, true]
        end
        out
      end

      def build_on_selection
        model = Sketchup.active_model
        paths = collect_paths(model)
        if paths.empty?
          UI.messagebox(t('select_path'))
          return
        end
        k = mode
        spec = spec_for(k)
        model.start_operation('Banian Build', true)
        groups = paths.map { |pts, closed, up| Builder.create(model.active_entities, k, spec, pts, closed, up) }.compact
        model.commit_operation
        model.selection.clear
        model.selection.add(groups) unless groups.empty?
        groups
      rescue StandardError => e
        model.abort_operation if model
        report_error(e)
        []
      end

      def build_path(points_local, closed)
        model = Sketchup.active_model
        k = mode
        model.start_operation('Banian Build', true)
        g = Builder.create(model.active_entities, k, spec_for(k), points_local, closed, nil)
        model.commit_operation
        g
      rescue StandardError => e
        model.abort_operation
        report_error(e)
        nil
      end

      def update_selected(kind, spec, similar = false)
        model = Sketchup.active_model
        targets = selected_pb(kind)
        return if targets.empty?
        if similar && kind == 'member'
          old = Builder.read(targets[0])
          if old
            key = spec_key(old['spec'])
            Quantities.pb_groups(model).each do |g|
              next if targets.include?(g) || Builder.kind(g) != 'member'
              i = Builder.read(g)
              targets << g if i && spec_key(i['spec']) == key
            end
          end
        end
        ids = targets.map(&:entityID).sort
        now = Time.now
        transparent = @last_ids == ids && @last_t && now - @last_t < 2.0
        @last_ids = ids
        @last_t = now
        model.start_operation('Banian Edit', true, false, transparent ? true : false)
        targets.each { |g| Builder.rebuild(g, spec) }
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        report_error(e)
      end

      def spec_key(spec)
        s = spec.dup
        s.delete('name')
        JSON.generate(s.keys.sort.map { |k| [k, s[k]] })
      end

      def modify_selected(name)
        model = Sketchup.active_model
        targets = selected_pb
        if targets.empty?
          UI.messagebox(t('select_obj'))
          return
        end
        model.start_operation(name, true)
        targets.each do |g|
          info = Builder.read(g)
          next unless info
          yield info['kind'], info['spec']
          Builder.rebuild(g, info['spec'])
        end
        model.commit_operation
        push_selection
      rescue StandardError => e
        model.abort_operation
        report_error(e)
      end

      def rotate_selected
        modify_selected('Banian Rotate') do |kind, spec|
          spec['rotation'] = ((spec['rotation'] || 0).to_i + 90) % 360 if kind == 'member'
          spec['flip'] = !spec['flip'] if kind == 'assembly'
        end
      end

      def flip_selected
        modify_selected('Banian Flip') { |_k, spec| spec['flip'] = !spec['flip'] }
      end

      # ---------- library ------------------------------------------------

      def save_face_profile
        model = Sketchup.active_model
        faces = model.selection.grep(Sketchup::Face)
        if faces.size != 1
          UI.messagebox(t('select_face'))
          return
        end
        f = faces[0]
        n = f.normal
        z = Geom::Vector3d.new(0, 0, 1)
        x = n.parallel?(z) ? Geom::Vector3d.new(1, 0, 0) : z.cross(n)
        x.normalize!
        y = n.cross(x)
        y.normalize!
        o = f.outer_loop.vertices[0].position
        loops = ([f.outer_loop] + (f.loops - [f.outer_loop])).map do |lp|
          lp.vertices.map do |v|
            d = v.position - o
            [(d.dot(x) * 25.4).round(3), (d.dot(y) * 25.4).round(3)]
          end
        end
        bb = Profiles.bbox(loops)
        loops = loops.map { |l| l.map { |q| [(q[0] - bb[0]).round(3), (q[1] - bb[1]).round(3)] } }
        res = UI.inputbox([t('profile_name')], ['My profile'], 'Banian Profile Builder')
        return unless res
        name = res[0].to_s.strip
        name = 'My profile' if name.empty?
        id = Library.add_profile(name, loops)
        bb = Profiles.bbox(loops)
        spec = spec_for('member').merge('profile' => id, 'custom_loops' => loops, 'custom_name' => name,
                                        'params' => { 'w' => (bb[2] - bb[0]).round(2), 'h' => (bb[3] - bb[1]).round(2) })
        set_spec('member', spec)
        push_library
        send_js('type' => 'use_spec', 'kind' => 'member', 'spec' => spec)
      end

      def save_assembly(spec)
        res = UI.inputbox([t('assembly_name')], ['My assembly'], 'Banian Profile Builder')
        return unless res
        name = res[0].to_s.strip
        name = 'My assembly' if name.empty?
        Library.add_assembly(name, spec)
        push_library
      end

      def export_csv(headers, rows)
        path = UI.savepanel('Export quantities (CSV)', '', 'banian-quantities.csv')
        return unless path
        path += '.csv' unless path =~ /\.csv\z/i
        File.write(path, Quantities.to_csv(rows, headers), encoding: 'UTF-8')
        send_js('type' => 'toast', 'text' => File.basename(path))
      end

      # ---------- preview -------------------------------------------------

      def preview(kind, spec)
        if kind == 'assembly'
          flip = spec['flip'] ? true : false
          parts = (spec['rows'] || []).map do |row0|
            row = Assembly.apply_global_flip(row0, flip)
            loops = Profiles.placed_loops(Assembly.row_profile_spec(row))
            hidden = row['visible'] == false
            if row['type'] == 'repeat'
              bb = Profiles.bbox(loops)
              v0 = row['v0'].to_f; v1 = v0 + row['length'].to_f
              { 'type' => 'repeat', 'hidden' => hidden,
                'loops' => [[[bb[0], v0], [bb[2], v0], [bb[2], v1], [bb[0], v1]]] }
            else
              { 'type' => 'layer', 'hidden' => hidden, 'loops' => loops }
            end
          end
          { 'parts' => parts }
        else
          { 'parts' => [{ 'type' => 'layer', 'loops' => Profiles.placed_loops(spec) }] }
        end
      end
    end
  end
end
