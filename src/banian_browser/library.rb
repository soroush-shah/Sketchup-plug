module BanianStudio
  module BanianBrowser
    # Library roots, recursive folder scanning (sub-folders become categories),
    # cached index files and file operations.
    module Library
      SKIP_DIRS = %w[__macosx .git .svn $recycle.bin thumbs .thumbs @eadir].freeze
      SLICE = 0.05

      class << self
        def roots
          Settings['roots']
        end

        def root_for(path)
          p = Util.norm(path)
          roots.map { |r| r['path'] }.select { |r| p == r || p.start_with?(r + '/') }.max_by(&:length)
        end

        def add_root(path, type)
          p = Util.norm(path)
          return nil unless File.directory?(p)
          existing = roots.find { |r| r['path'] == p }
          if existing
            existing['type'] = type
          else
            roots << { 'path' => p, 'type' => type, 'name' => File.basename(p) }
          end
          Settings.save
          scan(p)
          p
        end

        def remove_root(path)
          p = Util.norm(path)
          roots.reject! { |r| r['path'] == p }
          Settings.save
          f = index_file(p)
          File.delete(f) if File.exist?(f)
        end

        def set_root(path, attrs)
          r = roots.find { |x| x['path'] == Util.norm(path) }
          return unless r
          r['type'] = attrs['type'] if attrs['type']
          r['name'] = attrs['name'] if attrs['name'] && !attrs['name'].to_s.strip.empty?
          Settings.save
        end

        def index_file(root)
          File.join(Settings.sub_dir('index'), Digest::MD5.hexdigest(Util.norm(root)) + '.json')
        end

        def cached_index(root)
          f = index_file(root)
          return nil unless File.exist?(f)
          JSON.parse(File.read(f, :encoding => 'UTF-8'))
        rescue StandardError
          nil
        end

        def all_cached
          roots.map { |r| cached_index(r['path']) || { 'root' => r['path'], 'folders' => [], 'items' => [], 'pending' => true } }
        end

        def scanning?(root)
          @scanners && @scanners[Util.norm(root)]
        end

        # Asynchronous, chunked scan. Pushes the result to the dialog when done.
        def scan(root)
          root = Util.norm(root)
          @scanners ||= {}
          return if @scanners[root]
          @scanners[root] = Scanner.new(root) do |index|
            @scanners.delete(root)
            begin
              File.open(index_file(root), 'wb') { |f| f.write(JSON.generate(index)) }
            rescue StandardError => e
              Util.log_error(e, 'index write')
            end
            Dialog.emit('index', index)
          end
          Dialog.emit('scanning', 'root' => root)
          @scanners[root].start
        end

        def scan_all
          roots.each { |r| scan(r['path']) }
        end

        # ---- file operations (all paths UTF-8, forward slashes) --------------------
        def rename(path, new_name)
          p = Util.norm(path)
          name = Util.safe_filename(new_name)
          ext = File.directory?(p) ? '' : File.extname(p)
          name += ext unless ext.empty? || name.downcase.end_with?(ext.downcase)
          dst = Util.join(File.dirname(p), name)
          return { 'error' => I18n.t(:exists) } if File.exist?(dst) && dst.downcase != p.downcase
          side = File.directory?(p) ? nil : Util.sidecar_for(p)
          File.rename(p, dst)
          if side
            sdst = dst.sub(/\.[^.\/]+\z/, '') + File.extname(side)
            File.rename(side, sdst) unless File.exist?(sdst)
          end
          Settings.rename_path(p, dst)
          rescan_for(dst)
          { 'path' => dst }
        end

        def delete(paths)
          Array(paths).each do |path|
            p = Util.norm(path)
            next unless File.exist?(p)
            if File.directory?(p)
              FileUtils.rm_rf(p)
            else
              side = Util.sidecar_for(p)
              File.delete(p)
              File.delete(side) if side && File.exist?(side)
            end
            Settings.forget_path(p)
          end
          rescan_for(Array(paths).first) unless Array(paths).empty?
          true
        end

        def mkdir(parent, name)
          dir = Util.join(parent, Util.safe_filename(name))
          return { 'error' => I18n.t(:exists) } if File.exist?(dir)
          FileUtils.mkdir_p(dir)
          rescan_for(dir)
          { 'path' => dir }
        end

        def move(paths, dest_dir)
          dest = Util.norm(dest_dir)
          return { 'error' => 'invalid' } unless File.directory?(dest)
          moved = []
          Array(paths).each do |path|
            p = Util.norm(path)
            next unless File.exist?(p)
            next if File.dirname(p) == dest || dest.start_with?(p + '/')
            dst = Util.unique_path(Util.join(dest, File.basename(p)))
            side = File.directory?(p) ? nil : Util.sidecar_for(p)
            FileUtils.mv(p, dst)
            if side
              sdst = dst.sub(/\.[^.\/]+\z/, '') + File.extname(side)
              FileUtils.mv(side, sdst) unless File.exist?(sdst)
            end
            Settings.rename_path(p, dst)
            moved << dst
          end
          roots_touched = (Array(paths) + [dest]).map { |x| root_for(x) }.compact.uniq
          roots_touched.each { |r| scan(r) }
          { 'moved' => moved }
        end

        def copy_in(files, dest_dir)
          dest = Util.norm(dest_dir)
          files.each do |f|
            FileUtils.cp(f, Util.unique_path(Util.join(dest, File.basename(f))))
          end
          rescan_for(dest)
        end

        def rescan_for(path)
          r = root_for(path)
          scan(r) if r
        end
      end

      # Walks a folder tree a few milliseconds at a time (keeps SketchUp responsive).
      class Scanner
        def initialize(root, &done)
          @root = root
          @done = done
        end

        def start
          @stack = [@root]
          @folders = []
          @items = []
          @timer = UI.start_timer(0.01, true) { tick }
        end

        def tick
          return if @busy
          @busy = true
          t0 = Time.now
          while (dir = @stack.pop)
            scan_dir(dir)
            break if Time.now - t0 > SLICE
          end
          finish if @stack.empty?
        rescue StandardError => e
          Util.log_error(e, 'scan')
          finish
        ensure
          @busy = false
        end

        def finish
          UI.stop_timer(@timer) if @timer
          @timer = nil
          index = {
            'root' => @root,
            'scanned_at' => Time.now.to_i,
            'exists' => File.directory?(@root),
            'folders' => @folders,
            'items' => @items
          }
          @done.call(index)
        end

        def list(dir)
          Dir.entries(dir, :encoding => 'UTF-8')
        rescue StandardError
          begin
            Dir.entries(dir).map { |e| Util.utf8(e) }
          rescue StandardError
            []
          end
        end

        def scan_dir(dir)
          names = list(dir).map { |n| Util.utf8(n) }.reject { |n| n == '.' || n == '..' || n.start_with?('.') }
          files = []
          names.sort_by(&:downcase).each do |n|
            full = "#{dir}/#{n}"
            if File.directory?(full)
              next if SKIP_DIRS.include?(n.downcase)
              @folders << { 'p' => full, 'n' => n, 'd' => dir }
              @stack.push(full)
            else
              files << n
            end
          end
          bases = {}
          files.each do |n|
            e = File.extname(n).downcase
            bases[n.sub(/\.[^.]+\z/, '').downcase] = true if e == '.skp' || e == '.skm' || Util::MESH_EXTS.include?(e)
          end
          files.each do |n|
            ext = File.extname(n).downcase
            kind = Util.kind_of_ext(ext)
            next unless kind
            next if n.start_with?('~') || n =~ /\.skb\z/i
            # previews sitting next to a model/material are thumbnails, not textures
            next if kind == 'texture' && bases[n.sub(/\.[^.]+\z/, '').downcase]
            full = "#{dir}/#{n}"
            st = begin
              File.stat(full)
            rescue StandardError
              next
            end
            item = {
              'p' => full,
              'n' => n.sub(/\.[^.]+\z/, ''),
              'e' => ext.delete('.'),
              'k' => kind,
              'f' => dir,
              's' => st.size,
              'm' => st.mtime.to_i
            }
            item['v'] = Util.skp_version(full) if kind == 'model'
            @items << item
          end
        end
      end
    end
  end
end
