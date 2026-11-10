# encoding: UTF-8
# Banian Profile Builder - editing features of the panel controller:
#  * your own profiles (pick a face, live shape editing in place)
#  * eyedropper (adopt an existing object's settings)
#  * continue an object on another path / replace its path
#  * user components inside assemblies
#  * library import / export

require 'json'

module BanianStudio
  module ProfileBuilder
    module Controller
      MSG2 = {
        'en' => {
          'select_member' => 'Select one Banian profile (not an assembly) to edit its shape.',
          'shape_invalid' => 'The profile shape must be at least one closed face.',
          'replace_hint' => 'Select ONE Banian object together with the edges / face of the new path.',
          'continue_hint' => 'Select a Banian object together with the edges / faces of the new path.',
          'select_component' => 'Select a component in the model first.',
          'imported' => 'Imported items: '
        },
        'fa' => {
          'select_member' => 'برای ویرایش شکل، یک پروفایل بانیان (نه اسمبلی) را انتخاب کنید.',
          'shape_invalid' => 'شکل پروفایل باید حداقل یک سطح بسته باشد.',
          'replace_hint' => 'یک شیء بانیان را همراه با خطوط یا سطح مسیر جدید انتخاب کنید.',
          'continue_hint' => 'یک شیء بانیان را همراه با خطوط یا سطح مسیر جدید انتخاب کنید.',
          'select_component' => 'اول یک کامپوننت را در مدل انتخاب کنید.',
          'imported' => 'موارد وارد شده: '
        }
      }.freeze

      module_function

      def t2(key)
        (MSG2[lang] || MSG2['en'])[key] || MSG2['en'][key]
      end

      def library_payload
        d = Library.data
        sil = {}
        d['assemblies'].each { |a| sil.merge!(Silhouette.for_spec(Sketchup.active_model, a)) }
        {
          'sil' => sil,
          'profiles' => d['profiles'],
          'assemblies' => d['assemblies'].map do |a|
            thumb = begin
              Assembly.elevation(a)
            rescue StandardError
              []
            end
            a.merge('thumb' => thumb)
          end
        }
      end

      # ---------- your own profile from a face ----------------------------

      def pick_face
        faces = Sketchup.active_model.selection.grep(Sketchup::Face)
        if faces.size == 1
          add_face_profile(faces[0])
        else
          Sketchup.active_model.select_tool(PickFaceTool.new)
        end
      end

      # 2D loops (mm) of a face in its own plane. Vertical faces keep "up"
      # as up; any orientation works (no need to draw on the axes).
      def face_loops(face)
        n = face.normal
        z = Geom::Vector3d.new(0, 0, 1)
        x = n.parallel?(z) ? Geom::Vector3d.new(1, 0, 0) : z.cross(n)
        x.normalize!
        y = n.cross(x)
        y.normalize!
        o = face.outer_loop.vertices[0].position
        loops = ([face.outer_loop] + (face.loops - [face.outer_loop])).map do |lp|
          lp.vertices.map do |v|
            d = v.position - o
            [d.dot(x) * 25.4, d.dot(y) * 25.4]
          end
        end
        normalize_loops(loops)
      end

      def normalize_loops(loops)
        bb = Profiles.bbox(loops)
        loops.map { |l| l.map { |q| [(q[0] - bb[0]).round(3), (q[1] - bb[1]).round(3)] } }
      end

      def add_face_profile(face)
        loops = face_loops(face)
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
        spec
      end

      # ---------- live shape editing --------------------------------------

      def shape_editing?
        @shape && @shape[:group] && @shape[:group].valid? ? true : false
      end

      def begin_shape_edit
        model = Sketchup.active_model
        cancel_shape_edit if shape_editing?
        target = selected_pb('member').first
        unless target
          UI.messagebox(t2('select_member'))
          return
        end
        info = Builder.read(target)
        spec = info['spec']
        prep = Sweep.prepare(info['path'], info['closed'], info['up'])
        _t, r, u = Sweep.frames(prep[:points], prep[:closed], prep[:up])[0]
        tr = target.transformation
        o = tr * Geom::Point3d.new(*prep[:points][0])
        rv = tr * Geom::Vector3d.new(*r)
        uv = tr * Geom::Vector3d.new(*u)
        rv.normalize!
        uv.normalize!
        loops = Profiles.to_inches(Profiles.placed_loops(spec))
        model.start_operation('Banian Edit Shape', true)
        shape = model.active_entities.add_group
        pts = loops.map do |l|
          l.map { |q| Geom::Point3d.new(o.x + rv.x * q[0] + uv.x * q[1], o.y + rv.y * q[0] + uv.y * q[1], o.z + rv.z * q[0] + uv.z * q[1]) }
        end
        shape.entities.add_face(pts[0])
        pts[1..-1].each do |h|
          f = shape.entities.add_face(h)
          f.erase! if f && f.valid?
        end
        shape.name = 'Banian profile shape (edit me, then press Update)'
        target.hidden = true
        model.commit_operation
        @shape = { group: shape, target: target, o: o, r: rv, u: uv, spec: spec }
        model.selection.clear
        model.selection.add(shape)
        begin
          model.active_path = (model.active_path || []) + [shape] if model.respond_to?(:active_path=)
        rescue StandardError
          nil
        end
        send_js('type' => 'shape_edit', 'active' => true)
      rescue StandardError => e
        model.abort_operation if model
        report_error(e)
      end

      # Boundary loops (mm, in the placed section frame) of the edited shape.
      def shape_loops(sh)
        g = sh[:group]
        tr = g.transformation
        edges = g.entities.grep(Sketchup::Edge)
        faced = edges.select { |e| e.faces.size == 1 }
        faced = edges if faced.empty?
        loops = []
        chains(faced).each do |pts, closed|
          next unless closed && pts.size >= 3
          loops << pts.map do |p|
            d = (tr * p) - sh[:o]
            [d.dot(sh[:r]) * 25.4, d.dot(sh[:u]) * 25.4]
          end
        end
        return [] if loops.empty?
        loops.sort_by! { |l| -Profiles.signed_area(l).abs }
        outer = loops[0]
        ob = Profiles.bbox([outer])
        holes = loops[1..-1].select do |l|
          b = Profiles.bbox([l])
          b[0] > ob[0] && b[1] > ob[1] && b[2] < ob[2] && b[3] < ob[3]
        end
        [outer] + holes
      end

      def finish_shape_edit
        return unless shape_editing?
        model = Sketchup.active_model
        sh = @shape
        guard = 0
        while model.active_path && model.active_path.include?(sh[:group]) && guard < 20
          model.close_active
          guard += 1
        end
        loops = shape_loops(sh)
        if loops.empty?
          UI.messagebox(t2('shape_invalid'))
          return
        end
        spec = sh[:spec]
        a = -(spec['rotation'] || 0).to_f * Math::PI / 180.0
        ca = Math.cos(a); sa = Math.sin(a)
        raw = loops.map do |l|
          l.map do |q|
            x = spec['flip'] ? -q[0] : q[0]
            y = q[1]
            [x * ca - y * sa, x * sa + y * ca]
          end
        end
        raw = normalize_loops(raw)
        bb = Profiles.bbox(raw)
        nw = bb[2] - bb[0]; nh = bb[3] - bb[1]
        target = sh[:target]
        model.start_operation('Banian Update Shape', true)
        pid = spec['profile'].to_s
        if pid.start_with?('custom')
          Library.ensure_profile(pid, spec['custom_name'], spec['custom_loops'])
          Library.update_profile(pid, raw)
          tw = (spec['params'] || {})['w'].to_f
          th = (spec['params'] || {})['h'].to_f
          update_profile_everywhere(model, pid, raw, nw, nh, tw, th)
        elsif target.valid?
          name = "#{Builder.profile_name(spec)} (edited)"
          id = Library.add_profile(name, raw)
          s = spec.merge('profile' => id, 'custom_loops' => raw, 'custom_name' => name,
                         'params' => { 'w' => nw.round(2), 'h' => nh.round(2) })
          Builder.rebuild(target, s)
        end
        sh[:group].erase! if sh[:group].valid?
        if target.valid?
          target.hidden = false
          model.selection.clear
          model.selection.add(target)
        end
        model.commit_operation
        @shape = nil
        push_library
        send_js('type' => 'shape_edit', 'active' => false)
        push_selection
      rescue StandardError => e
        model.abort_operation if model
        report_error(e)
      end

      # Live profile editing: every member and assembly part using the
      # profile follows the new shape, keeping its own size ratio.
      def update_profile_everywhere(model, pid, raw, nw, nh, tw, th)
        scale = lambda do |params|
          pw = params['w'].to_f; ph = params['h'].to_f
          fx = tw > 0 && pw > 0 ? pw / tw : 1.0
          fy = th > 0 && ph > 0 ? ph / th : 1.0
          { 'w' => (nw * fx).round(2), 'h' => (nh * fy).round(2) }
        end
        Quantities.pb_groups(model).each do |g|
          info = Builder.read(g)
          next unless info
          s = info['spec']
          changed = false
          if info['kind'] == 'member' && s['profile'] == pid
            s['custom_loops'] = raw
            s['params'] = scale.call(s['params'] || {})
            changed = true
          elsif info['kind'] == 'assembly'
            (s['rows'] || []).each do |row|
              next unless row['profile'] == pid
              row['custom_loops'] = raw
              row['params'] = scale.call(row['params'] || {})
              changed = true
            end
          end
          Builder.rebuild(g, s) if changed
        end
      end

      def cancel_shape_edit
        return unless @shape
        model = Sketchup.active_model
        sh = @shape
        @shape = nil
        while model.active_path && sh[:group].valid? && model.active_path.include?(sh[:group])
          model.close_active
        end
        model.start_operation('Banian Cancel Shape', true)
        sh[:group].erase! if sh[:group].valid?
        sh[:target].hidden = false if sh[:target].valid?
        model.commit_operation
        send_js('type' => 'shape_edit', 'active' => false)
      end

      # ---------- eyedropper ---------------------------------------------

      def adopt(group)
        info = Builder.read(group)
        return nil unless info
        spec = info['spec']
        if info['kind'] == 'member'
          Library.ensure_profile(spec['profile'], spec['custom_name'], spec['custom_loops']) if spec['profile'].to_s.start_with?('custom')
        else
          (spec['rows'] || []).each do |r|
            Library.ensure_profile(r['profile'], r['name'], r['custom_loops']) if r['profile'].to_s.start_with?('custom')
          end
        end
        set_spec(info['kind'], spec)
        push_library
        send_js('type' => 'use_spec', 'kind' => info['kind'], 'spec' => spec)
        info['kind']
      end

      # ---------- paths ---------------------------------------------------

      def continue_on_selected_path
        model = Sketchup.active_model
        if selected_pb.empty? || collect_paths(model).empty?
          UI.messagebox(t2('continue_hint'))
          return
        end
        build_on_selection
      end

      def replace_path
        model = Sketchup.active_model
        targets = selected_pb
        paths = collect_paths(model)
        if targets.size != 1 || paths.empty?
          UI.messagebox(t2('replace_hint'))
          return
        end
        g = targets[0]
        pts, closed, up = paths[0]
        inv = g.transformation.inverse
        local = pts.map { |p| (inv * Geom::Point3d.new(*p)).to_a }
        up_l = up ? (inv * Geom::Vector3d.new(*up)).to_a : nil
        model.start_operation('Banian Replace Path', true)
        Builder.rebuild(g, nil, local, closed, up_l)
        model.commit_operation
        model.selection.clear
        model.selection.add(g)
      rescue StandardError => e
        model.abort_operation if model
        report_error(e)
      end

      # ---------- components in assemblies ---------------------------------

      def component_list
        Sketchup.active_model.definitions.map do |d|
          next if d.group? || d.image? || d.get_attribute(Builder::DICT, 'piece')
          bb = d.bounds
          { 'name' => d.name, 'w' => (bb.width * 25.4).round(1), 'd' => (bb.height * 25.4).round(1),
            'h' => (bb.depth * 25.4).round(1) }
        end.compact.sort_by { |c| c['name'].downcase }
      end

      def push_components
        send_js('type' => 'components', 'components' => component_list)
      end

      def pick_component(row)
        inst = Sketchup.active_model.selection.grep(Sketchup::ComponentInstance).first
        unless inst
          UI.messagebox(t2('select_component'))
          return
        end
        d = inst.definition
        bb = d.bounds
        push_components
        send_js('type' => 'component_picked', 'row' => row, 'name' => d.name,
                'w' => (bb.width * 25.4).round(1), 'd' => (bb.height * 25.4).round(1), 'h' => (bb.depth * 25.4).round(1))
      end

      # ---------- library files ------------------------------------------

      def export_library
        path = UI.savepanel('Export Banian library', '', 'banian-library.json')
        return unless path
        path += '.json' unless path =~ /\.json\z/i
        Library.export_to(path)
        send_js('type' => 'toast', 'text' => File.basename(path))
      end

      def import_library
        path = UI.openpanel('Import Banian library', '', 'Banian library|*.json||')
        return unless path
        n = Library.import_from(path)
        push_library
        send_js('type' => 'toast', 'text' => t2('imported') + n.to_s)
      rescue StandardError => e
        report_error(e)
      end
    end
  end
end
