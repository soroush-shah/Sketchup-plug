module BanianStudio
  module BanianBrowser
    # Thumbnail resolution + disk cache.
    #  * custom thumbnail chosen by the user
    #  * sidecar image next to the file ("chair.skp" + "chair.jpg")
    #  * plain images are shown directly (tif/tga converted once)
    #  * .skm: thumbnail stored inside the zip
    #  * .skp: preview PNG embedded in the file, or rendered by SketchUp on demand
    module Thumbnails
      PNG_SIG = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].pack('C*')
      PNG_END = 'IEND'.b + [0xAE, 0x42, 0x60, 0x82].pack('C*')
      CHUNK = 1 << 20
      MAX_SCAN = 64 << 20
      SLICE = 0.06

      class << self
        def cache_dir
          Settings.sub_dir('thumbs')
        end

        def clear_cache
          Dir.glob(File.join(cache_dir, '*')).each do |f|
            begin
              File.delete(f)
            rescue StandardError
              nil
            end
          end
        end

        def key_for(path)
          st = File.stat(path)
          Digest::MD5.hexdigest("#{Util.norm(path)}|#{st.mtime.to_i}|#{st.size}")
        end

        def cache_file(path, ext = '.png')
          File.join(cache_dir, key_for(path) + ext)
        end

        def url(file)
          stamp = begin
            File.mtime(file).to_i
          rescue StandardError
            nil
          end
          Util.file_url(file, stamp)
        end

        # Returns a file:// URL or nil (no preview available yet).
        def resolve(path)
          path = Util.norm(path)
          return nil unless File.file?(path)
          custom = Settings['custom_thumbs'][path]
          return url(custom) if custom && File.file?(custom)
          ext = File.extname(path).downcase
          if Util::IMAGE_EXTS.include?(ext)
            return url(path) if Util::WEB_IMAGE_EXTS.include?(ext)
            out = cache_file(path)
            return url(out) if File.file?(out)
            return convert_texture(path, out) ? url(out) : nil
          end
          side = Util.sidecar_for(path)
          return url(side) if side
          out = cache_file(path)
          return url(out) if File.file?(out)
          none = cache_file(path, '.none')
          return nil if File.file?(none)
          ok = case ext
               when '.skp' then extract_skp(path, out)
               when '.skm' then extract_skm(path, out)
               else false
               end
          if ok
            url(out)
          else
            File.open(none, 'wb') { |f| f.write('') }
            nil
          end
        rescue StandardError => e
          Util.log_error(e, "thumbnail #{path}")
          nil
        end

        # ---- async queue: resolves batches without freezing SketchUp ----------
        def request(paths)
          @queue ||= []
          paths.each { |p| @queue << p unless @queue.include?(p) }
          start_timer
        end

        def start_timer
          return if @timer
          @timer = UI.start_timer(0.01, true) { tick }
        end

        def tick
          return if @busy
          @busy = true
          t0 = Time.now
          out = {}
          while (p = @queue.shift)
            out[p] = resolve(p)
            break if Time.now - t0 > SLICE
          end
          Dialog.emit('thumbs', out) unless out.empty?
          if @queue.empty?
            UI.stop_timer(@timer)
            @timer = nil
          end
        ensure
          @busy = false
        end

        # Render a precise thumbnail with SketchUp itself (loads the model temporarily).
        def generate_with_sketchup(path)
          path = Util.norm(path)
          ext = File.extname(path).downcase
          out = cache_file(path)
          none = cache_file(path, '.none')
          model = Sketchup.active_model
          if ext == '.skp'
            v = Util.skp_version(path)
            return nil if v && v > Util.su_major
            model.start_operation('Banian thumbnail', true)
            begin
              d = model.definitions.load(path)
              d.save_thumbnail(out) if d
            ensure
              model.abort_operation
            end
          elsif ext == '.skm' && model.materials.respond_to?(:load)
            model.start_operation('Banian thumbnail', true)
            begin
              m = model.materials.load(path)
              m.write_thumbnail(out, 256) if m && m.respond_to?(:write_thumbnail)
            ensure
              model.abort_operation
            end
          end
          return nil unless File.file?(out)
          File.delete(none) if File.file?(none)
          url(out)
        rescue StandardError => e
          Util.log_error(e, 'generate thumbnail')
          nil
        end

        def set_custom(path, image)
          p = Util.norm(path)
          dst = File.join(Settings.sub_dir('custom_thumbs'), Digest::MD5.hexdigest(p) + File.extname(image).downcase)
          FileUtils.cp(image, dst)
          h = Settings['custom_thumbs']
          h[p] = Util.norm(dst)
          Settings.save
          url(dst)
        end

        def clear_custom(path)
          Settings['custom_thumbs'].delete(Util.norm(path))
          Settings.save
        end

        # ---- extractors -----------------------------------------------------------
        def extract_skm(path, out)
          return false unless ZipReader.zip?(path)
          zip = ZipReader.new(path)
          e = zip.find { |x| x.name =~ /thumbnail[^\/]*\.png\z/i } ||
              zip.find { |x| x.name =~ /\.(png|jpe?g)\z/i }
          return false unless e
          data = zip.read(e)
          return false unless data && !data.empty?
          File.open(out, 'wb') { |f| f.write(data) }
          true
        end

        def extract_skp(path, out)
          if ZipReader.zip?(path)
            zip = ZipReader.new(path)
            e = zip.find { |x| x.name =~ /thumbnail[^\/]*\.png\z/i } || zip.find { |x| x.name =~ /\.png\z/i }
            if e
              data = zip.read(e)
              if data && !data.empty?
                File.open(out, 'wb') { |f| f.write(data) }
                return true
              end
            end
            return false
          end
          scan_png(path, out)
        end

        def scan_png(path, out)
          File.open(path, 'rb') do |f|
            buf = ''.b
            total = 0
            while (chunk = f.read(CHUNK))
              total += chunk.bytesize
              buf << chunk
              i = buf.index(PNG_SIG)
              if i
                loop do
                  j = buf.index(PNG_END, i)
                  if j
                    File.open(out, 'wb') { |o| o.write(buf[i...(j + PNG_END.bytesize)]) }
                    return true
                  end
                  more = f.read(CHUNK)
                  return false unless more
                  buf << more
                  return false if buf.bytesize - i > (12 << 20)
                end
              end
              buf = buf.bytesize > 16 ? buf[-16..-1] : buf
              break if total > MAX_SCAN
            end
          end
          false
        end

        # tif / tga previews: let SketchUp decode the image and write a PNG copy.
        def convert_texture(path, out)
          model = Sketchup.active_model
          model.start_operation('Banian thumbnail', true)
          begin
            m = model.materials.add('banian_tmp_thumb')
            m.texture = path
            m.texture.write(out) if m.texture
          ensure
            model.abort_operation
          end
          File.file?(out)
        rescue StandardError
          false
        end
      end
    end
  end
end
