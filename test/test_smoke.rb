# frozen_string_literal: true

# Exercises builders / layout code paths against a permissive SketchUp stub
# (catches NoMethodError, typos and wrong arity in MEP Studio's own code).
require 'minitest/autorun'
require_relative 'sketchup_mock'

ORIGIN = Geom::Point3d.new(0, 0, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)

module Sketchup
  class Color
    def initialize(*a) = @a = a
  end

  class Material
    attr_accessor :color, :alpha, :name
  end

  class Materials < Hash
    def add(n) = (self[n] = Material.new.tap { |m| m.name = n })
  end

  class Layers < Hash
    def add(n) = (self[n] = Layer.new(n))
  end

  class Edge < Entity
    include Attr
    attr_accessor :soft, :smooth
    def faces = []
  end

  class Face
    attr_writer :material
    def normal = Geom::Vector3d.new(0, 0, 1)
    def pushpull(_d) = nil
    def followme(edges) = !edges.empty?
    def bounds = Geom::BoundingBox.new.add(@pts)
    def vertices = @pts.map { |p| Struct.new(:position).new(p) }
    def edges = @pts.each_with_index.map { |p, i| Struct.new(:start, :end).new(Struct.new(:position).new(p), Struct.new(:position).new(@pts[(i + 1) % @pts.size])) }
    def classify_point(_p) = PointInside
    PointInside = 1
    PointOnEdge = 2
    PointOnVertex = 0
  end

  class Entities
    def add_group = (g = Group.new; self << g; g)
    def add_edges(pts) = pts.each_cons(2).map { Edge.new }
    def add_circle(*_a) = Array.new(16) { Edge.new }
    def add_face(*a) = (f = Face.new(a.flatten.grep(Geom::Point3d)); self << f; f)
    def add_instance(defn, tr) = (i = ComponentInstance.new; i.definition = defn; i.transformation = tr; self << i; i)
    def add_text(*_a) = nil
    def erase_entities(_e) = nil
    def grep(k) = select { |e| e.is_a?(k) }
  end

  class Group
    attr_accessor :material
    def parent = Sketchup.active_model
    def erase! = Sketchup.active_model.entities.delete(self)
  end

  class Definition
    attr_accessor :description
    def bounds = Geom::BoundingBox.new.add(Geom::Point3d.new(-10, -10, -10), Geom::Point3d.new(10, 10, 0))
  end

  class Definitions < Array
    def add(n) = (d = Definition.new(n); self << d; d)
  end

  class Model
    def materials = (@materials ||= Materials.new)
    def layers = (@layers ||= Layers.new)
    def definitions = (@defs ||= Definitions.new)
    def active_entities = entities
    def edit_transform = Geom::Transformation.new
    def start_operation(*) = nil
    def commit_operation = nil
    def abort_operation = nil
    def selection = (@sel ||= [])
  end

  class InputPoint
    def initialize(*) = nil
    def valid? = false
  end
  def self.set_status_text(*) = nil
  def self.read_default(*) = nil
  def self.write_default(*) = nil
end

module UI
  def self.messagebox(m, *_a) = (puts(m) if m.include?("error"); ($msgs ||= []) << m)
  def self.inputbox(_p, defaults, _l, _t) = ($inputs || defaults)
end

SB_VCB_LABEL = 1
SB_VCB_VALUE = 2
SRC = File.expand_path('../src/mep_studio', __dir__)
module MEPStudio
  PLUGIN_DIR = SRC
end
%w[core/geo core/catalog core/settings core/util builders/run_builder builders/equipment commands/layout commands/clash commands/commands tools/path_tool tools/place_tool].each do |f|
  require File.join(SRC, f)
end

