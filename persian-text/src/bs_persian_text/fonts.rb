# encoding: UTF-8
# Scans installed font files (Windows system + per-user folders) and reads
# their names directly from the OpenType tables, so no Windows API is needed.

require 'json'
require 'fileutils'

module BanianStudio
  module PersianText
    module Fonts

      FONT_EXTS = %w[.ttf .otf .ttc .otc].freeze
      CACHE_VERSION = 2

      class << self

        def font_dirs
          dirs = []
          windir = ENV['WINDIR'] || ENV['SystemRoot'] || 'C:/Windows'
          dirs << File.join(windir, 'Fonts')
          if ENV['LOCALAPPDATA']
            dirs << File.join(ENV['LOCALAPPDATA'], 'Microsoft', 'Windows', 'Fonts')
          end
          # macOS (not the main target, but harmless)
          dirs << '/Library/Fonts'
          dirs << '/System/Library/Fonts'
          dirs << File.join(ENV['HOME'], 'Library', 'Fonts') if ENV['HOME']
          dirs.map { |d| d.tr('\\', '/') }.uniq.select { |d| File.directory?(d) }
        end

        def font_files
          files = []
          font_dirs.each do |dir|
            begin
              Dir.entries(dir).each do |name|
                next if name.start_with?('.')
                next unless FONT_EXTS.include?(File.extname(name).downcase)
                files << File.join(dir, name)
              end
            rescue StandardError
              next
            end
          end
          files
        end

        # Returns an Array of Hashes:
        # { 'path', 'index', 'family', 'style', 'full', 'weight', 'italic', 'fa' }
        def list(force = false)
          cache = force ? {} : read_cache
          result = []
          fresh = {}
          font_files.each do |path|
            begin
              st = File.stat(path)
              key = path.downcase
              stamp = "#{st.size}-#{st.mtime.to_i}"
              entry = cache[key]
              faces = if entry && entry['stamp'] == stamp
                        entry['faces']
                      else
                        parse_file(path)
                      end
              fresh[key] = { 'stamp' => stamp, 'faces' => faces }
              faces.each { |f| result << f.merge('path' => path) }
            rescue StandardError
              next
            end
          end
          write_cache(fresh)
          result.sort_by { |f| [f['family'].to_s.downcase, f['weight'].to_i, f['italic'] ? 1 : 0, f['style'].to_s] }
        end

        # ---------------------------------------------------------------------
        # OpenType parsing (headers only)
        # ---------------------------------------------------------------------

        def parse_file(path)
          faces = []
          File.open(path, 'rb') do |io|
            tag = io.read(4)
            offsets = [0]
            if tag == 'ttcf'
              io.seek(8)
              n = io.read(4).unpack('N').first
              n = 64 if n > 64
              offsets = io.read(4 * n).unpack('N*')
            end
            offsets.each_with_index do |off, idx|
              face = parse_face(io, off)
              next unless face
              face['index'] = idx
              faces << face
            end
          end
          faces
        end

        def parse_face(io, off)
          io.seek(off + 4)
          num_tables = io.read(2).unpack('n').first
          io.seek(off + 12)
          tables = {}
          num_tables.times do
            t, _chk, toff, tlen = io.read(16).unpack('a4NNN')
            tables[t] = [toff, tlen]
          end
          return nil unless tables['name'] && tables['cmap']
          names = read_names(io, *tables['name'])
          family = names[16] || names[1]
          return nil if family.nil? || family.empty?
          style = names[17] || names[2] || 'Regular'
          weight = 400
          italic = false
          if tables['OS/2']
            io.seek(tables['OS/2'][0] + 4)
            weight = io.read(2).unpack('n').first
            io.seek(tables['OS/2'][0] + 62)
            fs_sel = io.read(2).to_s.unpack('n').first.to_i
            italic = (fs_sel & 1) == 1
          end
          {
            'family' => family,
            'style' => style,
            'full' => names[4] || "#{family} #{style}",
            'weight' => weight,
            'italic' => italic,
            'fa' => covers_persian?(io, *tables['cmap']),
            'variable' => !tables['fvar'].nil?
          }
        end

        # Name IDs 1, 2, 4, 16, 17 (prefers Windows/English names).
        def read_names(io, toff, _tlen)
          io.seek(toff)
          _format, count, str_off = io.read(6).unpack('nnn')
          recs = io.read(12 * count).unpack('n*').each_slice(6).to_a
          wanted = [1, 2, 4, 16, 17]
          best = {}
          recs.each do |plat, enc, lang, nid, len, soff|
            next unless wanted.include?(nid)
            score = if plat == 3 && lang == 0x0409 then 3
                    elsif plat == 3 then 2
                    elsif plat == 1 && enc == 0 && lang == 0 then 1
                    else next
                    end
            next if best[nid] && best[nid][0] >= score
            best[nid] = [score, plat, enc, len, soff]
          end
          out = {}
          best.each do |nid, (_score, plat, _enc, len, soff)|
            io.seek(toff + str_off + soff)
            raw = io.read(len).to_s
            str = if plat == 3
                    raw.force_encoding('UTF-16BE').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
                  else
                    raw.force_encoding('ISO-8859-1').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
                  end
            str = str.delete("\u0000").strip
            out[nid] = str unless str.empty?
          end
          out
        end

        # Checks whether the Unicode cmap covers PEH (U+067E) and Persian YEH (U+06CC).
        def covers_persian?(io, toff, _tlen)
          io.seek(toff)
          _ver, n = io.read(4).unpack('nn')
          subs = io.read(8 * n).unpack('nnN' * n).each_slice(3).to_a
          sub = subs.find { |p, e, _| p == 3 && e == 10 } || subs.find { |p, e, _| p == 3 && e == 1 } ||
                subs.find { |p, _e, _| p == 0 }
          return false unless sub
          io.seek(toff + sub[2])
          fmt = io.read(2).unpack('n').first
          cps = [0x067E, 0x06CC]
          case fmt
          when 4
            io.read(4) # length, language
            seg_x2 = io.read(2).unpack('n').first
            io.read(6)
            ends = io.read(seg_x2).unpack('n*')
            io.read(2)
            starts = io.read(seg_x2).unpack('n*')
            cps.all? { |cp| ends.each_index.any? { |i| starts[i] <= cp && cp <= ends[i] && ends[i] != 0xFFFF } }
          when 12
            io.read(10) # reserved, length, language
            ngroups = io.read(4).unpack('N').first
            groups = io.read(12 * ngroups).unpack('N*').each_slice(3).to_a
            cps.all? { |cp| groups.any? { |s, e, _| s <= cp && cp <= e } }
          else
            false
          end
        rescue StandardError
          false
        end

        # ---------------------------------------------------------------------
        # Cache
        # ---------------------------------------------------------------------

        def data_dir
          base = ENV['APPDATA'] || ENV['HOME'] || Dir.pwd
          dir = File.join(base.tr('\\', '/'), 'BanianStudio', 'PersianText')
          FileUtils.mkdir_p(dir) unless File.directory?(dir)
          dir
        rescue StandardError
          nil
        end

        def cache_path
          dir = data_dir
          dir ? File.join(dir, 'fonts_cache.json') : nil
        end

        def read_cache
          path = cache_path
          return {} unless path && File.exist?(path)
          data = JSON.parse(File.read(path, encoding: 'UTF-8'))
          data['version'] == CACHE_VERSION ? (data['files'] || {}) : {}
        rescue StandardError
          {}
        end

        def write_cache(files)
          path = cache_path
          return unless path
          File.open(path, 'w:UTF-8') { |f| f.write(JSON.generate('version' => CACHE_VERSION, 'files' => files)) }
        rescue StandardError
          nil
        end

      end
    end
  end
end
