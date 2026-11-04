# frozen_string_literal: true

# Offline tests for the Banian Stretch core. Run with:
#   ruby banian_stretch/tests/test_core.rb

require 'minitest/autorun'
require_relative 'mock_sketchup'

SRC = File.expand_path('../src/banian_stretch', __dir__)
%w[settings region plan applier].each { |f| require File.join(SRC, f) }

class CoreTest < Minitest::Test
  include Banian::Stretch

  ALL = { instances: true, faces: true, edges: true, vertices: true }.freeze
  RIGHT = Geom::Vector3d.new(10, 0, 0)

  def setup
    @model = Sketchup::Model.new
    @ents = @model.active_entities
  end

  # Box region covering x in [lo, hi], everything in y/z.
  def slab(lo, hi)
    BoxRegion.new(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0),
                  Geom::Vector3d.new(0, 0, 1), [lo, -1000, -1000], [hi, 1000, 1000])
  end

  def stretch(region, vector = RIGHT, filters: ALL, make_unique: false)
    plan = Plan.new(@model).apply_region(region, filters, :add)
    applier = Applier.new(@model, plan, vector, make_unique: make_unique)
    applier.run
    applier
  end

  def component(&block)
    defn = Sketchup::ComponentDefinition.new
    block.call(defn.entities)
    defn
  end

  def place(entities, defn, tr = Geom::Transformation.new, klass = Sketchup::ComponentInstance)
    entities.add(klass.new(defn, tr))
  end

  def test_loose_geometry_right_half_moves
    MockBuild.box(@ents, [0, 0, 0], [100, 50, 50])
    stretch(slab(60, 200))
    assert_equal [0.0, 110.0], MockBuild.xs(@ents)
    assert_equal [[:start, 'Banian Stretch'], [:commit]], @model.operations
  end

  def test_instance_fully_inside_is_moved_not_edited
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [10, 10, 10]) }
    inst = place(@ents, defn, Geom::Transformation.translation(Geom::Vector3d.new(80, 0, 0)))
    stretch(slab(60, 200))
    assert_in_delta 90.0, inst.transformation.to_a[12]
    assert_equal [0.0, 10.0], MockBuild.xs(defn.entities)
  end

  def test_instance_filter_off_leaves_inside_instance
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [10, 10, 10]) }
    inst = place(@ents, defn, Geom::Transformation.translation(Geom::Vector3d.new(80, 0, 0)))
    plan = Plan.new(@model).apply_region(slab(60, 200), ALL.merge(instances: false), :add)
    assert plan.empty?
    assert_in_delta 80.0, inst.transformation.to_a[12]
  end

  def test_partial_unique_group_is_stretched_inside
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [100, 10, 10]) }
    grp = place(@ents, defn, Geom::Transformation.new, Sketchup::Group)
    stretch(slab(60, 200))
    assert_same defn, grp.definition
    assert_equal [0.0, 110.0], MockBuild.xs(defn.entities)
  end

  def test_copied_group_is_made_unique_automatically
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [100, 10, 10]) }
    grp = place(@ents, defn, Geom::Transformation.new, Sketchup::Group)
    other = place(@ents, defn, Geom::Transformation.translation(Geom::Vector3d.new(0, 500, 0)), Sketchup::Group)
    region = BoxRegion.new(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0),
                           Geom::Vector3d.new(0, 0, 1), [60, -5, -5], [200, 20, 20])
    stretch(region, make_unique: false)
    refute_same defn, grp.definition
    assert_equal [0.0, 110.0], MockBuild.xs(grp.definition.entities)
    assert_equal [0.0, 100.0], MockBuild.xs(other.definition.entities)
  end

  def test_shared_component_without_make_unique_edits_definition_once
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [100, 10, 10]) }
    a = place(@ents, defn)
    b = place(@ents, defn, Geom::Transformation.translation(Geom::Vector3d.new(0, 50, 0)))
    plan = Plan.new(@model).apply_region(slab(60, 200), ALL, :add)
    assert plan.shared?
    Applier.new(@model, plan, RIGHT, make_unique: false).run
    assert_same defn, a.definition
    assert_same defn, b.definition
    assert_equal [0.0, 110.0], MockBuild.xs(defn.entities) # not 120: applied once
  end

  def test_shared_component_with_make_unique
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [100, 10, 10]) }
    a = place(@ents, defn)
    b = place(@ents, defn, Geom::Transformation.translation(Geom::Vector3d.new(0, 500, 0)))
    region = BoxRegion.new(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0),
                           Geom::Vector3d.new(0, 0, 1), [60, -5, -5], [200, 20, 20])
    applier = stretch(region, make_unique: true)
    assert_equal 1, applier.made_unique
    refute_same defn, a.definition
    assert_same defn, b.definition
    assert_equal [0.0, 110.0], MockBuild.xs(a.definition.entities)
    assert_equal [0.0, 100.0], MockBuild.xs(defn.entities)
  end

  def test_make_unique_on_both_affected_copies_creates_one_copy
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [100, 10, 10]) }
    a = place(@ents, defn)
    b = place(@ents, defn, Geom::Transformation.translation(Geom::Vector3d.new(0, 50, 0)))
    applier = stretch(slab(60, 200), make_unique: true)
    assert_equal 1, applier.made_unique # the last copy is already unique
    assert_equal [0.0, 110.0], MockBuild.xs(a.definition.entities)
    assert_equal [0.0, 110.0], MockBuild.xs(b.definition.entities)
  end

  def test_rotated_instance_uses_local_vector
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [10, 100, 10]) }
    # Rotated -90 deg about Z: local +Y points to world +X.
    inst = place(@ents, defn, Geom::Transformation.rotation_z(-90))
    stretch(slab(60, 200))
    ys = defn.entities.to_a.grep(Sketchup::Edge).flat_map(&:vertices).uniq.map { |v| v.position.y.round(6) }.uniq.sort
    assert_equal [0.0, 110.0], ys
    assert_in_delta 0.0, inst.transformation.to_a[12]
  end

  def test_scaled_instance_uses_local_vector
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [50, 10, 10]) }
    place(@ents, defn, Geom::Transformation.scaling(2, 1, 1)) # world length 100
    stretch(slab(60, 200))
    assert_equal [0.0, 55.0], MockBuild.xs(defn.entities) # local 5 = world 10
  end

  def test_nested_shared_paths_with_make_unique
    # Leaf component (shared) inside a group that is copied twice.
    leaf = component { |e| MockBuild.box(e, [0, 0, 0], [100, 10, 10]) }
    outer = component { |e| place(e, leaf) }
    g1 = place(@ents, outer, Geom::Transformation.new, Sketchup::Group)
    g2 = place(@ents, outer, Geom::Transformation.translation(Geom::Vector3d.new(0, 500, 0)), Sketchup::Group)
    region = BoxRegion.new(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0),
                           Geom::Vector3d.new(0, 0, 1), [60, -5, -5], [200, 20, 20])
    stretch(region, make_unique: true)

    leaf1 = g1.definition.entities.to_a.first
    leaf2 = g2.definition.entities.to_a.first
    refute_same outer, g1.definition
    refute_same leaf, leaf1.definition
    assert_equal [0.0, 110.0], MockBuild.xs(leaf1.definition.entities)
    assert_same leaf, leaf2.definition
    assert_equal [0.0, 100.0], MockBuild.xs(leaf.entities)
  end

  def test_edge_filter_requires_both_ends_inside
    MockBuild.box(@ents, [0, 0, 0], [100, 50, 50])
    plan = Plan.new(@model).apply_region(slab(60, 200), ALL.merge(vertices: false, faces: false), :add)
    assert_equal 4, plan.vertex_count # the 4 right-side vertices, via the right-side edges
    plan = Plan.new(@model).apply_region(slab(-1, 50), { instances: true, faces: false, edges: true, vertices: false }, :add)
    assert_equal 4, plan.vertex_count
  end

  def test_face_filter_only
    MockBuild.box(@ents, [0, 0, 0], [100, 50, 50])
    region = BoxRegion.new(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0),
                           Geom::Vector3d.new(0, 0, 1), [60, -1, -1], [200, 60, 60])
    only_faces = { instances: true, faces: true, edges: false, vertices: false }
    assert_equal 4, Plan.new(@model).apply_region(region, only_faces, :add).vertex_count
    thin = BoxRegion.new(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0),
                         Geom::Vector3d.new(0, 0, 1), [60, -1, -1], [200, 60, 20])
    assert Plan.new(@model).apply_region(thin, only_faces, :add).empty?
  end

  def test_remove_mode
    MockBuild.box(@ents, [0, 0, 0], [100, 50, 50])
    plan = Plan.new(@model).apply_region(slab(-1, 200), ALL, :add)
    assert_equal 8, plan.vertex_count
    plan.apply_region(slab(-1, 50), ALL, :remove)
    assert_equal 4, plan.vertex_count
  end

  def test_pick_add_and_remove_inside_nested_instance
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [100, 10, 10]) }
    grp = place(@ents, defn, Geom::Transformation.new, Sketchup::Group)
    face = defn.entities.to_a.grep(Sketchup::Face).last # x = 100 face
    plan = Plan.new(@model).apply_pick([grp], face, :add)
    assert_equal 4, plan.vertex_count
    Applier.new(@model, plan, RIGHT).run
    assert_equal [0.0, 110.0], MockBuild.xs(defn.entities)
    plan = Plan.new(@model).apply_pick([grp], face, :add).apply_pick([grp], face, :remove)
    assert plan.empty?
  end

  def test_locked_and_hidden_instances_are_skipped
    defn = component { |e| MockBuild.box(e, [0, 0, 0], [10, 10, 10]) }
    a = place(@ents, defn, Geom::Transformation.translation(Geom::Vector3d.new(80, 0, 0)))
    a.locked = true
    b = place(@ents, defn, Geom::Transformation.translation(Geom::Vector3d.new(90, 0, 0)))
    b.hidden = true
    assert Plan.new(@model).apply_region(slab(60, 200), ALL, :add).empty?
  end

  def test_edit_context_transform
    # User is editing a group placed at x = 1000; region is in world space.
    @model.edit_transform = Geom::Transformation.translation(Geom::Vector3d.new(1000, 0, 0))
    MockBuild.box(@ents, [0, 0, 0], [100, 50, 50])
    stretch(slab(1060, 1200))
    assert_equal [0.0, 110.0], MockBuild.xs(@ents)
  end

  def test_region_classification
    r = slab(0, 10)
    inside = [Geom::Point3d.new(1, 0, 0), Geom::Point3d.new(9, 5, 5)]
    outside = [Geom::Point3d.new(20, 0, 0), Geom::Point3d.new(30, 5, 5)]
    partial = [Geom::Point3d.new(5, 0, 0), Geom::Point3d.new(15, 5, 5)]
    spanning = [Geom::Point3d.new(-5, 0, 0), Geom::Point3d.new(15, 5, 5)]
    assert_equal :inside, r.classify(inside)
    assert_equal :outside, r.classify(outside)
    assert_equal :partial, r.classify(partial)
    assert_equal :partial, r.classify(spanning)
  end

  def test_box_region_corners_round_trip
    r = BoxRegion.new(Geom::Point3d.new(5, 5, 0), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(-1, 0, 0),
                      Geom::Vector3d.new(0, 0, 1), [0, 0, -2], [10, 4, 2])
    r.corners.each { |c| assert r.contains?(c) }
    assert_equal 8, r.corners.size
  end

  def test_polygon_normal
    pts = [[0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0]].map { |p| Geom::Point3d.new(*p) }
    n = Geometry.polygon_normal(pts)
    assert_in_delta 1.0, n.z
  end

  def test_preview_marks_moving_endpoints
    MockBuild.box(@ents, [0, 0, 0], [100, 50, 50])
    plan = Plan.new(@model).apply_region(slab(60, 200), ALL, :add)
    preview = Preview.new(plan)
    assert_equal 4, preview.markers.size
    stretched = preview.segments.count { |s| s.a_moves != s.b_moves }
    assert_equal 4, stretched
  end
end