class TestSmoke < Minitest::Test
  U = MEPStudio::Util

  def setup
    Sketchup.reset_model!
    $msgs = []
  end

  def test_duct_and_pipe_build
    ents = Sketchup.active_model.entities
    pts = [[0, 0, 100], [100, 0, 100], [100, 100, 100], [100, 100, 150]]
    d = MEPStudio::RunBuilder.build(ents, pts, 'kind' => 'duct', 'shape' => 'rect', 'system' => 'SA', 'width' => 400,
                                               'height' => 250, 'elbow_radius' => 1.0, 'insulation' => 25, 'show_insulation' => true)
    assert_equal 'duct', d.get_attribute('MEPStudio', 'type')
    assert_equal '400x250', d.get_attribute('MEPStudio', 'size')
    p = MEPStudio::RunBuilder.build(ents, pts, 'kind' => 'pipe', 'system' => 'CHWS', 'dn' => 50, 'elbow_radius' => 1.5)
    assert_in_delta 60.3, p.get_attribute('MEPStudio', 'diameter'), 0.01
    t = MEPStudio::RunBuilder.build(ents, pts, 'kind' => 'tray', 'system' => 'TRAY', 'width' => 300, 'height' => 100)
    assert_equal 'tray', t.get_attribute('MEPStudio', 'shape')
    r = MEPStudio::RunBuilder.rebuild(d, 'width' => 600)
    assert_equal '600x250', r.get_attribute('MEPStudio', 'size')
  end

  def test_all_equipment_definitions
    MEPStudio::Catalog::FCU.each_key do |k|
      d = MEPStudio::Equipment.fcu_definition(k, 'Left')
      cons = MEPStudio::Equipment.connectors(d)
      assert cons.any? { |c| c['system'] == 'CHWS' }, k
    end
    MEPStudio::Catalog::TERMINALS.each_key { |k| refute_empty MEPStudio::Equipment.connectors(MEPStudio::Equipment.terminal_definition(k)) }
    MEPStudio::Catalog::LIGHTS.each_key { |k| MEPStudio::Equipment.light_definition(k) }
    %w[Pendent Upright Sidewall].each { |h| MEPStudio::Equipment.sprinkler_definition(h, 80) }
    inst = Sketchup::ComponentInstance.new
    inst.definition = MEPStudio::Equipment.fcu_definition('FCU-400 Ducted')
    wc = MEPStudio::Equipment.world_connectors(inst)
    sup = wc.find { |c| c['name'] == 'Supply' }
    assert_in_delta U.mm(350), sup['wpos'][1], 1e-6
  end

  def test_sprinkler_layout
    pts = [[0, 0, 0], [10_000, 0, 0], [10_000, 6000, 0], [0, 6000, 0]].map { |p| Geom::Point3d.new(*p.map { |v| U.mm(v) }) }
    face = Sketchup::Face.new(pts)
    Sketchup.active_model.selection << face
    MEPStudio::Layout.sprinklers
    assert_match(/6 heads/, $msgs.last)
    zone = Sketchup.active_model.entities.find { |e| e.is_a?(Sketchup::Group) && e.get_attribute('MEPStudio', 'container') }
    sizes = zone.entities.map { |e| e.get_attribute('MEPStudio', 'dn') }.compact.uniq.sort
    assert_includes sizes, 25
    # clash check over the generated layout must not flag its own tees / drops
    res = MEPStudio::Clash.detect('clearance' => 0, 'check_mep' => true, 'check_arch' => false, 'only_visible' => true, 'ignore_tags' => '')
    assert_empty res, res.map { |c| [c[:a].name, c[:b][:name]] }.inspect
  end

  def test_boq_and_edges
    MEPStudio::RunBuilder.build(Sketchup.active_model.entities, [[0, 0, 0], [U.mm(5000), 0, 0]],
                                'kind' => 'duct', 'shape' => 'rect', 'system' => 'SA', 'width' => 400, 'height' => 250)
    captured = nil
    MEPStudio::Commands.stub(:show_boq, ->(l) { captured = l }) { MEPStudio::Commands.boq }
    assert_in_delta 5.0, captured.first['qty'], 0.01
    assert_in_delta 6.5, captured.first['area'], 0.01
  end

  def test_path_tool_flow
    view = Object.new
    def view.invalidate = nil
    tool = MEPStudio::PathTool.new('duct')
    tool.onUserText('600x300', view)
    tool.add_point([0, 0, tool.center_offset], nil, view)
    tool.onUserText('e3200', view)
    tool.add_point([U.mm(4000), 0, tool.level_z], nil, view)
    tool.onUserText('z+1000', view)
    tool.onReturn(view)
    g = Sketchup.active_model.entities.grep(Sketchup::Group).last
    assert_equal '600x300', g.get_attribute('MEPStudio', 'size')
    path = MEPStudio::RunBuilder.path_from(g).map { |p| p.map { |c| U.to_mm(c).round } }
    # bottom 2900 default + half height 150 -> 3050 centre; then e3200 -> 3350; then +1000
    assert_equal [[0, 0, 3050], [0, 0, 3350], [4000, 0, 3350], [4000, 0, 4350]], path
    pt = MEPStudio::PathTool.new('pipe')
    pt.onUserText('dn80', view)
    assert_equal 'DN80 @ ', "DN#{pt.instance_variable_get(:@opts)['dn']} @ "
  end
end
