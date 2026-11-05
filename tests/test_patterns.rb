# Run: ruby tests/test_patterns.rb  (no SketchUp needed)
$LOAD_PATH.unshift File.expand_path('../src/banian_floor_studio/core', __dir__)
require 'geom2d'
require 'patterns'

FS = BanianStudio::FloorStudio
G = FS::Geom2D
MM = 1 / 25.4

$fail = 0
def check(cond, msg)
  if cond
    print '.'
  else
    $fail += 1
    puts "\nFAIL: #{msg}"
  end
end

region = {
  :outer => [[0, 0], [3000 * MM, 0], [3000 * MM, 2000 * MM], [1500 * MM, 2600 * MM], [0, 2000 * MM]],
  :holes => [[[800 * MM, 800 * MM], [1200 * MM, 800 * MM], [1200 * MM, 1100 * MM], [800 * MM, 1100 * MM]]]
}

base = { :length => 600 * MM, :width => 150 * MM, :gap => 0.0, :seed => 7,
         :wood_min => 400 * MM, :wood_max => 1200 * MM, :small => 200 * MM }
configs = FS::Patterns::LIST.map { |pt| base.merge(:pattern => pt) }
configs << base.merge(:pattern => 'herringbone', :angle => 0.3, :anchor => 'center')
configs << base.merge(:pattern => 'brick', :offset => 1.0 / 3, :angle => 0.7)
configs << base.merge(:pattern => 'chevron', :chevron_angle => 0.5)
configs << base.merge(:pattern => 'basket', :basket_n => 4, :length => 400 * MM)

rng = Random.new(3)
configs.each do |cfg|
  t0 = Time.now
  res = FS::Patterns.layout(region, cfg)
  dt = Time.now - t0
  tiles = res[:tiles]
  check(!tiles.empty?, "#{cfg[:pattern]} produced tiles")
  # convexity + ccw
  tiles.each do |t|
    unless G.convex?(t.poly) && G.signed_area(t.poly) > 0
      check(false, "#{cfg[:pattern]} tile not convex/ccw")
      break
    end
  end
  bad = 0
  400.times do
    pt = [rng.rand * 3000 * MM, rng.rand * 2600 * MM]
    next unless G.point_in_region?(pt, region)
    c = tiles.count { |t| G.point_in_poly?(pt, t.poly) }
    gapok = cfg[:pattern] == 'voronoi' && c == 0
    bad += 1 unless c == 1 || gapok
  end
  check(bad <= 2, "#{cfg[:pattern]} coverage (bad samples #{bad})")
  # boundary flags sanity
  nb = tiles.count { |t| t.state == :boundary }
  puts format("\n%-12s tiles=%5d cut=%4d %.3fs", cfg[:pattern], tiles.length, nb, dt)
end

# segment clipping
idx = G::SegmentIndex.new(G.region_segments(region), 10)
segs = G.clip_segment_region([-10, 1000 * MM], [4000 * MM, 1000 * MM], region, idx)
check(segs.length == 2, "clip segment around hole -> #{segs.length}")

# offset
sq = [[0, 0], [10, 0], [10, 10], [0, 10]]
o = G.offset_convex(sq, 1.0)
check(o && (G.area(o) - 64).abs < 1e-6, 'offset convex')
o2 = G.offset_convex(sq, [1, 0, 0, 0])
check(o2 && (G.area(o2) - 90).abs < 1e-6, 'per-edge offset')
check(G.offset_convex(sq, 6).nil?, 'offset collapse')

# texture periods
%w[grid brick herringbone chevron basket hexagon].each do |pt|
  w, h, list, seamless = FS::Patterns.texture_tiles(base.merge(:pattern => pt, :gap => 3 * MM))
  check(seamless && w > 0 && h > 0 && !list.empty?, "texture period #{pt}")
end

# big area performance
big = { :outer => [[0, 0], [20_000 * MM, 0], [20_000 * MM, 20_000 * MM], [0, 20_000 * MM]], :holes => [] }
t0 = Time.now
r = FS::Patterns.layout(big, base.merge(:pattern => 'herringbone', :length => 600 * MM, :width => 100 * MM))
puts format("\nbig herringbone: %d tiles in %.2fs", r[:tiles].length, Time.now - t0)

begin
  FS::Patterns.layout(big, base.merge(:pattern => 'grid', :length => 5 * MM, :width => 5 * MM))
  check(false, 'too many tiles should raise')
rescue FS::TooManyTiles
  check(true, '')
end

puts
puts $fail.zero? ? 'ALL OK' : "#{$fail} FAILURES"
exit($fail.zero? ? 0 : 1)
