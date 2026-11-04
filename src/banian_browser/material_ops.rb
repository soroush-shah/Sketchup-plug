# encoding: UTF-8
module BanianStudio
  module BanianBrowser
    # Material import, picking, replacing, saving and model-material listing.
    module MaterialOps
      class << self
        def model
          Sketchup.active_model
        end

        # The material the user picked with the eyedropper (or last imported).
        # SketchUp's own current material (paint bucket / Materials panel) wins, so the
        # browser always works on what the user chose in SketchUp.
        def current
          m = model.materials.current
          m = nil if m && m.deleted?
          return m if m
          m = @current
          m && !m.deleted? && model.materials.include?(m) ? m : nil
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

        # Formats SketchUp reads directly; others (webp, gif) are converted to PNG by the
        # dialog first (see Commands#cmd_save_converted).
        NATIVE_IMAGES = %w[.jpg .jpeg .png .bmp .tif .tiff .tga].freeze

        def converted_file(path)
          File.join(Settings.sub_dir('converted'), Thumbnails.key_for(path) + '.png')
        end

        def needs_conversion?(path)
          !NATIVE_IMAGES.include?(File.extname(path).downcase)
        end

        # "Oak_120x60cm.jpg" / "tile 60x60 mm.png" / "marble-1.2x0.6m.jpg" -> [w, h] in inches
        def size_from_name(name)
          m = name.match(/(\d+(?:[.,]\d+)?)\s*[x×*]\s*(\d+(?:[.,]\d+)?)\s*(mm|cm|m)\b/i)
          return nil unless m
          f = { 'mm' => 0.1, 'cm' => 1.0, 'm' => 100.0 }[m[3].downcase]
          [Util.cm_to_in(m[1].tr(',', '.').to_f * f), Util.cm_to_in(m[2].tr(',', '.').to_f * f)]
        end

        def material_from_image(path)
          base = File.basename(path, '.*')
          file = path
          if needs_conversion?(path)
            file = converted_file(path)
            raise ArgumentError, "#{File.basename(path)}: #{I18n.t(:format_unsupported)}" unless File.file?(file)
          end
          existing = model.materials.find do |m|
            m.texture && [path, file].include?(Util.norm(m.texture.filename.to_s))
          end
          return existing if existing
          mat = model.materials.add(base)
          mat.texture = file
          tex = mat.texture
          if tex && tex.image_width.to_i > 0
            size = size_from_name(base)
            if size
              tex.size = size
            else
              w = Util.cm_to_in(Settings['image_width_cm'].to_f > 0 ? Settings['image_width_cm'] : 100)
              tex.size = [w, w * tex.image_height.to_f / tex.image_width.to_f]
            end
          end
          mat
        end

        # Imports every image / .skm of a folder (and its sub-folders) as model materials.
        def import_folder(folder, recursive = true)
          pattern = recursive ? File.join(folder, '**', '*') : File.join(folder, '*')
          files = Dir.glob(pattern.gsub(/[\[\]{}]/) { |c| "\\#{c}" }).select do |f|
            e = File.extname(f).downcase
            (NATIVE_IMAGES.include?(e) || e == '.skm') && File.file?(f)
          end
          return 0 if files.empty?
          n = 0
          model.start_operation(I18n.t(:op_import_mat), true)
          files.each do |f|
            begin
              f = Util.norm(f)
              if File.extname(f).downcase == '.skm'
                model.materials.load(f) if model.materials.respond_to?(:load)
              else
                material_from_image(f)
              end
              n += 1
            rescue StandardError => e
              Util.log_error(e, 'import folder')
            end
          end
          model.commit_operation
          n
        end

        # ---- swapping materials while keeping the UV mapping (Replace Textures) ------
        def swap_face(face, front, dst, tw)
          old = front ? face.material : face.back_material
          keep = old && old.texture && dst.texture
          if keep
            pts, uvs = TextureTools.sample(face, front, tw)
          end
          if front
            face.material = dst
          else
            face.back_material = dst
          end
          TextureTools.apply(face, front, pts, uvs) if keep
          true
        rescue StandardError => e
          Util.log_error(e, 'swap face')
          false
        end

        def swap_in(entities, src, dst)
          tw = Sketchup.create_texture_writer
          n = 0
          entities.to_a.each do |e|
            if e.is_a?(Sketchup::Face)
              n += 1 if e.material == src && swap_face(e, true, dst, tw)
              n += 1 if e.back_material == src && swap_face(e, false, dst, tw)
            elsif e.respond_to?(:material=) && !e.is_a?(Sketchup::Edge) && e.material == src
              e.material = dst
              n += 1
            end
          end
          n
        end

        def swap_everywhere(src, dst)
          n = swap_in(model.entities, src, dst)
          model.definitions.each { |d| n += swap_in(d.entities, src, dst) unless d.image? }
          n
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
