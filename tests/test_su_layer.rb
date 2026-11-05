# encoding: UTF-8
# Smoke tests of the SketchUp layer against tests/su_mock.rb.
#   ruby tests/test_su_layer.rb
require 'minitest/autorun'
require 'json'
require_relative 'su_mock'

module UI
  def self.messagebox(*a) = (@msgs ||= []) << a
  def self.start_timer(*_a) = yield
end

module BanianStudio
  module ProfileBuilder
    VERSION = 'test'
    PLUGIN_DIR = File.expand_path('../src/banian_profile_builder', __dir__)
  end
end
PB = BanianStudio::ProfileBuilder
%w[core/vec core/profiles core/path core/sweep core/assembly core/presets
   su/library su/builder su/quantities su/controller tools/draw_tool tools/extend_tool].each do |f|
  require File.join(PB::PLUGIN_DIR, f)
end

class TestSULayer < Minitest::Test
  def setup
    Sketchup.reset!
    PB::Builder.forget_cache(Sketchup.active_model)
    @m = Sketchup.active_model
  end

  def wall_path
    [[0, 0, 0], [4000.mm, 0, 0], [4000.mm, 3000.mm, 0]]
  end

  def test_member_create_and_rebuild
    spec = { 'profile' => 'i_beam', 'params' => { 'w' => 100, 'h' => 200 }, 'anchor' => 'bc', 'material' => 'BPB Metal' }
    g = PB::Builder.create(@m.active_entities, 'member', spec, wall_path, false)
    refute_nil g
    assert_equal 'member', PB::Builder.kind(g)
    assert_equal 'I-Beam (IPE) 100×200×6×9', g.name
    assert_equal 'BPB Metal', g.material.name
    info = PB::Builder.read(g)
    assert_equal [0.0, 0.0, 0.0], info['path'][0], 'path stored relative to group origin'
    qty = JSON.parse(g.get_attribute(PB::Builder::DICT, 'qty'))
    assert_in_delta 7000, qty[0]['length_mm'], 0.5
    n1 = g.entities.polygon_count
    assert PB::Builder.rebuild(g, spec.merge('params' => { 'w' => 150, 'h' => 300 }))
    assert_equal n1, g.entities.polygon_count
    assert_equal 2, g.entities.grep(Sketchup::Face).size, 'two end caps'
    new_path = PB::PathOps.extend_end(info['path'], false, 1000.mm)
    PB::Builder.rebuild(g, nil, new_path)
    qty = JSON.parse(g.get_attribute(PB::Builder::DICT, 'qty'))
    assert_in_delta 8000, qty[0]['length_mm'], 0.5
  end

  def test_assembly_shares_piece_definitions
    spec = PB::Controller.default_assembly
    g1 = PB::Builder.create(@m.active_entities, 'assembly', spec, wall_path, false)
    g2 = PB::Builder.create(@m.active_entities, 'assembly', spec, [[0, 5000.mm, 0], [3000.mm, 5000.mm, 0]], false)
    pieces = @m.definitions.select { |d| d.get_attribute(PB::Builder::DICT, 'piece') }
    assert_equal 1, pieces.size, 'all studs of all walls share one definition'
    studs = g1.entities.grep(Sketchup::ComponentInstance).size + g2.entities.grep(Sketchup::ComponentInstance).size
    assert studs > 20
    assert_equal pieces[0].count_instances, studs
    # door: stud pieces of new lengths, old definition still used by g2
    spec2 = spec.merge('openings' => [{ 'at' => 1000, 'width' => 900, 'sill' => 0, 'head' => 2100, 'jambs' => true }])
    PB::Builder.rebuild(g1, spec2)
    assert @m.definitions.count { |d| d.get_attribute(PB::Builder::DICT, 'piece') } >= 2
    # removing the opening again purges the cripple definition
    PB::Builder.rebuild(g1, spec)
    left = @m.definitions.select { |d| d.get_attribute(PB::Builder::DICT, 'piece') }
    assert_equal 1, left.size
  end

  def test_quantities_report
    PB::Builder.create(@m.active_entities, 'assembly', PB::Controller.default_assembly, wall_path, false)
    PB::Builder.create(@m.active_entities, 'member', { 'profile' => 'rect', 'params' => { 'w' => 50, 'h' => 50 } }, wall_path, false)
    rows = PB::Quantities.report(@m)
    assert(rows.any? { |r| r['name'] == 'Stud' && r['count'] > 10 })
    assert(rows.any? { |r| r['type'] == 'member' && (r['length_mm'] - 7000).abs < 1 })
    csv = PB::Quantities.to_csv(rows.map { |r| [r['name'], r['size']] }, %w[Name Size])
    assert csv.start_with?("﻿")
  end

  def test_chains_split_and_close
    v = ->(x, y) { Sketchup::Vertex.new(Geom::Point3d.new(x, y, 0)) }
    a, b, c, d = v.(0, 0), v.(10, 0), v.(10, 10), v.(0, 10)
    square = [Sketchup::Edge.new(a, b), Sketchup::Edge.new(b, c), Sketchup::Edge.new(c, d), Sketchup::Edge.new(d, a)]
    e, f, g = v.(50, 0), v.(60, 0), v.(70, 5)
    open = [Sketchup::Edge.new(e, f), Sketchup::Edge.new(f, g)]
    res = PB::Controller.chains(square + open)
    assert_equal 2, res.size
    closed = res.find { |_, cl| cl }
    opened = res.find { |_, cl| !cl }
    assert_equal 4, closed[0].size
    assert_equal 3, opened[0].size
  end

  def test_preview_payloads
    p = PB::Controller.preview('assembly', PB::Controller.default_assembly)
    assert_equal 4, p['parts'].size
    m = PB::Controller.preview('member', 'profile' => 'angle', 'params' => {})
    refute_empty m['parts'][0]['loops']
  end

  def test_every_preset_builds
    PB::Presets::LIST.each do |e|
      spec = { 'preset' => e.id, 'rows' => PB::Presets.rows_for(e.id, {}), 'openings' => [] }
      g = PB::Builder.create(@m.active_entities, 'assembly', spec, wall_path, false)
      refute_nil g, e.id
      assert g.entities.list.size > 1, e.id
    end
  end
end

class TestChunking < Minitest::Test
  def test_long_curve_is_chunked_but_complete
    Sketchup.reset!
    m = Sketchup.active_model
    pts = (0..1500).map { |i| a = i * 0.004; [5000.mm * Math.cos(a), 5000.mm * Math.sin(a), 0] }
    g = PB::Builder.create(m.active_entities, 'member', { 'profile' => 'round_tube', 'params' => { 'd' => 48, 't' => 3 } }, pts, false)
    meshes = g.entities.meshes
    assert meshes.size > 1
    assert_equal 1500 * 48, meshes.sum { |mm| mm.polygons.size }
    assert meshes.all? { |mm| mm.points.size <= 2 * PB::Builder::CHUNK + 64 }
  end
end
