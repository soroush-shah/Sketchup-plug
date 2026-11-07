# Curved / multi-face surface tests (mocked SketchUp). Run: ruby tests/test_curved.rb
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
%w[core/geom2d core/patterns core/params core/region core/surface core/materials core/builder ui/dialog].each { |f| require File.join(ROOT, f) }
FS = BanianStudio::FloorStudio
MM = 1 / 25.4

$fails = 0
def check(c, msg)
  if c then print '.' else $fails += 1; puts "\nFAIL #{msg}" end
end

class FakeDlg
  attr_reader :msgs
  def initialize; @msgs = []; end
  def execute_script(s); @msgs << JSON.parse(s[8..-2]); end
  def visible?; true; end
  def last(t); @msgs.reverse.find { |m| m['type'] == t }; end
end
dlg = FakeDlg.new
FS::Studio.instance_variable_set(:@dlg, dlg)
model = Sketchup.active_model

# --- half-cylinder wall: R=2000, H=2500, 24 segments over 180 deg ----------
R = 2000 * MM
H = 2500 * MM
N = 24
pts = []
(0..N).each { |i| a = Math::PI * i / N; pts << [R * Math.cos(a), R * Math.sin(a), 0] }
(0..N).each { |i| a = Math::PI * i / N; pts << [R * Math.cos(a), R * Math.sin(a), H] }
top = N + 1
polys = (0...N).map { |i| [i, i + 1, top + i + 1, top + i] }
[3, 4, 10, 17].each { |i| polys[i] = polys[i].reverse } # inconsistent orientation
faces = Sketchup::Topo.build(model.entities, pts, polys, true)

comps = FS::Surface.components([faces[5]]) # one facet selected -> whole surface
check(comps.length == 1 && comps[0].length == N, "soft expansion -> #{comps.map(&:length)}")

p = FS::Params.from_ui('pattern' => 'brick', 'length' => 600, 'width' => 300, 'gap' => 3)
sf = FS::Surface.from_faces(faces, p)
chord = 2 * R * Math.sin(Math::PI / (2 * N))
area = FS::Geom2D.area(sf.region[:outer])
check((area - N * chord * H).abs < 1e-3 * area, "unrolled area #{area} vs #{N * chord * H}")
bb = FS::Geom2D.bbox(sf.region[:outer])
check(((bb[2] - bb[0]) - N * chord).abs < 1e-3 && ((bb[3] - bb[1]) - H).abs < 1e-3,
      "unrolled size #{(bb[2] - bb[0]) / MM} x #{(bb[3] - bb[1]) / MM}")
check(!sf.planar && !sf.overlap, 'curved, no overlap')

rng = Random.new(1)
bad = 0
60.times do
  q = [bb[0] + rng.rand * (bb[2] - bb[0]), bb[1] + rng.rand * (bb[3] - bb[1])]
  p3 = sf.to3d(q)
  r = Math.hypot(p3.x, p3.y)
  back = sf.to2d(p3)
  bad += 1 if r > R + 1e-6 || r < R * Math.cos(Math::PI / N) - 1e-6 || (back[0] - q[0]).abs > 1e-6 || (back[1] - q[1]).abs > 1e-6
end
check(bad.zero?, "2D<->3D roundtrip on cylinder (bad #{bad})")

# --- generate 3D tiles on the outside (convex) and inside (concave) ---------
def tile_corners(model, grp, hl, hw)
  out = []
  grp.entities.each do |e|
    next unless e.is_a?(Sketchup::ComponentInstance)
    out << [[-hl, -hw], [hl, -hw], [hl, hw], [-hl, hw], [0, 0]].map { |c| e.transformation.apply(Geom::Point3d.new(c[0], c[1], 0)) }
  end
  out
end

