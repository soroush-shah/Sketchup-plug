module BanianStudio
  module BanianBrowser
    # Small helpers shared by every module. Written for Ruby 2.2+ (SketchUp 2017+).
    # A string that already is JSON (sent to the dialog as is).
    class RawJSON < String; end

    module Util
      MODEL_EXTS = %w[.skp].freeze
      MATERIAL_EXTS = %w[.skm].freeze
      IMAGE_EXTS = %w[.jpg .jpeg .png .bmp .gif .tif .tiff .tga .webp].freeze
      WEB_IMAGE_EXTS = %w[.jpg .jpeg .png .bmp .gif .webp].freeze
      SIDECAR_EXTS = %w[.png .jpg .jpeg .webp .bmp].freeze
      MESH_EXTS = %w[.glb .gltf .fbx .obj .dae .3ds .stl .ply .wrl .vrml .usdz].freeze

      module_function

      def win?
        (RUBY_PLATFORM =~ /mswin|mingw|cygwin/) ? true : false
      end

      def mac?
        !win?
      end

      # Major SketchUp version: 17 for 2017 ... 27 for 2027.
      def su_major
        Sketchup.version.to_i
      end

      # Convert an internal major version (e.g. 24) to the marketing year (2024).
      def su_year(major)
        return nil unless major
        major >= 13 ? 2000 + major : major
      end

      # Force any string (file names from Windows APIs, ENV values, ...) to valid UTF-8.
      def utf8(str)
        return '' if str.nil?
        s = str.to_s.dup
        if s.encoding == Encoding::UTF_8
          return s.valid_encoding? ? s : s.scrub('?')
        end
        begin
          t = s.encode('UTF-8')
        rescue StandardError
          t = s.force_encoding('UTF-8')
        end
        t.valid_encoding? ? t : t.scrub('?')
      end

      # Normalised path: UTF-8 and forward slashes (Windows accepts them).
      def norm(path)
        p = utf8(path).tr('\\', '/')
        p = p.chomp('/') if p.length > 3 && p.end_with?('/')
        p
      end

      def join(*parts)
        norm(File.join(*parts.map { |x| utf8(x) }))
      end

      def escape_segment(seg)
        seg.dup.force_encoding('BINARY').gsub(/[^A-Za-z0-9\-._~]/n) { |c| format('%%%02X', c.ord) }
           .force_encoding('UTF-8')
      end

      # file:// URL usable in the HtmlDialog for local images.
      def file_url(path, stamp = nil)
        p = norm(path)
        enc = p.split('/', -1).map { |seg| seg =~ /\A[A-Za-z]:\z/ ? seg : escape_segment(seg) }.join('/')
        url = enc.start_with?('/') ? "file://#{enc}" : "file:///#{enc}"
        stamp ? "#{url}?v=#{stamp}" : url
      end

      # Reads the "{24.0.594}" version stamp from a .skp header. Returns major int or nil.
      def skp_version(path)
        data = File.open(path, 'rb') { |f| f.read(160) }
        return nil unless data
        txt = data.force_encoding('BINARY').delete("\x00")
        m = txt.match(/\{(\d+)\.(\d+)\.(\d+)\}/)
        m ? m[1].to_i : nil
      rescue StandardError
        nil
      end

      def kind_of_ext(ext)
        e = ext.downcase
        return 'model' if MODEL_EXTS.include?(e)
        return 'material' if MATERIAL_EXTS.include?(e)
        return 'texture' if IMAGE_EXTS.include?(e)
        return 'mesh' if MESH_EXTS.include?(e)
        nil
      end

      # Sidecar preview image next to a model/material: "chair.skp" -> "chair.png"
      def sidecar_for(path)
        base = path.sub(/\.[^.\/]+\z/, '')
        SIDECAR_EXTS.each do |e|
          [e, e.upcase].each do |x|
            f = base + x
            return f if File.file?(f)
          end
        end
        nil
      end

      def safe_filename(name)
        n = utf8(name).gsub(%r{[\\/:*?"<>|\x00-\x1f]}, '_').strip
        n = n[0, 120] if n.length > 120
        n.empty? ? 'untitled' : n
      end

      def unique_path(path)
        return path unless File.exist?(path)
        dir = File.dirname(path)
        ext = File.extname(path)
        base = File.basename(path, ext)
        i = 2
        loop do
          cand = File.join(dir, "#{base} (#{i})#{ext}")
          return cand unless File.exist?(cand)
          i += 1
        end
      end

      def open_folder(path)
        p = norm(path)
        if mac? && File.exist?(p)
          system('open', '-R', p)
        else
          dir = File.directory?(p) ? p : File.dirname(p)
          UI.openURL(file_url(dir))
        end
      end

      def open_with_os(path)
        if mac?
          system('open', norm(path))
        else
          UI.openURL(file_url(path))
        end
      end

      # --- length / unit helpers (UI talks in centimetres) -------------------
      def cm_to_in(v)
        v.to_f / 2.54
      end

      def in_to_cm(v)
        (v.to_f * 2.54).round(3)
      end

      def color_hex(color)
        return nil unless color
        format('#%02x%02x%02x', color.red, color.green, color.blue)
      end

      def log(*msg)
        puts "[Banian Browser] #{msg.join(' ')}"
      end

      # Removes an unused definition (keeps the file small after cancelled imports).
      def remove_definition(d)
        return unless d && d.valid?
        return if d.instances.length > 0
        defs = Sketchup.active_model.definitions
        if defs.respond_to?(:remove)
          defs.remove(d)
        else
          d.entities.clear!
        end
      rescue StandardError => e
        log_error(e, 'remove definition')
      end

      def log_error(err, where = nil)
        log("Error#{where ? " in #{where}" : ''}: #{err.class}: #{err.message}")
        bt = err.backtrace
        log(bt[0, 6].join("\n")) if bt
      end

      # All group / component instances in a selection-like collection.
      def instances_in(ents)
        ents.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      end

      def definition_of(inst)
        return inst.definition if inst.is_a?(Sketchup::ComponentInstance)
        return inst.definition if inst.respond_to?(:definition)
        inst.entities.parent
      end
    end
  end
end
