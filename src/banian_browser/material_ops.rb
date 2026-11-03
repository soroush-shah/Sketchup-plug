module BanianStudio
  module BanianBrowser
    # Material import, picking, replacing, saving and model-material listing.
    module MaterialOps
      class << self
        def model
          Sketchup.active_model
        end

        # The material the user picked with the eyedropper (or last imported).
        def current
          m = @current
          m = nil if m && (m.deleted? || !model.materials.include?(m))
          m || model.materials.current
        rescue StandardError
          nil
        end

        def current=(mat)
          @current = mat
          begin
            model.materials.current = mat if mat
          rescue StandardError
            nil
          end
          Dialog.emit('picked', info(mat))
        end

        # ---- import ----------------------------------------------------------------
        def import(path)
          path = Util.norm(path)
          return nil unless ModelOps.check_file(path)
          ext = File.extname(path).downcase
          mat = nil
          model.start_operation(I18n.t(:op_import_mat), true)
          begin
            if ext == '.skm'
              unless model.materials.respond_to?(:load)
                model.abort_operation
                UI.messagebox(I18n.t(:needs_newer_su))
                return nil
              end
              mat = model.materials.load(path)
            else
              mat = material_from_image(path)
            end
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            Util.log_error(e, 'import material')
            UI.messagebox(I18n.t(:mat_load_failed) + "\n" + e.message)
            return nil
          end
          Settings.record_use(path)
          self.current = mat
          mat
        end

        def material_from_image(path)
          base = File.basename(path, '.*')
          existing = model.materials.find do |m|
            m.texture && Util.norm(m.texture.filename.to_s) == path
          end
          return existing if existing
          mat = model.materials.add(base)
          mat.texture = path
          tex = mat.texture
          if tex && tex.image_width.to_i > 0
            w = Util.cm_to_in(Settings['image_width_cm'].to_f > 0 ? Settings['image_width_cm'] : 100)
            h = w * tex.image_height.to_f / tex.image_width.to_f
            tex.size = [w, h]
          end
          mat
        end

        # Click on a material card: import it and give the user a paint bucket.
        def import_and_paint(path)
          mat = import(path)
          return false unless mat
          case Settings['paint_tool']
          when 'banian' then model.select_tool(MaterialBucketTool.new)
          when 'native' then Sketchup.send_action('selectPaintTool:')
          end
          true
        end

        def import_and_apply(path)
          mat = import(path)
          return false unless mat
          apply_to_selection(mat)
        end

        def apply_to_selection(mat = nil)
          mat ||= current
          return msg(:pick_first) unless mat
          ents = model.selection.to_a.select { |e| e.respond_to?(:material=) && !e.is_a?(Sketchup::Edge) }
          return msg(:select_something) if ents.empty?
          model.start_operation(I18n.t(:op_paint), true)
          ents.each { |e| e.material = mat }
          model.commit_operation
          true
        end

        # ---- replace ----------------------------------------------------------------
        # Replaces every use of `src` (faces, back faces, groups, components) with `dst`.
        def replace(src, dst, remove_src = true)
          return msg(:pick_first) unless src
          return false unless dst
          return false if src == dst
          model.start_operation(I18n.t(:op_replace_mat), true)
          count = 0
          walk = lambda do |ents|
            ents.each do |e|
              if e.is_a?(Sketchup::Face)
                if e.material == src
                  e.material = dst
                  count += 1
                end
                if e.back_material == src
                  e.back_material = dst
                  count += 1
                end
              elsif e.respond_to?(:material) && e.respond_to?(:material=) && e.material == src
                e.material = dst
                count += 1
              end
            end
          end
          walk.call(model.entities)
          model.definitions.each { |d| walk.call(d.entities) unless d.image? }
          if remove_src && model.materials.respond_to?(:remove)
            begin
              model.materials.remove(src)
            rescue StandardError
              nil
            end
          end
          model.commit_operation
          self.current = dst
          count
        end

        def replace_with_path(path, remove_src = true)
          src = current
          return msg(:pick_first) unless src
          src_name = src.name
          dst = import(path)
          return false unless dst
          src = model.materials[src_name]
          replace(src, dst, remove_src)
        end

        def replace_with_material_name(src_name, dst_name, remove_src = true)
          src = model.materials[src_name]
          dst = model.materials[dst_name]
          replace(src, dst, remove_src)
        end

        # ---- save ------------------------------------------------------------------
        def save_to_library(mat, folder)
          mat ||= current
          return msg(:pick_first) unless mat
          unless mat.respond_to?(:save_as)
            UI.messagebox(I18n.t(:needs_newer_su))
            return nil
          end
          res = UI.inputbox([I18n.t(:file_name)], [Util.utf8(mat.display_name)], I18n.t(:save_material))
          return nil unless res
          path = Util.unique_path(Util.join(folder, Util.safe_filename(res[0]) + '.skm'))
          mat.save_as(path)
          Library.rescan_for(path)
          path
        end

        def export_all(folder)
          return false unless model.materials.first && model.materials.first.respond_to?(:save_as)
          n = 0
          model.materials.each do |m|
            path = Util.unique_path(Util.join(folder, Util.safe_filename(m.display_name) + '.skm'))
            begin
              m.save_as(path)
              n += 1
            rescue StandardError => e
              Util.log_error(e, 'export material')
            end
          end
          Library.rescan_for(folder)
          n
        end

        def collect_textures(folder)
          n = 0
          model.materials.each do |m|
            tex = m.texture
            next unless tex
            ext = File.extname(tex.filename.to_s)
            ext = '.png' if ext.empty?
            path = Util.unique_path(Util.join(folder, Util.safe_filename(m.display_name) + ext))
            begin
              tex.write(path)
              n += 1
            rescue StandardError => e
              Util.log_error(e, 'collect texture')
            end
          end
          return msg(:no_textures) if n.zero?
          Library.rescan_for(folder)
          n
        end

        def purge_unused
          before = model.materials.length
          model.materials.purge_unused
          before - model.materials.length
        end

        # ---- material properties -------------------------------------------------
        def set_props(name, props)
          mat = name ? model.materials[name] : current
          return msg(:pick_first) unless mat
          model.start_operation(I18n.t(:op_edit_mat), true)
          if props.key?('alpha')
            mat.alpha = [[props['alpha'].to_f, 0.0].max, 1.0].min
          end
          if mat.texture && (props.key?('width') || props.key?('height'))
            tex = mat.texture
            w = props['width'] ? Util.cm_to_in(props['width']) : tex.width
            h = props['height'] ? Util.cm_to_in(props['height']) : tex.height
            tex.size = [w, h] if w > 0 && h > 0
          end
          if props['color']
            c = props['color'].to_s.sub('#', '')
            mat.color = Sketchup::Color.new(c[0, 2].to_i(16), c[2, 2].to_i(16), c[4, 2].to_i(16)) if c.length == 6
          end
          if props['name'] && !props['name'].to_s.strip.empty?
            begin
              mat.name = props['name'].to_s.strip
            rescue StandardError
              nil
            end
          end
          model.commit_operation
          @current = mat
          Dialog.emit('picked', info(mat))
          true
        end

        def info(mat)
          return nil unless mat && !mat.deleted?
          tex = mat.texture
          {
            'name' => Util.utf8(mat.name),
            'display' => Util.utf8(mat.display_name),
            'color' => Util.color_hex(mat.color),
            'alpha' => mat.alpha,
            'texture' => tex ? true : false,
            'width' => tex ? Util.in_to_cm(tex.width) : nil,
            'height' => tex ? Util.in_to_cm(tex.height) : nil,
            'pixels' => tex ? [tex.image_width, tex.image_height] : nil,
            'thumb' => thumb(mat)
          }
        end

        def thumb_dir
          d = Util.join(Util.utf8(Sketchup.temp_dir), 'banian_browser_mats')
          FileUtils.mkdir_p(d) unless File.directory?(d)
          d
        end

        def thumb(mat)
          return nil unless mat.respond_to?(:write_thumbnail)
          tex = mat.texture
          sig = [mat.name, Util.color_hex(mat.color), mat.alpha, tex ? tex.filename : '', tex ? tex.width : 0].join('|')
          file = File.join(thumb_dir, Digest::MD5.hexdigest(sig) + '.png')
          mat.write_thumbnail(file, 128) unless File.file?(file)
          File.file?(file) ? Util.file_url(file) : nil
        rescue StandardError
          nil
        end

        def list
          used = {}
          walk = lambda do |ents|
            ents.each do |e|
              used[e.material] = true if e.respond_to?(:material) && e.material
              used[e.back_material] = true if e.is_a?(Sketchup::Face) && e.back_material
            end
          end
          walk.call(model.entities)
          model.definitions.each { |d| walk.call(d.entities) if d.instances.length > 0 && !d.image? }
          cur = current
          model.materials.map do |m|
            h = info(m)
            h['used'] = used[m] ? true : false
            h['current'] = (m == cur)
            h
          end
        end

        def msg(key)
          UI.messagebox(I18n.t(key))
          false
        end
      end
    end
  end
end