[false, true].each do |flip|
  model.selection.clear
  model.selection.add(faces)
  dlg.msgs.clear
  ui = { 'mode' => '3d', 'pattern' => 'brick', 'length' => 600, 'width' => 300, 'gap' => 3, 'thickness' => 10,
         'profile' => 'chamfer', 'flip' => flip }
  FS::Studio.on_preview(ui)
  pv = dlg.last('preview')
  check(pv && pv['curved'] && pv['count'] == N, 'curved preview')
  FS::Studio.safe { FS::Studio.on_apply(ui) }
  d = dlg.last('done')
  check(d && d['full'] > 20, "curved 3d apply flip=#{flip}: #{dlg.last('error') && dlg.last('error')['detail']}")
  grp = model.entities.grep(Sketchup::Group).last
  check(grp.get_attribute('BanianFloorStudio', 'surface'), 'surface stored')
  corners = tile_corners(model, grp, 300 * MM, 150 * MM)
  check(corners.length > 20, "instances #{corners.length}")
  worst_in = 0.0
  worst_far = 0.0
  corners.each do |cs|
    cs.each do |c|
      r = Math.hypot(c.x, c.y)
      # outside: tile back plane never inside the wall; inside: never behind it
      pen = flip ? r - R : R * Math.cos(Math::PI / N) - r
      worst_in = pen if pen > worst_in
    end
    rc = Math.hypot(cs[4].x, cs[4].y)
    far = flip ? R - rc : rc - R
    worst_far = far if far > worst_far
  end
  puts format("\n  flip=%s: max penetration %.2f mm, max gap at tile centre %.1f mm", flip, worst_in / MM, worst_far / MM)
  check(worst_in < 0.05, "no penetration flip=#{flip} (#{(worst_in / MM).round(2)} mm)")
  check(worst_far < 30 * MM, "tiles hug the surface flip=#{flip} (#{(worst_far / MM).round(1)} mm)")
end

# --- edit / rebuild curved layout ------------------------------------------
g = model.entities.grep(Sketchup::Group).last
model.selection.clear
model.selection.add(g)
dlg.msgs.clear
FS::Studio.safe { FS::Studio.on_apply('mode' => '3d', 'pattern' => 'herringbone', 'length' => 400, 'width' => 80, 'gap' => 2) }
check(dlg.last('done'), "curved rebuild #{dlg.last('error') && dlg.last('error')['detail']}")

# --- custom anchor on curved surface ---------------------------------------
model.selection.clear
model.selection.add(faces)
dlg.msgs.clear
FS::Studio.on_set_anchor_local('x' => 1500, 'y' => 1000, 'state' => { 'pattern' => 'grid' })
an = dlg.last('anchor')
r3 = Math.hypot(an['pt'][0], an['pt'][1])
check((r3 - 2000).abs < 15, "anchor on the cylinder r=#{r3}")
FS::Studio.on_preview('pattern' => 'grid', 'anchor' => 'custom', 'anchor_pt' => an['pt'])
mk = dlg.last('preview')['marker']
check((mk[0] - 1500).abs < 0.5 && (mk[1] - 1000).abs < 0.5, "anchor roundtrip #{mk}")

# --- divide + texture on curved --------------------------------------------
dlg.msgs.clear
before = model.entities.grep(Sketchup::Edge).length
FS::Studio.safe { FS::Studio.on_apply('mode' => 'divide', 'pattern' => 'grid', 'length' => 500, 'width' => 500, 'gap' => 0) }
check(dlg.last('done'), "curved divide #{dlg.last('error') && dlg.last('error')['detail']}")
lines = model.entities.grep(Sketchup::Edge)[before..-1] || []
offc = lines.count do |e|
  [e.instance_variable_get(:@a), e.instance_variable_get(:@b)].any? do |q|
    r = Math.hypot(q.x, q.y)
    r > R + 1e-6 || r < R * Math.cos(Math::PI / N) - 1e-6 || q.z < -1e-6 || q.z > H + 1e-6
  end
end
check(lines.length > 30 && offc.zero?, "divide lines on surface #{lines.length}, off #{offc}")

dlg.msgs.clear
$uv_calls = 0
FS::Studio.safe { FS::Studio.on_apply_texture('state' => { 'mode' => 'texture', 'pattern' => 'grid' }, 'png' => 'data:image/png;base64,' + ['x'].pack('m0'), 'w' => 600, 'h' => 600) }
check(dlg.last('done') && $uv_calls == N * 2, "curved texture uv calls #{$uv_calls}")

# --- coplanar faces merge into one region ----------------------------------
m2 = Sketchup::Model.new
$model = m2
fl = Sketchup::Topo.build(m2.entities, [[5000, 0, 0], [6000, 0, 0], [7000, 0, 0], [7000, 800, 0], [6000, 800, 0], [5000, 800, 0]],
                          [[0, 1, 4, 5], [1, 2, 3, 4]], false)
cmp = FS::Surface.components(fl)
check(cmp.length == 1, 'coplanar faces grouped')
s2 = FS::Surface.from_faces(fl, FS::Params.from_ui({}))
check(s2.planar && (FS::Geom2D.area(s2.region[:outer]) - 2000 * 800).abs < 1, "planar merged area #{FS::Geom2D.area(s2.region[:outer])}")
check(FS::Surface.components([fl[0]]).length == 1 && FS::Surface.components([fl[0]])[0].length == 1, 'hard edges do not expand selection')

puts
puts $fails.zero? ? 'CURVED OK' : "#{$fails} FAILURES"
exit($fails.zero? ? 0 : 1)
