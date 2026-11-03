module BanianStudio
  module BanianBrowser
    # Proxy system (made for Enscape / render workflows).
    #
    # A proxy is a very light component (a box, or the N largest faces of the
    # model) that keeps the exact origin and size of the full model and stores the
    # path of the full .skp it stands for. Work with proxies so the SketchUp file
    # stays small and fast; swap everything to the full models right before
    # rendering in Enscape, then swap back. The full geometry is removed from the
    # file while proxies are shown, so the .skp really gets lighter.
    module Proxy
      PDICT = 'BanianProxy'.freeze
      MAT_NAME = 'Banian Proxy'.freeze
      MAX_SCAN_FACES = 250_000

      class << self
        def model
          Sketchup.active_model
        end

        def proxy_dir(sub = nil)
          base = Settings['proxy_dir'].to_s
          base = Util.join(Settings.data_dir, 'proxies') if base.empty?
          dir = sub ? Util.join(base, sub) : Util.norm(base)
          FileUtils.mkdir_p(dir) unless File.directory?(dir)
          dir
        end

        def role(d)
          d.get_attribute(PDICT, 'role')
        end

        def proxy?(d)
          role(d) == 'proxy'
        end

        def source_of(d)
          d.get_attribute(PDICT, 'source') || d.get_attribute(DICT, 'source')
        end

        def proxy_material
          m = model.materials[MAT_NAME]
          return m if m
          m = model.materials.add(MAT_NAME)
          m.color = Sketchup::Color.new(80, 150, 230)
          m.alpha = 0.35
          m
        end

        def mode
          Settings['proxy_mode'] == 'simplified' ? 'simplified' : 'box'
        end

        # ---- building ------------------------------------------------------------------
        # Makes sure the full model exists as a .skp on disk and returns its path.
        def ensure_source(full)
          src = source_of(full)
          return src if src && File.file?(src) && !full.get_attribute(PDICT, 'dirty')
          path = Util.join(proxy_dir('sources'), "#{Util.safe_filename(full.name)}_#{full.guid[0, 8]}.skp")
          full.save_as(path)
          full.set_attribute(PDICT, 'source', path)
          path
        end

        def tag(pdef, src, mode_name, name)
          pdef.set_attribute(PDICT, 'role', 'proxy')
          pdef.set_attribute(PDICT, 'source', src)
          pdef.set_attribute(PDICT, 'mode', mode_name)
          pdef.set_attribute(PDICT, 'name', name)
          pdef.description = "Banian proxy of: #{src}"
        end

        def build_proxy(full, src, mode_name)
          pdef = model.definitions.add("#{full.name} [Proxy]")
          bb = full.bounds
          if mode_name == 'simplified'
            add_simplified(pdef.entities, full, Settings['proxy_faces'].to_i)
            add_box_lines(pdef.entities, bb)
          else
            add_box(pdef.entities, bb)
          end
          tag(pdef, src, mode_name, full.name)
          pdef
        end

        def add_box(ents, bb)
          c = (0..7).map { |i| bb.corner(i) }
          mat = proxy_material
          [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]].each do |idx|
            begin
              f = ents.add_face(idx.map { |i| c[i] })
              if f
                f.material = mat
                f.back_material = mat
              end
            rescue StandardError
              nil
            end
          end
          add_box_lines(ents, bb, true)
        end

        def add_box_lines(ents, bb, diagonals_only = false)
          c = (0..7).map { |i| bb.corner(i) }
          lines = [[4, 7], [5, 6]]
          unless diagonals_only
            lines += [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
          end
          lines.each do |a, b|
            begin
              ents.add_cline(c[a], c[b]) unless c[a] == c[b]
            rescue StandardError
              nil
            end
          end
        end

        def add_simplified(ents, full, limit)
          limit = 300 if limit <= 0
          faces = []
          collect_faces(full.entities, Geom::Transformation.new, nil, faces, 0)
          faces.sort_by! { |x| -x[0] }
          faces[0, limit].each do |_area, face, tr, mat|
            begin
              f = ents.add_face(face.outer_loop.vertices.map { |v| v.position.transform(tr) })
              next unless f
              f.material = mat if mat
              f.back_material = mat if mat
            rescue StandardError
              nil
            end
          end
        end

        def collect_faces(ents, tr, inherited, out, depth)
          return if depth > 10 || out.length > MAX_SCAN_FACES
          ents.each do |e|
            if e.is_a?(Sketchup::Face)
              out << [e.area(tr), e, tr, e.material || inherited]
            elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
              next if e.respond_to?(:hidden?) && e.hidden?
              collect_faces(Util.definition_of(e).entities, tr * e.transformation, e.material || inherited, out, depth + 1)
            end
          end
        end

        def remove_definition(d)
          return unless d && d.valid?
          return if d.instances.length > 0
          if model.definitions.respond_to?(:remove)
            model.definitions.remove(d)
          else
            d.entities.clear!
          end
        rescue StandardError => e
          Util.log_error(e, 'remove definition')
        end

        def find_proxy(src, mode_name = nil)
          model.definitions.find do |d|
            proxy?(d) && d.get_attribute(PDICT, 'source') == src &&
              (mode_name.nil? || d.get_attribute(PDICT, 'mode') == mode_name)
          end
        end

        def find_full(src)
          model.definitions.find do |d|
            !proxy?(d) && !d.image? && d.entities.length > 0 &&
              (d.get_attribute(PDICT, 'source') == src || d.get_attribute(DICT, 'source') == src)
          end
        end

        def load_full(src)
          return nil unless File.file?(src)
          v = Util.skp_version(src)
          return nil if v && v > Util.su_major
          d = find_full(src) || model.definitions.load(src)
          d.set_attribute(PDICT, 'role', 'full')
          d.set_attribute(PDICT, 'source', src)
          d
        end

        # ---- commands ------------------------------------------------------------------
        def convert_selection(mode_name = nil)
          mode_name ||= mode
          insts = Util.instances_in(model.selection.to_a)
          return msg(:select_components) if insts.empty?
          model.start_operation(I18n.t(:op_proxy), true)
          done = 0
          begin
            insts.each do |inst|
              inst = inst.to_component if inst.is_a?(Sketchup::Group)
              full = inst.definition
              next if proxy?(full)
              src = ensure_source(full)
              pdef = find_proxy(src, mode_name) || build_proxy(full, src, mode_name)
              full.instances.to_a.each { |i| i.definition = pdef }
              full.set_attribute(PDICT, 'role', 'full')
              remove_definition(full) if Settings['proxy_remove_full']
              done += 1
            end
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            Util.log_error(e, 'proxy convert')
            UI.messagebox(I18n.t(:proxy_failed) + "\n" + e.message)
            return false
          end
          Dialog.emit('proxy_stats', stats)
          done
        end

        def selected_instances
          Util.instances_in(model.selection.to_a).select { |i| i.is_a?(Sketchup::ComponentInstance) }
        end

        # Proxy -> full model.
        def to_full(scope = 'all')
          insts = if scope == 'all'
                    model.definitions.select { |d| proxy?(d) }.map { |d| d.instances.to_a }.flatten
                  else
                    selected_instances.select { |i| proxy?(i.definition) }
                  end
          return msg(:no_proxies) if insts.empty?
          missing = []
          model.start_operation(I18n.t(:op_to_full), true)
          begin
            insts.group_by { |i| i.definition }.each do |pdef, list|
              src = pdef.get_attribute(PDICT, 'source')
              full = src ? load_full(src) : nil
              unless full
                missing << (src || pdef.name)
                next
              end
              list.each { |i| i.definition = full }
            end
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            Util.log_error(e, 'to full')
            UI.messagebox(I18n.t(:proxy_failed) + "\n" + e.message)
            return false
          end
          UI.messagebox(I18n.t(:proxy_missing) + "\n" + missing.uniq.join("\n")) unless missing.empty?
          Dialog.emit('proxy_stats', stats)
          insts.length - missing.length
        end

        # Full model -> proxy (only models that came from a proxy or the library).
        def to_proxy(scope = 'all')
          insts = if scope == 'all'
                    model.definitions.select { |d| role(d) == 'full' }.map { |d| d.instances.to_a }.flatten
                  else
                    selected_instances.select { |i| !proxy?(i.definition) && source_of(i.definition) }
                  end
          return msg(:no_full) if insts.empty?
          model.start_operation(I18n.t(:op_proxy), true)
          begin
            insts.group_by { |i| i.definition }.each do |full, list|
              src = ensure_source(full)
              pdef = find_proxy(src, mode) || find_proxy(src) || build_proxy(full, src, mode)
              list.each { |i| i.definition = pdef }
              full.set_attribute(PDICT, 'role', 'full')
              remove_definition(full) if Settings['proxy_remove_full']
            end
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            Util.log_error(e, 'to proxy')
            UI.messagebox(I18n.t(:proxy_failed) + "\n" + e.message)
            return false
          end
          Dialog.emit('proxy_stats', stats)
          insts.length
        end

        # Place a library model directly as a proxy. The proxy is cached on disk, so
        # the heavy model is only read once.
        def place_as_proxy(path)
          path = Util.norm(path)
          return false unless ModelOps.check_file(path) && ModelOps.check_version(path)
          m = mode
          name = File.basename(path, '.*')
          key = Digest::MD5.hexdigest("#{path}|#{File.mtime(path).to_i}|#{m}|#{Settings['proxy_faces']}")
          cache = Util.join(proxy_dir('cache'), key + '.skp')
          pdef = find_proxy(path, m)
          unless pdef
            model.start_operation(I18n.t(:op_proxy), true)
            begin
              if File.file?(cache)
                pdef = model.definitions.load(cache)
                pdef.name = "#{name} [Proxy]"
                tag(pdef, path, m, name)
              else
                had = find_full(path)
                full = had || model.definitions.load(path)
                pdef = build_proxy(full, path, m)
                remove_definition(full) unless had
                begin
                  pdef.save_as(cache)
                rescue StandardError
                  nil
                end
              end
              model.commit_operation
            rescue StandardError => e
              model.abort_operation
              Util.log_error(e, 'place proxy')
              UI.messagebox(I18n.t(:proxy_failed) + "\n" + e.message)
              return false
            end
          end
          Settings.record_use(path)
          model.place_component(pdef, false)
          true
        end

        def open_source
          inst = selected_instances.find { |i| source_of(i.definition) }
          return msg(:select_proxy) unless inst
          ModelOps.open_new_window(source_of(inst.definition))
        end

        # Proxy -> full model, and forget the link (normal component again).
        def make_regular
          sel = selected_instances
          return msg(:select_proxy) if sel.empty?
          to_full('selection') if sel.any? { |i| proxy?(i.definition) }
          model.start_operation(I18n.t(:op_regular), true)
          selected_instances.map(&:definition).uniq.each do |d|
            next if proxy?(d)
            d.delete_attribute(PDICT) if d.attribute_dictionary(PDICT)
          end
          model.commit_operation
          Dialog.emit('proxy_stats', stats)
          true
        end

        def stats
          proxies = 0
          types = 0
          full = 0
          missing = 0
          model.definitions.each do |d|
            if proxy?(d)
              n = d.instances.length
              next if n.zero?
              types += 1
              proxies += n
              src = d.get_attribute(PDICT, 'source')
              missing += 1 unless src && File.file?(src)
            elsif role(d) == 'full'
              full += d.instances.length
            end
          end
          { 'proxies' => proxies, 'types' => types, 'full' => full, 'missing' => missing,
            'dir' => proxy_dir, 'mode' => mode }
        end

        def msg(key)
          UI.messagebox(I18n.t(key))
          false
        end
      end
    end
  end
end
