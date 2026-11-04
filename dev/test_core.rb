# Runs the SketchUp-independent parts of Banian Browser in plain Ruby.
#   ruby dev/test_core.rb
require 'tmpdir'
require 'json'
require 'fileutils'
require 'digest/md5'
require 'zlib'

# ---- minimal SketchUp stubs ---------------------------------------------------
module Sketchup
  def self.version; '26.1.0'; end
  def self.find_support_file(_n); Dir.tmpdir; end
  def self.require(path); Kernel.require(path); end
  def self.temp_dir; Dir.tmpdir; end
end
module UI
  @timers = {}
  @next = 0
  def self.start_timer(_s, _r = false, &blk)
    @next += 1
    @timers[@next] = blk
    @next
  end
  def self.stop_timer(id); @timers.delete(id); end
  # Runs pending timers the way SketchUp would, until none are left.
  def self.run_timers(limit = 100_000)
    limit.times do
      break if @timers.empty?
      @timers.values.each(&:call)
    end
  end
end

$fails = 0
def check(name, cond)
  puts "#{cond ? 'PASS' : 'FAIL'}  #{name}"
  $fails += 1 unless cond
end

tmp = Dir.mktmpdir('bb_test')
ENV['LOCALAPPDATA'] = tmp
ENV['HOME'] = tmp
FileUtils.mkdir_p(File.join(tmp, 'Library', 'Application Support'))

module BanianStudio
  module BanianBrowser
    PLUGIN_DIR = File.expand_path('../src/banian_browser', __dir__)
    DICT = 'BanianBrowser'
    module Dialog
      @events = []
      class << self; attr_reader :events; end
      def self.emit(e, d); @events << [e, d]; end
    end
  end
end
%w[util settings i18n zip_reader thumbnails library].each do |f|
  require File.join(BanianStudio::BanianBrowser::PLUGIN_DIR, f)
end
BB = BanianStudio::BanianBrowser

# ---- fixtures -------------------------------------------------------------------
png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].pack('C*') + 'FAKEDATA'.b + 'IEND'.b + [0xAE, 0x42, 0x60, 0x82].pack('C*')
lib = File.join(tmp, 'کتابخانه lib')
FileUtils.mkdir_p(File.join(lib, 'Furniture', 'Chairs'))
FileUtils.mkdir_p(File.join(lib, 'Materials', 'Wood'))
FileUtils.mkdir_p(File.join(lib, '.hidden'))
header = "\xFF\xFE\xFF\x0E".b + 'SketchUp Model'.encode('UTF-16LE').b + "\xFF\xFE\xFF\x0A".b + '{24.0.594}'.encode('UTF-16LE').b
skp = File.join(lib, 'Furniture', 'Chairs', 'صندلی Chair.skp')
File.binwrite(skp, header + ('x' * 5000).b + png + ('y' * 100).b)
File.binwrite(File.join(lib, 'Furniture', 'Table.skp'), header + ('z' * 100).b)
File.binwrite(File.join(lib, 'Furniture', 'Table.jpg'), 'jpg-sidecar')
File.binwrite(File.join(lib, 'Materials', 'Wood', 'Oak.jpg'), 'jpg')
File.binwrite(File.join(lib, 'Materials', 'Wood', 'readme.txt'), 'x')
File.binwrite(File.join(lib, 'Furniture', 'Lamp.fbx'), 'fbx')
File.binwrite(File.join(lib, 'Furniture', 'Lamp.png'), 'sidecar')
File.binwrite(File.join(lib, '.hidden', 'Secret.skp'), header)
# a real zip (.skm) made with Ruby's zlib (raw deflate)
def make_zip(path, files)
  out = ''.b
  cd = ''.b
  files.each do |name, data|
    z = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    comp = z.deflate(data, Zlib::FINISH)
    z.close
    crc = Zlib.crc32(data)
    off = out.bytesize
    out << ['PK', 3, 4].pack('a2CC') << [20, 0, 8, 0, 0, crc, comp.bytesize, data.bytesize, name.bytesize, 0].pack('vvvvvVVVvv') << name.b << comp
    cd << ['PK', 1, 2].pack('a2CC') << [20, 20, 0, 8, 0, 0, crc, comp.bytesize, data.bytesize, name.bytesize, 0, 0, 0, 0, 0, off].pack('vvvvvvVVVvvvvvVV') << name.b
  end
  cdoff = out.bytesize
  out << cd << ['PK', 5, 6].pack('a2CC') << [0, 0, files.size, files.size, cd.bytesize, cdoff, 0].pack('vvvvVVv')
  File.binwrite(path, out)
