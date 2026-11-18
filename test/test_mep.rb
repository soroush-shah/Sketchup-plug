# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'sketchup_mock'
SRC = File.expand_path('../src/mep_studio', __dir__)
module MEPStudio
  PLUGIN_DIR = SRC
end
%w[core/geo core/catalog core/settings core/util builders/run_builder builders/equipment commands/clash commands/commands].each do |f|
  require File.join(SRC, f)
end

G = MEPStudio::Geo
U = MEPStudio::Util

class TestGeo < Minitest::Test
  def test_fillet_keeps_ends_and_shortens
    pts = [[0, 0, 0], [100, 0, 0], [100, 100, 0]]
    f = G.fillet_path(pts, 20)
    assert_equal [0.0, 0.0, 0.0], f.first
    assert_equal [100.0, 100.0, 0.0], f.last
    assert f.size > 3
    assert G.path_length(f) < 200
    # arc points are at distance r from the centre (80,20)
    f[1..-2].each { |p| assert_in_delta 20.0, G.dist(p, [80, 20, 0]), 1e-6 }
  end

  def test_clean_path_removes_collinear
    assert_equal 2, G.clean_path([[0, 0, 0], [5, 0, 0], [10, 0, 0]]).size
  end

  def test_obb_overlap
    a = G.segment_obb([0, 0, 0], [100, 0, 0], 10, 10)
    b = G.segment_obb([50, -50, 0], [50, 50, 0], 10, 10)
    c = G.segment_obb([50, -50, 20], [50, 50, 20], 10, 10)
    assert G.obb_overlap?(a, b)
    refute G.obb_overlap?(a, c)
    assert G.obb_overlap?(G.obb_inflate(a, 11), c)
  end

  def test_tri_obb
    b = G.segment_obb([0, 0, 0], [100, 0, 0], 10, 10)
    assert G.tri_obb_overlap?([[50, -100, -100], [50, 100, -100], [50, 0, 100]], b)
    refute G.tri_obb_overlap?([[50, -100, 20], [50, 100, 20], [60, 0, 20]], b)
  end

  def test_seg_dist
    d, = G.seg_seg_dist([0, 0, 0], [10, 0, 0], [5, -5, 3], [5, 5, 3])
    assert_in_delta 3.0, d, 1e-9
  end

  def test_grid_counts_light_hazard
    # 10 m x 6 m room, light hazard 4.6 m / 20.9 m2
    nx, ny, dx, dy = G.grid_counts(10_000, 6000, 4600, 20.9e6)
    assert dx <= 4600 && dy <= 4600
    assert dx * dy <= 20.9e6
    assert_equal [3, 2], [nx, ny]
  end

  def test_section_axes_vertical
    w, h = G.section_axes([0, 0, 1])
    assert_in_delta 0, G.dot(w, [0, 0, 1]), 1e-9
    assert_in_delta 0, G.dot(h, [0, 0, 1]), 1e-9
  end
end

class TestCatalog < Minitest::Test
  def test_pipe_schedule
    assert_equal 25, MEPStudio::Catalog.sprinkler_pipe_dn('Light', 2)
    assert_equal 32, MEPStudio::Catalog.sprinkler_pipe_dn('Light', 3)
    assert_equal 50, MEPStudio::Catalog.sprinkler_pipe_dn('Light', 8)
    assert_equal 65, MEPStudio::Catalog.sprinkler_pipe_dn('Ordinary', 20)
    assert_equal 80, MEPStudio::Catalog.sprinkler_pipe_dn('Ordinary', 21)
  end

  def test_settings_merge
    m = MEPStudio::Settings.deep_merge({ 'a' => { 'x' => 1, 'y' => 2 } }, { 'a' => { 'y' => 5 } })
    assert_equal({ 'a' => { 'x' => 1, 'y' => 5 } }, m)
  end
end

