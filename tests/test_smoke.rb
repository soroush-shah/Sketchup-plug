# End-to-end smoke test against a mocked SketchUp API.
# Run: ruby tests/test_smoke.rb
require 'tmpdir'
require 'json'
require_relative 'mock_sketchup'

ROOT = File.expand_path('../src/banian_floor_studio', __dir__)
module BanianStudio
  module FloorStudio
    PATH = ROOT
    VERSION = 'test'.freeze
  end
end
%w[core/geom2d core/patterns core/params core/region core/materials core/builder ui/dialog].each { |f| require File.join(ROOT, f) }

FS = BanianStudio::FloorStudio

class FakeDlg
  attr_reader :msgs
  def initialize; @msgs = []; end
  def execute_script(s)
    raise 'bad script' unless s.start_with?('FS.recv(')
    @msgs << JSON.parse(s[8..-2])
  end
  def visible?; true; end
  def last(type); @msgs.reverse.find { |m| m['type'] == type }; end
end

dlg = FakeDlg.new
FS::Studio.instance_variable_set(:@dlg, dlg)
model = Sketchup.active_model
mm = 1 / 25.4
room = model.entities.add_face([[0, 0, 0], [3000 * mm, 0, 0], [3000 * mm, 2000 * mm, 0], [0, 2000 * mm, 0]].map { |p| Geom::Point3d.new(*p) })
wall = model.entities.add_face([[0, 0, 0], [3000 * mm, 0, 0], [3000 * mm, 0, 2500 * mm], [0, 0, 2500 * mm]].map { |p| Geom::Point3d.new(*p) })
m1 = model.materials.add('Oak'); m1.texture = 'oak.jpg'
m2 = model.materials.add('Grey'); m2.color = Sketchup::Color.new(120, 120, 120)

fails = 0
check = lambda do |c, msg|
  if c then print '.' else fails += 1; puts "\nFAIL #{msg}" end
end

FS::Studio.on_ready
check.call(dlg.last('init'), 'init sent')

# preview without selection (sample)
FS::Studio.on_preview('pattern' => 'herringbone', 'length' => 600, 'width' => 100)
pv = dlg.last('preview')
check.call(pv && pv['source'] == 'none' && pv['tiles'].length > 10, 'sample preview')

profiles = %w[square chamfer round bullnose cove ogee]
FS::Patterns::LIST.each_with_index do |pat, i|
  [room, wall].each do |face|
    model.selection.clear
    model.selection.add(face)
    ui = { 'mode' => '3d', 'pattern' => pat, 'length' => 600, 'width' => 150, 'gap' => 3,
           'materials' => %w[Oak Grey], 'weights' => [2, 1], 'shades' => 3,
           'profile' => profiles[i % profiles.length], 'profile_size' => 2, 'imp_angle' => 0.5, 'imp_height' => 0.5,
           'anchor' => %w[corner center world][i % 3], 'angle' => 15 * i, 'align' => i.even? ? 'edge' : 'world' }
    dlg.msgs.clear
    FS::Studio.on_preview(ui)
    check.call(dlg.last('preview'), "preview #{pat}")
    FS::Studio.safe { FS::Studio.on_apply(ui) }
    d = dlg.last('done')
    err = dlg.last('error')
    check.call(d && d['full'].to_i > 0, "apply 3d #{pat}: #{err && err['detail']}")
  end
end

# divide mode
model.selection.clear
model.selection.add(room)
dlg.msgs.clear
FS::Studio.safe { FS::Studio.on_apply('mode' => 'divide', 'pattern' => 'brick', 'length' => 600, 'width' => 300, 'gap' => 0) }
check.call(dlg.last('done'), "divide: #{dlg.last('error') && dlg.last('error')['detail']}")

# texture mode
dlg.msgs.clear
FS::Studio.safe { FS::Studio.on_apply('mode' => 'texture', 'pattern' => 'chevron', 'length' => 600, 'width' => 100) }
td = dlg.last('texture_data')
check.call(td && td['tiles'].length > 0 && td['seamless'], 'texture data')
png = 'data:image/png;base64,' + ['fakepng'].pack('m0')
FS::Studio.safe { FS::Studio.on_apply_texture('state' => { 'mode' => 'texture', 'pattern' => 'chevron' }, 'png' => png, 'w' => td['w'], 'h' => td['h']) }
check.call(dlg.last('done') && dlg.last('done')['texture'], "texture apply #{dlg.last('error') && dlg.last('error')['detail']}")

# edit existing layout
g = model.entities.grep(Sketchup::Group).find { |x| FS::Builder.generated?(x) }
model.selection.clear
model.selection.add(g)
dlg.msgs.clear
FS::Studio.send_selection
check.call(dlg.last('source')['kind'] == 'group', 'edit source')
FS::Studio.safe { FS::Studio.on_apply('mode' => '3d', 'pattern' => 'hexagon', 'length' => 250) }
check.call(dlg.last('done'), "rebuild #{dlg.last('error') && dlg.last('error')['detail']}")
FS::Studio.shuffle
check.call(model.ops.last == [:commit], 'shuffle')

# too many tiles -> error message, no crash
model.selection.clear
model.selection.add(room)
dlg.msgs.clear
FS::Studio.safe { FS::Studio.on_apply('mode' => '3d', 'pattern' => 'grid', 'length' => 2, 'width' => 2, 'gap' => 0) }
check.call(dlg.last('error') && dlg.last('error')['code'] == 'too_many', 'too many guard')

# state roundtrip (unicode)
FS::Studio.save_state(JSON.generate('lang' => 'fa', 'note' => 'کاشی'))
check.call(FS::Studio.load_state['note'] == 'کاشی', 'state roundtrip')

puts "\nuv mapping calls: #{$uv_calls}, defs: #{model.definitions.length}"
puts fails.zero? ? 'SMOKE OK' : "#{fails} FAILURES"
exit(fails.zero? ? 0 : 1)
