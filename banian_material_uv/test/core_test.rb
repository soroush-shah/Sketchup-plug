# Run: ruby -I banian_material_uv/src banian_material_uv/test/core_test.rb
require 'minitest/autorun'
require 'banian_material_uv/core'

C = BanianStudio::MaterialUV::Core
V = C::V

module Shapes
  module_function

  # lat-long sphere: quads + pole triangles, soft edges like SketchUp Follow Me
  def sphere(r = 50.0, seg = 24, rings = 12, center = [0, 0, 0])
    m = C::Mesh.new
    id = 0
    grid = {}
    top = (id += 1); m.add_vertex(top, V.add(center, [0, 0, r]))
    bot = (id += 1); m.add_vertex(bot, V.add(center, [0, 0, -r]))
    (1...rings).each do |j|
      lat = Math::PI / 2 - Math::PI * j / rings
      seg.times do |i|
        lon = 2 * Math::PI * i / seg
        grid[[i, j]] = (id += 1)
        m.add_vertex(id, V.add(center, [r * Math.cos(lat) * Math.cos(lon), r * Math.cos(lat) * Math.sin(lon), r * Math.sin(lat)]))
      end
    end
    seg.times do |i|
      i2 = (i + 1) % seg
      m.add_face([top, grid[[i, 1]], grid[[i2, 1]]])
      (1...rings - 1).each do |j|
        m.add_face([grid[[i, j]], grid[[i, j + 1]], grid[[i2, j + 1]], grid[[i2, j]]])
      end
      m.add_face([bot, grid[[i2, rings - 1]], grid[[i, rings - 1]]])
    end
    m.edges.each_value { |e| e.soft = true }
    m
  end

  def cylinder(r = 30.0, h = 100.0, seg = 24, caps = true, axis_x = false)
    m = C::Mesh.new
    pt = lambda { |x, y, z| axis_x ? [z, x, y] : [x, y, z] }
    seg.times do |i|
      a = 2 * Math::PI * i / seg
      m.add_vertex(i, pt.call(r * Math.cos(a), r * Math.sin(a), 0))
      m.add_vertex(i + seg, pt.call(r * Math.cos(a), r * Math.sin(a), h))
    end
    seg.times do |i|
      i2 = (i + 1) % seg
      m.add_face([i, i2, i2 + seg, i + seg])
    end
    if caps
      m.add_face((0...seg).to_a.reverse)
      m.add_face((seg...2 * seg).to_a)
    end
    m.edges.each_value { |e| e.soft = e.faces.size == 2 && e.key.all? { true } }
    # hard rim edges (between side and cap)
    m.edges.each_value do |e|
      e.soft = e.faces.all? { |f| m.faces[f].verts.size == 4 }
    end
    m
  end

  def cone(r = 40.0, h = 80.0, seg = 24, rows = 4)
    m = C::Mesh.new
    id = 0; g = {}
    (0..rows).each do |j|
      rr = r * (1.0 - j.to_f / (rows + 1))
      seg.times do |i|
        a = 2 * Math::PI * i / seg
        g[[i, j]] = (id += 1)
        m.add_vertex(id, [rr * Math.cos(a), rr * Math.sin(a), h * j.to_f / (rows + 1)])
      end
    end
    seg.times do |i|
      i2 = (i + 1) % seg
      rows.times { |j| m.add_face([g[[i, j]], g[[i2, j]], g[[i2, j + 1]], g[[i, j + 1]]]) }
    end
    m.edges.each_value { |e| e.soft = true }
    m
  end

  def torus(rr = 60.0, r = 15.0, s1 = 24, s2 = 12)
    m = C::Mesh.new
    id = 0; g = {}
    s1.times do |i|
      a = 2 * Math::PI * i / s1
      s2.times do |j|
        b = 2 * Math::PI * j / s2
        g[[i, j]] = (id += 1)
        m.add_vertex(id, [(rr + r * Math.cos(b)) * Math.cos(a), (rr + r * Math.cos(b)) * Math.sin(a), r * Math.sin(b)])
      end
    end
    s1.times do |i|
      s2.times do |j|
        i2 = (i + 1) % s1; j2 = (j + 1) % s2
        m.add_face([g[[i, j]], g[[i2, j]], g[[i2, j2]], g[[i, j2]]])
      end
    end
    m.edges.each_value { |e| e.soft = true }
    m
  end

  # triangulated torus (diagonals soft) to test triangle pairing
  def torus_tri(rr = 60.0, r = 15.0, s1 = 24, s2 = 12)
    m = C::Mesh.new
    id = 0; g = {}
    s1.times do |i|
      a = 2 * Math::PI * i / s1
      s2.times do |j|
        b = 2 * Math::PI * j / s2
        g[[i, j]] = (id += 1)
        m.add_vertex(id, [(rr + r * Math.cos(b)) * Math.cos(a), (rr + r * Math.cos(b)) * Math.sin(a), r * Math.sin(b)])
      end
    end
    s1.times do |i|
      s2.times do |j|
        i2 = (i + 1) % s1; j2 = (j + 1) % s2
        m.add_face([g[[i, j]], g[[i2, j]], g[[i2, j2]]])
        m.add_face([g[[i, j]], g[[i2, j2]], g[[i, j2]]])
      end
    end
    m.edges.each_value { |e| e.soft = true }
    m
  end

  def box(sz = 50.0)
    m = C::Mesh.new
    pts = [[0,0,0],[sz,0,0],[sz,sz,0],[0,sz,0],[0,0,sz],[sz,0,sz],[sz,sz,sz],[0,sz,sz]]
    pts.each_with_index { |p, i| m.add_vertex(i, p) }
    [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each { |f| m.add_face(f) }
    m
  end
end

class CoreTest < Minitest::Test
  def all(m) (0...m.faces.size).to_a end

  def test_eigen
    r = C::LA.eigen_sym3([[2, 1, 0], [1, 2, 0], [0, 0, 5]])
    vals = r.map { |x| x[0].round(6) }
    assert_equal [1.0, 3.0, 5.0], vals
  end

  def test_sphere_fit
    m = Shapes.sphere(50, 24, 12, [10, 20, 30])
    c, r, err = C.fit_sphere(m.pos.values)
    assert_in_delta 50.0, r, 1e-6
    assert_in_delta 10.0, c[0], 1e-6
    assert err < 1e-6
  end

  def test_auto_detect
    assert_equal 'spherical', C.analyze(Shapes.sphere, all(Shapes.sphere))[:mode]
    cy = Shapes.cylinder
    info = C.analyze(cy, all(cy))
    assert_equal 'cylindrical', info[:mode]
    assert_in_delta 30.0, info[:radius], 1e-6
    assert_in_delta 1.0, info[:axis][2].abs, 1e-6
    cx = Shapes.cylinder(30, 100, 24, true, true)
    ix = C.analyze(cx, all(cx))
    assert_equal 'cylindrical', ix[:mode]
    assert_in_delta 1.0, ix[:axis][0].abs, 1e-6
    co = Shapes.cone
    assert_equal 'natural', C.analyze(co, all(co))[:mode]
    to = Shapes.torus
    assert_equal 'quad', C.analyze(to, all(to))[:mode]
    bx = Shapes.box
    refute_equal 'spherical', C.analyze(bx, all(bx))[:mode]
  end

  # every face must yield valid position_material pairs, finite uv
  def check_pairs(m, maps)
    m.faces.each do |f|
      assert maps[f.id], "face #{f.id} not mapped"
      pairs = C.face_pairs(m, f.id, maps[f.id], true)
      assert pairs, "face #{f.id} no pairs"
      assert pairs.size >= 3 && pairs.size <= 4
      pairs.each { |_v, uv| assert uv.all? { |x| x.finite? } }
    end
  end

  # texture should not be stretched: length in uv ~ length in 3D
  def assert_isometric(m, maps, tol)
    m.faces.each do |f|
      vs = f.verts
      vs.each_with_index do |a, i|
        b = vs[(i + 1) % vs.size]
        l3 = V.dist(m.pos[a], m.pos[b])
        ua = maps[f.id][a]; ub = maps[f.id][b]
        l2 = Math.sqrt((ua[0] - ub[0])**2 + (ua[1] - ub[1])**2)
        assert_in_delta l3, l2, l3 * tol + 1e-6, "face #{f.id} edge distorted"
      end
    end
  end

  def test_cylindrical_mapping
    m = Shapes.cylinder
    res = C.compute(m, all(m), :mode => 'auto', :size_mode => 'real')
    check_pairs(m, res[:maps])
    # side faces: uv width ~ arc length (2*pi*r/seg), height = 100
    side = m.faces.find { |f| f.verts.size == 4 }
    us = side.verts.map { |v| res[:maps][side.id][v][0] }
    assert_in_delta 2 * Math::PI * 30 / 24, us.max - us.min, 1e-6
    # fit mode: full revolution => u in [0,1]
    fit = C.compute(m, all(m), :mode => 'cylindrical', :size_mode => 'fit', :repeat_u => 1, :repeat_v => 1)
    allu = []
    m.faces.each { |f| next unless f.verts.size == 4; f.verts.each { |v| allu << fit[:maps][f.id][v][0] } }
    assert_in_delta 1.0, allu.max - allu.min, 0.06
  end

  def test_seam_continuity_cylinder
    m = Shapes.cylinder(30, 100, 24, false)
    res = C.compute(m, all(m), :mode => 'cylindrical', :size_mode => 'real')
    m.faces.each do |f|
      us = f.verts.map { |v| res[:maps][f.id][v][0] }
      assert (us.max - us.min) < 2 * Math::PI * 30 / 24 + 1e-6, 'seam face wrapped badly'
    end
  end

  def test_spherical
    m = Shapes.sphere
    res = C.compute(m, all(m), :mode => 'spherical', :size_mode => 'fit', :repeat_u => 1, :repeat_v => 1)
    check_pairs(m, res[:maps])
    vals = res[:maps].values.map { |h| h.values }.flatten(1)
    assert vals.map { |x| x[1] }.min >= -1e-9
    assert vals.map { |x| x[1] }.max <= 1 + 1e-9
    # no face spans more than a few segments in u (pole/seam handling)
    m.faces.each do |f|
      us = f.verts.map { |v| res[:maps][f.id][v][0] }
      assert (us.max - us.min) < 2.0 / 24 + 1e-6, "face #{f.id} wraps"
    end
  end

  def test_natural_cone_is_isometric
    m = Shapes.cone
    res = C.compute(m, all(m), :mode => 'natural', :size_mode => 'real')
    check_pairs(m, res[:maps])
    assert_isometric(m, res[:maps], 1e-6)
  end

  def test_natural_box
    m = Shapes.box
    res = C.compute(m, all(m), :mode => 'natural', :size_mode => 'real')
    check_pairs(m, res[:maps])
    assert_isometric(m, res[:maps], 1e-6)
  end

  def test_natural_reversed_face
    m = C::Mesh.new
    [[0,0,0],[10,0,0],[10,10,0],[0,10,0],[20,0,0],[20,10,0]].each_with_index { |p, i| m.add_vertex(i, p) }
    m.add_face([0, 1, 2, 3])
    m.add_face([1, 2, 5, 4]) # reversed (normal -Z)
    res = C.compute(m, [0, 1], :mode => 'natural', :size_mode => 'real')
    # coplanar -> uv must equal planar projection (continuous)
    u0 = res[:maps][0]; u1 = res[:maps][1]
    assert_in_delta u0[1][0], u1[1][0], 1e-9
    assert_in_delta u0[2][1], u1[2][1], 1e-9
    assert_in_delta 20.0, (u1[4][0] - u0[0][0]).abs, 1e-9
  end

  def test_quad_torus
    [Shapes.torus, Shapes.torus_tri].each do |m|
      res = C.compute(m, all(m), :mode => 'quad', :size_mode => 'fit', :repeat_u => 1, :repeat_v => 1)
      check_pairs(m, res[:maps])
    end
    bt = C.build_cells(Shapes.torus_tri, all(Shapes.torus_tri))
    assert_equal 24 * 12, bt[:cells].size
  end

  def test_quad_sphere_with_poles
    m = Shapes.sphere
    res = C.compute(m, all(m), :mode => 'quad', :size_mode => 'real')
    check_pairs(m, res[:maps])
  end

  def test_box_and_planar
    m = Shapes.box
    res = C.compute(m, all(m), :mode => 'box', :size_mode => 'real')
    check_pairs(m, res[:maps])
    assert_isometric(m, res[:maps], 1e-9)
    res = C.compute(m, all(m), :mode => 'planar', :planar_dir => [0, -1, 0], :size_mode => 'real')
    check_pairs(m, res[:maps])
  end

  def test_multi_island
    m = C::Mesh.new
    s1 = Shapes.sphere(10, 12, 6, [0, 0, 0])
    s2 = Shapes.sphere(20, 12, 6, [100, 0, 0])
    [[s1, 0], [s2, 1000]].each do |s, off|
      s.pos.each { |k, p| m.add_vertex(k + off, p) }
      s.faces.each { |f| m.add_face(f.verts.map { |v| v + off }) }
    end
    m.edges.each_value { |e| e.soft = true }
    res = C.compute(m, all(m), :mode => 'auto', :size_mode => 'real')
    assert_equal 2, res[:islands].size
    assert(res[:islands].all? { |i| i[:mode] == 'spherical' })
    assert_in_delta 20.0, res[:islands][1][:radius], 1e-6
  end

  def test_face_pairs_ngon
    m = C::Mesh.new
    6.times { |i| a = Math::PI * 2 * i / 6; m.add_vertex(i, [10 * Math.cos(a), 10 * Math.sin(a), 0]) }
    m.add_face((0..5).to_a)
    res = C.compute(m, [0], :mode => 'planar', :size_mode => 'real')
    pairs = C.face_pairs(m, 0, res[:maps][0])
    assert_equal 3, pairs.size
  end

  def test_transform
    t = { :scale_u => 2.0, :scale_v => 1.0, :rot => Math::PI / 2, :off_u => 0.5, :off_v => 0, :flip_u => false, :flip_v => false }
    r = C.transform_uv([2.0, 0.0], t)
    assert_in_delta 0.5, r[0], 1e-9
    assert_in_delta 1.0, r[1], 1e-9
  end
end

class OrientationTest < Minitest::Test
  # texture must read correctly (not mirrored) when seen from the front side
  def test_not_mirrored
    [[Shapes.cylinder, 'cylindrical'], [Shapes.sphere, 'spherical'], [Shapes.box, 'box'],
     [Shapes.box, 'natural'], [Shapes.cone, 'natural'], [Shapes.torus, 'quad']].each do |m, mode|
      res = C.compute(m, (0...m.faces.size).to_a, :mode => mode, :size_mode => 'real')
      m.faces.each do |f|
        assert_equal 1, C.handedness(m, f.id, res[:maps][f.id]), "#{mode} face #{f.id} mirrored"
      end
    end
  end
end
