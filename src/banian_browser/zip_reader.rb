module BanianStudio
  module BanianBrowser
    # Minimal read-only ZIP reader (stored + deflate), enough to pull thumbnails
    # out of .skm material files without any external gem.
    class ZipReader
      Entry = Struct.new(:name, :method, :csize, :usize, :offset)

      EOCD = 'PK'.b + [5, 6].pack('CC')
      CDIR = 'PK'.b + [1, 2].pack('CC')
      LOCAL = 'PK'.b + [3, 4].pack('CC')

      def self.zip?(path)
        File.open(path, 'rb') { |f| f.read(4) } == LOCAL
      rescue StandardError
        false
      end

      attr_reader :entries

      def initialize(path)
        @path = path
        @entries = read_entries
      end

      def find(&block)
        @entries.find(&block)
      end

      def read(entry)
        File.open(@path, 'rb') do |f|
          f.seek(entry.offset)
          head = f.read(30)
          return nil unless head && head[0, 4] == LOCAL
          nlen = head[26, 2].unpack('v')[0]
          elen = head[28, 2].unpack('v')[0]
          f.seek(entry.offset + 30 + nlen + elen)
          data = f.read(entry.csize)
          case entry.method
          when 0 then data
          when 8 then inflate(data)
          end
        end
      rescue StandardError
        nil
      end

      private

      def inflate(data)
        z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        out = z.inflate(data)
        begin
          z.finish
        rescue StandardError
          nil
        end
        z.close
        out
      end

      def read_entries
        File.open(@path, 'rb') do |f|
          size = f.size
          tail_len = [size, 65_557].min
          f.seek(size - tail_len)
          tail = f.read(tail_len)
          idx = tail.rindex(EOCD)
          return [] unless idx
          count = tail[idx + 10, 2].unpack('v')[0]
          cd_size = tail[idx + 12, 4].unpack('V')[0]
          cd_off = tail[idx + 16, 4].unpack('V')[0]
          f.seek(cd_off)
          cd = f.read(cd_size) || ''
          list = []
          pos = 0
          count.times do
            break unless cd[pos, 4] == CDIR
            method = cd[pos + 10, 2].unpack('v')[0]
            csize = cd[pos + 20, 4].unpack('V')[0]
            usize = cd[pos + 24, 4].unpack('V')[0]
            nlen = cd[pos + 28, 2].unpack('v')[0]
            elen = cd[pos + 30, 2].unpack('v')[0]
            clen = cd[pos + 32, 2].unpack('v')[0]
            off = cd[pos + 42, 4].unpack('V')[0]
            name = Util.utf8(cd[pos + 46, nlen])
            list << Entry.new(name, method, csize, usize, off)
            pos += 46 + nlen + elen + clen
          end
          list
        end
      rescue StandardError
        []
      end
    end
  end
end
