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
        'place_mode' => 'normal',  # normal | fit3 | fit2 | surface
        'paint_tool' => 'native',  # native | banian | none
        'image_width_cm' => 100.0, # default real width for plain image textures
        'proxy_dir' => '',
        'proxy_mode' => 'box',     # box | simplified
        'proxy_faces' => 300,
        'proxy_remove_full' => true,
        'rotate_step' => 45,
        'surface_align' => 'normal',
        'tex_include_groups' => true,
        'tex_nudge' => 0.1,
        'last_save_dir' => '',
        'show_ext' => false
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
          save
        end
      end
    end
  end
end