class TestClash < Minitest::Test
  def setup
    Sketchup.reset_model!
  end

  def run_group(type, system, pts_mm, w: 0, h: 0, dia: 0, shape: 'rect', dn: 0)
    g = Sketchup::Group.new("#{type} #{system}")
    pts = pts_mm.map { |p| p.map { |c| U.mm(c) } }
    U.set_attrs(g, 'type' => type, 'system' => system, 'shape' => shape, 'width' => w, 'height' => h,
                   'diameter' => dia, 'dn' => dn, 'insulation' => 0, 'size' => 'x', 'path' => pts.flatten,
                   'centerline' => pts.flatten)
    Sketchup.active_model.entities << g
    g
  end

  def beam(x0, y0, z0, x1, y1, z1)
    g = Sketchup::Group.new('Beam')
    c = [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0], [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]]
          .map { |p| Geom::Point3d.new(*p.map { |v| U.mm(v) }) }
    [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]].each do |f|
      g.entities << Sketchup::Face.new(f.map { |i| c[i] })
    end
    Sketchup.active_model.entities << g
    g
  end

  OPTS = { 'clearance' => 25, 'check_mep' => true, 'check_arch' => true, 'only_visible' => true, 'ignore_tags' => '' }.freeze

  def test_pipe_crossing_duct_is_hard
    run_group('duct', 'SA', [[0, 0, 3000], [5000, 0, 3000]], w: 400, h: 250)
    run_group('pipe', 'CHWS', [[2000, -2000, 3000], [2000, 2000, 3000]], dia: 60.3, shape: 'round', dn: 50)
    r = MEPStudio::Clash.detect(OPTS)
    assert_equal 1, r.size
    assert r[0][:hard]
    assert_in_delta 2000, U.to_mm(r[0][:loc][0]), 300
  end

  def test_soft_clash_within_clearance
    run_group('duct', 'SA', [[0, 0, 3000], [5000, 0, 3000]], w: 400, h: 250)
    # pipe centre 125 + 30 + 15 mm above duct axis -> 15 mm gap
    run_group('pipe', 'CHWS', [[2000, -2000, 3170], [2000, 2000, 3170]], dia: 60.3, shape: 'round', dn: 50)
    r = MEPStudio::Clash.detect(OPTS)
    assert_equal 1, r.size
    refute r[0][:hard]
  end

  def test_branch_tee_same_system_ignored
    run_group('pipe', 'CHWS', [[0, 0, 3000], [5000, 0, 3000]], dia: 60.3, shape: 'round', dn: 50)
    run_group('pipe', 'CHWS', [[2000, 0, 3000], [2000, 3000, 3000]], dia: 33.7, shape: 'round', dn: 25)
    assert_empty MEPStudio::Clash.detect(OPTS)
  end

  def test_branch_of_other_system_reported
    run_group('pipe', 'CHWS', [[0, 0, 3000], [5000, 0, 3000]], dia: 60.3, shape: 'round', dn: 50)
    run_group('pipe', 'HWS', [[2000, 0, 3000], [2000, 3000, 3000]], dia: 33.7, shape: 'round', dn: 25)
    assert_equal 1, MEPStudio::Clash.detect(OPTS).size
  end

  def test_duct_through_beam
    run_group('duct', 'SA', [[0, 0, 3000], [5000, 0, 3000]], w: 400, h: 250)
    beam(2400, -3000, 2900, 2700, 3000, 3500)
    r = MEPStudio::Clash.detect(OPTS)
    assert_equal 1, r.size
    assert_equal 'Arch/Struct', r[0][:vs]
    assert r[0][:hard]
  end

  def test_duct_below_beam_clear
    run_group('duct', 'SA', [[0, 0, 2500], [5000, 0, 2500]], w: 400, h: 250)
    beam(2400, -3000, 2900, 2700, 3000, 3500)
    assert_empty MEPStudio::Clash.detect(OPTS)
  end

  def test_parallel_runs_no_clash
    run_group('pipe', 'CHWS', [[0, 0, 3000], [5000, 0, 3000]], dia: 60.3, shape: 'round', dn: 50)
    run_group('pipe', 'CHWR', [[0, 200, 3000], [5000, 200, 3000]], dia: 60.3, shape: 'round', dn: 50)
    assert_empty MEPStudio::Clash.detect(OPTS)
  end

  def test_fcu_with_duct_from_collar_ignored
    defn = Sketchup::Definition.new('FCU')
    bb = Geom::BoundingBox.new
    bb.add(Geom::Point3d.new(U.mm(-470), U.mm(-250), U.mm(-240)), Geom::Point3d.new(U.mm(470), U.mm(350), 0))
    defn.bounds = bb
    fcu = Sketchup::ComponentInstance.new('FCU')
    fcu.definition = defn
    fcu.transformation = Geom::Transformation.translation(Geom::Point3d.new(0, 0, U.mm(3000)))
    U.set_attrs(fcu, 'type' => 'fcu', 'system' => 'EQ', 'model' => 'FCU-400')
    Sketchup.active_model.entities << fcu
    run_group('duct', 'SA', [[0, 350, 2880], [0, 3000, 2880]], w: 700, h: 120)
    assert_empty MEPStudio::Clash.detect(OPTS)
  end
end

class TestChains < Minitest::Test
  V = Struct.new(:position)
  E = Struct.new(:start, :end) do
    def other_vertex(v) = v.equal?(start) ? self.end : start
  end

  def test_branched_network_splits
    pt = ->(x, y) { V.new(Geom::Point3d.new(x, y, 0)) }
    a = pt.(0, 0); b = pt.(10, 0); c = pt.(20, 0); d = pt.(10, 10); e = pt.(20, 10)
    edges = [E.new(a, b), E.new(b, c), E.new(b, d), E.new(d, e)]
    chains = MEPStudio::Commands.chains_from(edges)
    assert_equal 3, chains.size
    assert_includes chains.map(&:size), 3 # b-d-e
  end
end
