module BanianStudio
  module BanianBrowser
    # Persistent JSON settings, shared by every SketchUp version on this computer.
    module Settings
      DEFAULTS = {
        'roots' => [],             # [{ 'path' => ..., 'type' => 'models'|'materials'|'both', 'name' => ... }]
        'favorites' => [],         # file paths
        'recent' => [],            # file paths, newest first
        'usage' => {},             # path => times used
        'custom_thumbs' => {},     # path => image path
        'language' => 'fa',
        'theme' => 'light',
        'card_size' => 150,
        'sort' => 'name_asc',
        'recursive' => true,
        'folder_view' => 'folders', # folders: a folder shows its sub-folders + own files | flat: everything inside
        'place_mode' => 'normal',  # normal | fit3 | fit2 | surface
        'paint_tool' => 'native',  # native | banian | none
        'image_width_cm' => 100.0, # default real width for plain image textures
        'rotate_step' => 45,       # Left/Right arrows in the surface tool
        'place_rotate' => 90,      # Up/Down arrows while placing a model
        'surface_align' => 'normal',
        'tex_include_groups' => true,
        'tex_nudge' => 0.1,
        'last_save_dir' => '',
        'show_ext' => false,
        'show_info' => false,      # full name / size / date under each card
        'pinned' => {},            # 'models'|'materials' => [folder paths] shown above the grid
        'import_ratio' => 100,     # % of faces kept when importing files
        'simplify_ratio' => 50,    # % kept when simplifying model geometry / skp
        'import_tolerance' => 0.5, # cm
        'import_use_tol' => false,
        'import_keep_seams' => true,
        'import_keep_borders' => true,
        'import_flat' => false,
        'import_components' => true,
        'import_tint' => false
      }.freeze

      MAX_RECENT = 80

      class << self
        def data_dir
          @data_dir ||= begin
            base = nil
            if Util.win?
              base = ENV['LOCALAPPDATA'] || ENV['APPDATA']
            else
              home = ENV['HOME']
              base = File.join(Util.utf8(home), 'Library', 'Application Support') if home
            end
            base = Util.utf8(base) if base
            if base.nil? || base.empty? || !File.directory?(base)
              base = File.dirname(Util.utf8(Sketchup.find_support_file('Plugins')))
            end
            dir = Util.join(base, 'BanianBrowser')
            FileUtils.mkdir_p(dir)
            dir
          end
        end

        def sub_dir(name)
          d = Util.join(data_dir, name)
          FileUtils.mkdir_p(d) unless File.directory?(d)
          d
        end

        def file
          Util.join(data_dir, 'settings.json')
        end

        def data
          load unless @data
          @data
        end

        def load
          @data = JSON.parse(JSON.generate(DEFAULTS))
          if File.exist?(file)
            begin
              stored = JSON.parse(File.read(file, :encoding => 'UTF-8'))
              @data.merge!(stored) if stored.is_a?(Hash)
            rescue StandardError => e
              Util.log_error(e, 'settings load')
            end
          end
          @data
        end

        def save
          tmp = file + '.tmp'
          File.open(tmp, 'wb') { |f| f.write(JSON.pretty_generate(data)) }
          File.delete(file) if File.exist?(file) && Util.win?
          File.rename(tmp, file)
        rescue StandardError => e
          Util.log_error(e, 'settings save')
        end

        def [](key)
          data[key.to_s]
        end

        def []=(key, value)
          data[key.to_s] = value
          save
        end

        def update(hash)
          hash.each { |k, v| data[k.to_s] = v if DEFAULTS.key?(k.to_s) }
          save
        end

        def record_use(path)
          p = Util.norm(path)
          rec = data['recent']
          rec.delete(p)
          rec.unshift(p)
          rec.pop while rec.length > MAX_RECENT
          data['usage'][p] = data['usage'][p].to_i + 1
          save
        end

        def toggle_favorite(path)
          p = Util.norm(path)
          fav = data['favorites']
          if fav.include?(p)
            fav.delete(p)
          else
            fav.unshift(p)
          end
          save
          fav.include?(p)
        end

        # Keeps favorites/recent/usage pointing at the new path after rename/move.
        def rename_path(old_path, new_path)
          o = Util.norm(old_path)
          n = Util.norm(new_path)
          %w[favorites recent].each do |k|
            data[k] = data[k].map { |p| p == o ? n : (p.start_with?(o + '/') ? n + p[o.length..-1] : p) }
          end
          data['pinned'] = pinned_map { |p| p == o ? n : (p.start_with?(o + '/') ? n + p[o.length..-1] : p) }
          %w[usage custom_thumbs].each do |k|
            h = {}
            data[k].each do |p, v|
              np = p == o ? n : (p.start_with?(o + '/') ? n + p[o.length..-1] : p)
              h[np] = v
            end
            data[k] = h
          end
          save
        end

        def forget_path(path)
          p = Util.norm(path)
          %w[favorites recent].each { |k| data[k].reject! { |x| x == p || x.start_with?(p + '/') } }
          %w[usage custom_thumbs].each { |k| data[k].reject! { |x, _| x == p || x.start_with?(p + '/') } }
          data['pinned'] = pinned_map { |x| x == p || x.start_with?(p + '/') ? nil : x }
          save
        end

        def pinned_map
          src = data['pinned'].is_a?(Hash) ? data['pinned'] : {}
          out = {}
          src.each { |view, list| out[view] = (list || []).map { |x| yield(x) }.compact.uniq }
          out
        end

        # Pins / unpins a folder for the 'models' or 'materials' view. Returns the new map.
        def toggle_pin(view, path)
          view = view == 'materials' ? 'materials' : 'models'
          p = Util.norm(path)
          map = data['pinned'].is_a?(Hash) ? data['pinned'] : {}
          list = (map[view] || []).dup
          if list.include?(p)
            list.delete(p)
          else
            list << p
          end
          map[view] = list
          data['pinned'] = map
          save
          map
        end

        # Moves a pinned folder left/right (delta -1 / +1). Returns the new map.
        def move_pin(view, path, delta)
          map = data['pinned'].is_a?(Hash) ? data['pinned'] : {}
          list = map[view] || []
          i = list.index(Util.norm(path))
          return map unless i
          j = [[i + delta.to_i, 0].max, list.length - 1].min
          list.insert(j, list.delete_at(i))
          save
          map
        end
      end
    end
  end
end
