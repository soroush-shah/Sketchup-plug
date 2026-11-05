# encoding: UTF-8
# Plain-Ruby tests for the geometry core (no SketchUp needed).
#   ruby -I. tests/test_core.rb
require 'minitest/autorun'
require 'json'
base = File.expand_path('../src/banian_profile_builder/core', __dir__)
%w[vec profiles path sweep assembly presets].each { |f| require File.join(base, f) }

PB = BanianStudio::ProfileBuilder

class TestCore < Minitest::Test
  V = PB::Vec

  def test_all_profiles_generate_valid_loops
    PB::Profiles::CATALOG.each do |e|
      loops = PB::Profiles.place(e.generator.call(PB::Profiles.defaults(e.id)))
      refute_empty loops, e.id
      assert PB::Profiles.signed_area(loops[0]) > 0, "#{e.id} outer must be CCW"
      loops[1..-1].each { |l| assert PB::Profiles.signed_area(l) < 0, "#{e.id} hole must be CW" }
      assert PB::Profiles.area(loops) > 0, e.id
    end
  end

  def test_anchor_places_path_point
    spec = { 'profile' => 'rect', 'params' => { 'w' => 100, 'h' => 50 }, 'anchor' => 'bl' }
    bb = PB::Profiles.bbox(PB::Profiles.placed_loops(spec))
    assert_in_delta 0, bb[0], 1e-9
    assert_in_delta 0, bb[1], 1e-9
    assert_in_delta 100, bb[2], 1e-9
    spec['rotation'] = 90
    bb = PB::Profiles.bbox(PB::Profiles.placed_loops(spec))
    assert_in_delta 50, bb[2] - bb[0], 1e-9
  end

  # Every edge of a closed (watertight) mesh must be shared by exactly 2 faces.
  def edge_counts(mesh, extra_faces = [])
    counts = Hash.new(0)
    polys = mesh[:polygons].map { |p| p.map(&:abs) } + extra_faces
    polys.each do |p|
      p.each_with_index do |a, i|
        b = p[(i + 1) % p.size]
        counts[[a, b].sort] += 1
      end
    end
    counts
  end

  def test_closed_square_path_is_watertight_and_outward
    path = [[0, 0, 0], [100, 0, 0], [100, 100, 0], [0, 100, 0]]
    prep = PB::Sweep.prepare(path, true)
    assert_equal [0.0, 0.0, 1.0], prep[:up]
    loops = PB::Profiles.to_inches(PB::Profiles.placed_loops('profile' => 'rect', 'params' => { 'w' => 254, 'h' => 254 }))
    m = PB::Sweep.mesh(prep, loops)
    assert_equal 16, m[:vertices].size
    assert_equal 16, m[:polygons].size
    assert edge_counts(m).values.all? { |c| c == 2 }
    centroid = [50.0, 50.0, 0.0]
    m[:polygons].each do |p|
      pts = p.map { |i| m[:vertices][i.abs - 1] }
      n = V.cross(V.sub(pts[1], pts[0]), V.sub(pts[2], pts[0]))
      c = pts.inject([0, 0, 0]) { |s, q| V.add(s, q) }.map { |x| x / 4.0 }
      # Faces on the inner side of the ring point towards the centroid,
      # faces on the outer side away from it; either way the normal must
      # point away from the solid's material, checked via the tube axis.
      axis_pt = closest_on_square(c)
      assert V.dot(n, V.sub(c, axis_pt)) > 0, 'normal must point outward'
    end
  end

  def closest_on_square(c)
    x = c[0].clamp(0, 100); y = c[1].clamp(0, 100)
    d = { [x, 0] => c[1].abs, [x, 100] => (c[1] - 100).abs, [0, y] => c[0].abs, [100, y] => (c[0] - 100).abs }
    k = d.min_by { |_, v| v }[0]
    [k[0], k[1], 0.0]
  end

  def test_open_path_caps_and_mitre
    path = [[0, 0, 0], [100, 0, 0], [100, 100, 0]]
    prep = PB::Sweep.prepare(path, false)
    loops = PB::Profiles.to_inches(PB::Profiles.placed_loops('profile' => 'rect', 'params' => { 'w' => 254, 'h' => 254 }))
    m = PB::Sweep.mesh(prep, loops)
    assert_equal 2, m[:caps].size
    # mitre point at the outer corner: right side of +X travel is -Y
    ring = m[:vertices][4, 4]
    assert(ring.any? { |p| (p[0] - 105).abs < 1e-6 && (p[1] + 5).abs < 1e-6 })
    caps = m[:caps].map { |c, _| c[0].map { |q| m[:vertices].index(q) + 1 } }
    assert edge_counts(m, caps).values.all? { |c| c == 2 }
  end

  def test_tube_with_hole
    path = [[0, 0, 0], [0, 0, 100]]
    prep = PB::Sweep.prepare(path, false)
    assert_nil prep[:up]
    loops = PB::Profiles.to_inches(PB::Profiles.placed_loops('profile' => 'round_tube', 'params' => { 'd' => 100, 't' => 5 }))
    m = PB::Sweep.mesh(prep, loops)
    assert_equal 2, m[:caps][0][0].size
    soft = m[:polygons].flatten.count(&:negative?)
    assert soft > 0, 'round faces should be smoothed'
  end

  def test_collinear_points_removed
    pts = PB::PathOps.clean([[0, 0, 0], [10, 0, 0], [20, 0, 0], [20, 10, 0]], false)
    assert_equal 3, pts.size
  end

  def test_extend_and_trim
    pts = [[0, 0, 0], [100, 0, 0], [100, 50, 0]]
    e = PB::PathOps.extend_end(pts, false, 25)
    assert_in_delta 75, e[-1][1], 1e-9
    t = PB::PathOps.extend_end(pts, false, -80)
    assert_in_delta 70, PB::PathOps.length(t, false), 1e-6
    s = PB::PathOps.extend_end(pts, true, 10)
    assert_in_delta(-10, s[0][0], 1e-9)
  end

  def test_kept_ranges_closed_wraps
    k = PB::PathOps.kept_ranges(400.0, true, [[50, 100]])
    assert_equal [[100, 450]], k
    sub = PB::PathOps.subpath([[0, 0, 0], [100, 0, 0], [100, 100, 0], [0, 100, 0]], true, 100, 450)
    assert_in_delta 350, PB::PathOps.length(sub, false), 1e-6
  end

  def test_stud_wall_plan_with_door
    rows = PB::Presets.rows_for('stud_wall', {})
    spec = { 'rows' => rows, 'openings' => [{ 'at' => 1000, 'width' => 900, 'sill' => 0, 'head' => 2100, 'jambs' => true }] }
    path = [[0, 0, 0], [4000 / 25.4, 0, 0]]
    prep = PB::Sweep.prepare(path, false)
    plan = PB::Assembly.plan(prep, spec)
    bottom = plan[:layers][0]
    assert_equal 2, bottom[:paths].size, 'bottom plate is cut by the door'
    assert_equal 1, plan[:layers][1][:paths].size, 'top plate continues'
    studs = plan[:repeats][0][:items]
    in_door = studs.select { |it| it[:s] * 25.4 > 1020 && it[:s] * 25.4 < 1880 }
    assert in_door.all? { |it| it[:v0] * 25.4 >= 2099 }, 'cripples above the door only'
    q = PB::Assembly.quantities(plan)
    assert_equal 4, q.size
    assert q.all? { |e| e['length_mm'] > 0 }
  end

  def test_all_presets_plan
    path = [[0, 0, 0], [3000 / 25.4, 0, 0], [3000 / 25.4, 2000 / 25.4, 0]]
    PB::Presets::LIST.each do |e|
      prep = PB::Sweep.prepare(path, false)
      plan = PB::Assembly.plan(prep, 'rows' => PB::Presets.rows_for(e.id, {}))
      refute_empty plan[:layers] + plan[:repeats], e.id
      plan[:layers].each { |l| l[:paths].each { |p, c| refute_nil PB::Sweep.mesh({ points: p, closed: c, up: prep[:up] }, l[:loops]) } }
    end
  end

  def test_helix_keeps_no_roll
    pts = (0..40).map { |i| a = i * 0.3; [100 * Math.cos(a), 100 * Math.sin(a), i * 5.0] }
    prep = PB::Sweep.prepare(pts, false)
    frs = PB::Sweep.frames(prep[:points], false, prep[:up])
    frs.each { |_, r, _| assert_in_delta 0, r[2], 1e-9 }
  end

  def test_prism_outward
    loops = PB::Profiles.to_inches(PB::Profiles.placed_loops('profile' => 'rect', 'params' => { 'w' => 254, 'h' => 254 }))
    m = PB::Sweep.prism(loops, 10)
    m[:polygons].each do |p|
      pts = p.map { |i| m[:vertices][i.abs - 1] }
      n = V.cross(V.sub(pts[1], pts[0]), V.sub(pts[2], pts[0]))
      c = pts.inject([0, 0, 0]) { |s, q| V.add(s, q) }
      assert V.dot(n, [c[0], c[1], 0]) > 0
    end
  end

  def test_performance_long_curve
    pts = (0..2000).map { |i| a = i * 0.01; [500 * Math.cos(a), 500 * Math.sin(a), 0] }
    loops = PB::Profiles.to_inches(PB::Profiles.placed_loops('profile' => 'round_tube', 'params' => { 'd' => 48, 't' => 3 }))
    t = Time.now
    m = PB::Sweep.mesh(PB::Sweep.prepare(pts, false), loops)
    dt = Time.now - t
    assert m[:polygons].size > 50_000
    assert dt < 2.0, "sweep took #{dt}s"
  end
end