end
skm = File.join(lib, 'Materials', 'Wood', 'Walnut.skm')
make_zip(skm, 'document.xml' => '<x/>', 'doc_thumbnail.png' => png)

# ---- tests ------------------------------------------------------------------------
check('skp version read from header', BB::Util.skp_version(skp) == 24)
check('su_year', BB::Util.su_year(27) == 2027)
check('file_url escapes unicode + spaces', BB::Util.file_url('C:/a b/صندلی.png').start_with?('file:///C:/a%20b/%D8%B5'))
check('file_url mac path', BB::Util.file_url('/Users/x/a.png') == 'file:///Users/x/a.png')
check('sidecar found', BB::Util.sidecar_for(File.join(lib, 'Furniture', 'Table.skp')).end_with?('Table.jpg'))
check('zip reader lists entries', BB::ZipReader.new(skm).entries.map(&:name).sort == %w[doc_thumbnail.png document.xml])

BB::Settings.data['roots'] = [{ 'path' => BB::Util.norm(lib), 'type' => 'both', 'name' => 'lib' }]
BB::Library.scan(lib)
UI.run_timers
ev = BB::Dialog.events.select { |e, _| e == 'index' }.last
idx = ev && ev[1]
check('scan produced an index', idx.is_a?(Hash))
names = idx['items'].map { |i| i['n'] }.sort
check('items found (sidecar + hidden + txt skipped)', names == ['Lamp', 'Oak', 'Table', 'Walnut', 'صندلی Chair'])
check('3D formats listed as mesh', idx['items'].find { |i| i['n'] == 'Lamp' }['k'] == 'mesh')
check('folders become categories', idx['folders'].map { |f| f['n'] }.sort == %w[Chairs Furniture Materials Wood])
chair = idx['items'].find { |i| i['n'] == 'صندلی Chair' }
check('model kind + version stored', chair['k'] == 'model' && chair['v'] == 24)
check('texture kind', idx['items'].find { |i| i['n'] == 'Oak' }['k'] == 'texture')
check('index cached on disk', BB::Library.cached_index(lib)['items'].length == 5)

u = BB::Thumbnails.resolve(skp)
check('skp embedded png extracted', u && File.binread(BB::Thumbnails.cache_file(skp)) == png)
u2 = BB::Thumbnails.resolve(skm)
check('skm thumbnail extracted', u2 && File.binread(BB::Thumbnails.cache_file(skm)) == png)
check('sidecar used as thumbnail', BB::Thumbnails.resolve(File.join(lib, 'Furniture', 'Table.skp')).end_with?('Table.jpg?v=' + File.mtime(File.join(lib, 'Furniture', 'Table.jpg')).to_i.to_s))
check('image is its own thumbnail', BB::Thumbnails.resolve(File.join(lib, 'Materials', 'Wood', 'Oak.jpg')).include?('Oak.jpg'))

# incremental rescan: unchanged folders are not read again
old = Time.now - 3600
Dir.glob(File.join(lib, '**', '*')).select { |d| File.directory?(d) }.push(lib).each { |d| File.utime(old, old, d) }
BB::Library.scan(lib, true)
UI.run_timers
BB::Dialog.events.clear
reads = 0
BB::Util.singleton_class.send(:alias_method, :orig_skp_version, :skp_version)
BB::Util.define_singleton_method(:skp_version) { |p| reads += 1; orig_skp_version(p) }
BB::Library.scan(lib)
UI.run_timers
check('unchanged library: no re-render, no file reads', BB::Dialog.events.map(&:first) == %w[scanning index_same] && reads.zero?)
File.binwrite(File.join(lib, 'Furniture', 'Chairs', 'New Chair.skp'), header)
BB::Dialog.events.clear
BB::Library.scan(lib)
UI.run_timers
ev2 = BB::Dialog.events.find { |e, _| e == 'index' }
check('new file found by incremental scan', ev2 && ev2[1]['items'].any? { |i| i['n'] == 'New Chair' } && ev2[1]['items'].length == 6)
check('only the changed file header read', reads == 1)
BB::Dialog.events.clear
BB::Library.scan(lib)
UI.run_timers
check('after the change it is stable again', BB::Dialog.events.map(&:first) == %w[scanning index_same])
File.delete(File.join(lib, 'Furniture', 'Chairs', 'New Chair.skp'))
BB::Library.scan(lib, true)
UI.run_timers

