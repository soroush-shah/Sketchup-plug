# encoding: UTF-8
require 'json'

module BanianStudio
  module MaterialUV
    module Settings
      PREF = 'BanianMaterialUV'

      DEFAULTS = {
        'lang' => 'fa',
        'mat_source' => 'chosen',   # chosen | current | existing
        'material' => '',
        'mode' => 'auto',           # auto natural quad cylindrical spherical box planar
        'axis' => 'auto',           # auto x y z
        'planar_dir' => 'normal',   # normal camera x y z
        'size_mode' => 'real',      # real | fit
        'tile_w' => 0, 'tile_h' => 0,
        'repeat_u' => 1, 'repeat_v' => 1,
        'scale_u' => 100, 'scale_v' => 100,
        'rotation' => 0, 'seam' => 0,
        'offset_u' => 0, 'offset_v' => 0,
        'flip_u' => false, 'flip_v' => false,
        'sides' => 'front',         # front back both
        'allow_distort' => true,
        'cross_hard' => true,
        'expand' => false,
        'tool_scope' => 'surface'   # surface face object
      }

      @data = nil

      def self.get
        return @data if @data
        @data = DEFAULTS.dup
        raw = Sketchup.read_default(PREF, 'settings', nil)
        if raw.is_a?(String) && !raw.empty?
          begin
            h = JSON.parse(raw)
            h.each { |k, v| @data[k] = v if DEFAULTS.key?(k) } if h.is_a?(Hash)
          rescue StandardError
          end
        end
        @data
      end

      def self.update(h)
        d = get
        h.each { |k, v| d[k.to_s] = v if DEFAULTS.key?(k.to_s) } if h.is_a?(Hash)
        save
        d
      end

      def self.save
        Sketchup.write_default(PREF, 'settings', JSON.generate(get))
      rescue StandardError
        nil
      end

      def self.lang
        get['lang'] == 'en' ? 'en' : 'fa'
      end
    end

    # Messages shown by Ruby (message boxes / status bar). Menus stay English.
    module T
      STR = {
        'nothing' => ['Select faces, groups or components first.',
                      'اول صفحه، گروه یا کامپوننت را انتخاب کنید.'],
        'no_material' => ['Choose a material first (or use "Keep existing material").',
                          'اول یک متریال انتخاب کنید (یا گزینه «متریال فعلی صفحه‌ها» را بزنید).'],
        'done' => ['Banian Material UV: %d faces mapped.',
                   'بانیان متریال یو‌وی: %d صفحه نگاشت شد.'],
        'reset' => ['Banian Material UV: texture position reset on %d faces.',
                    'بانیان متریال یو‌وی: موقعیت بافت %d صفحه ریست شد.'],
        'tool' => ['Click a surface to map the texture. Shift = single face, Ctrl = whole object, Alt = pick material.',
                   'Click a surface to map the texture. Shift = single face, Ctrl = whole object, Alt = pick material.'],
        'about' => ["Banian Material UV %s\nBanian Studio\n\nUV mapping for curved surfaces: spheres, cylinders, domes, arches, curved walls and free-form meshes.",
                    "بانیان متریال یو‌وی %s\nBanian Studio\n\nنگاشت UV برای سطوح منحنی: کره، استوانه، گنبد، قوس، دیوار منحنی و احجام آزاد."]
      }

      def self.t(key, *args)
        pair = STR[key] || [key, key]
        s = Settings.lang == 'en' ? pair[0] : pair[1]
        args.empty? ? s : (s % args)
      end
    end
  end
end