raw = BB::Library.all_cached_json
check('cached indexes sent as raw JSON', raw.is_a?(BB::RawJSON) && JSON.parse(raw).first['items'].length == 5)

# file operations
r = BB::Library.rename(skp, 'Chair Renamed')
UI.run_timers
check('rename keeps extension', r['path'].end_with?('Chair Renamed.skp') && File.exist?(r['path']))
UI.run_timers
m = BB::Library.mkdir(File.join(lib, 'Furniture'), 'New/Folder?')
check('mkdir sanitises name', File.directory?(m['path']) && File.basename(m['path']) == 'New_Folder_')
UI.run_timers
mv = BB::Library.move([r['path']], m['path'])
check('move file', mv['moved'].length == 1 && File.exist?(mv['moved'][0]))
check('favorite toggle', BB::Settings.toggle_favorite(mv['moved'][0]) == true)
BB::Library.delete([mv['moved'][0]])
check('delete file + forget favorite', !File.exist?(mv['moved'][0]) && BB::Settings['favorites'].empty?)
# pinned folders
fur = BB::Util.norm(File.join(lib, 'Furniture'))
mats_dir = BB::Util.norm(File.join(lib, 'Materials'))
BB::Settings.toggle_pin('models', fur)
BB::Settings.toggle_pin('models', mats_dir)
BB::Settings.toggle_pin('materials', mats_dir)
check('pin per view', BB::Settings['pinned']['models'] == [fur, mats_dir] && BB::Settings['pinned']['materials'] == [mats_dir])
BB::Settings.move_pin('models', mats_dir, -1)
check('pin reorder', BB::Settings['pinned']['models'] == [mats_dir, fur])
BB::Settings.rename_path(fur, fur + ' 2')
check('pin follows rename', BB::Settings['pinned']['models'].include?(fur + ' 2'))
BB::Settings.forget_path(mats_dir)
check('pin forgotten with folder', BB::Settings['pinned']['models'] == [fur + ' 2'] && BB::Settings['pinned']['materials'].empty?)
BB::Settings.toggle_pin('models', fur + ' 2')
check('unpin', BB::Settings['pinned']['models'].empty?)
check('menus are English', BB::I18n.en(:open_browser) == 'Open Banian Browser')
check('settings persisted as json', JSON.parse(File.read(BB::Settings.file))['roots'].length == 1)
check('i18n fa/en', BB::I18n.t(:yes) == 'بله' && (BB::Settings['language'] = 'en') && BB::I18n.t(:yes) == 'Yes')

# placing tool: arrow keys turn by the place_rotate setting (logic only, no geometry)
VK_UP = 38; VK_DOWN = 40; VK_LEFT = 37; VK_RIGHT = 39; COPY_MODIFIER_KEY = 17
module Sketchup
  class InputPoint; def valid?; false; end; end
  class << self
    attr_accessor :status_text, :vcb_label, :vcb_value
    def active_model
      v = Object.new
      def v.invalidate; end
      m = Object.new
      m.define_singleton_method(:active_view) { v }
      m
    end
  end
end
module Geom; class Transformation; end; end
require File.join(BB::PLUGIN_DIR, 'tools', 'tool_base')
require File.join(BB::PLUGIN_DIR, 'tools', 'place_tool')
bounds = Object.new
defn = Object.new
defn.define_singleton_method(:bounds) { bounds }
defn.define_singleton_method(:entities) { [] }
tool = BB::PlaceTool.new(defn)
tool.activate
BB::Settings['place_rotate'] = 90
tool.onKeyDown(VK_UP, false, 0, nil)
check('Up turns by 90', tool.instance_variable_get(:@angle) == 90.0 && BB::PlaceTool.current == tool)
BB::Settings['place_rotate'] = 45
tool.turn(-1)
tool.onKeyDown(VK_DOWN, false, 0, nil)
check('step from settings, Down / forwarded turn', tool.instance_variable_get(:@angle) == 0.0)
check('status shows step', Sketchup.status_text.to_s.include?('45'))
check('placing announced to the window', BB::Dialog.events.any? { |e, d| e == 'placing' && d == true })

FileUtils.rm_rf(tmp)
puts $fails.zero? ? "\nALL PASSED" : "\n#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)
