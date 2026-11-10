# encoding: UTF-8
# Minimal stand-in for the SketchUp Ruby API, just enough to exercise the
# Banian SketchUp layer outside SketchUp. Not a full emulation.

def file_loaded?(_f) = false
def file_loaded(_f) = nil

MF_ENABLED = 0
MF_GRAYED = 2

module Geom
  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0) = (@x, @y, @z = x.to_f, y.to_f, z.to_f)
    def to_a = [x, y, z]
    def -(o) = Vector3d.new(x - o.x, y - o.y, z - o.z)
    def ==(o) = o.is_a?(Point3d) && to_a == o.to_a
    def distance(o) = Math.sqrt((x - o.x)**2 + (y - o.y)**2 + (z - o.z)**2)
  end

  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0) = (@x, @y, @z = x.to_f, y.to_f, z.to_f)
    def to_a = [x, y, z]
    def dot(o) = x * o.x + y * o.y + z * o.z
    def cross(o) = Vector3d.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    def length = Math.sqrt(dot(self))
    def normalize! = (l = length; @x /= l; @y /= l; @z /= l; self)
    def parallel?(o) = cross(o).length < 1e-9
  end

  class Transformation
    attr_reader :origin
    def initialize(o = nil) = (@origin = o || Point3d.new)
    def self.axes(o, *_a) = new(o)
    def self.translation(v) = new(Point3d.new(v.x, v.y, v.z))
    def self.rotation(*_a) = new
    def self.scaling(*_a) = new
    def inverse = Transformation.new(Point3d.new(-origin.x, -origin.y, -origin.z))
    def *(p)
      return p if p.is_a?(Vector3d)
      return Transformation.new(self * p.origin) if p.is_a?(Transformation)
      Point3d.new(p.x + origin.x, p.y + origin.y, p.z + origin.z)
    end
  end

  class PolygonMesh
    SOFTEN_BASED_ON_INDEX = 2
    SMOOTH_SOFT_EDGES = 8
    attr_reader :points, :polygons
    def initialize(*_a) = (@points = []; @polygons = [])
    def add_point(p) = (@points << p; @points.size)
    def add_polygon(idx) = (@polygons << idx; @polygons.size)
  end
end

module Sketchup
  def self.version = '24.0.0'
  def self.active_model = (@model ||= Model.new)
  def self.reset! = (@model = Model.new)

  module Attr
    def attrs = (@attrs ||= Hash.new { |h, k| h[k] = {} })
    def set_attribute(d, k, v) = (attrs[d][k] = v)
    def get_attribute(d, k, default = nil) = attrs[d].key?(k) && !attrs[d][k].nil? ? attrs[d][k] : default
    def attribute_dictionary(d) = attrs.key?(d) ? attrs[d] : nil
  end

  class Entity
    include Attr
    attr_accessor :parent, :material, :name, :hidden
    @@ids = 0
    def entityID = (@id ||= (@@ids += 1))
    def valid? = !@erased
    def erase! = (@erased = true; parent.entities_list.delete(self) if parent.respond_to?(:entities_list))
    def model = Sketchup.active_model
  end

  class Face < Entity
    attr_reader :pts
    def initialize(pts) = (@pts = pts)
    def normal = Geom::Vector3d.new(0, 0, 1)
    def reverse! = self
  end

  class Entities
    attr_reader :parent, :list, :meshes
    def initialize(parent) = (@parent = parent; @list = [])
    def entities_list = @list
    def each(&b) = @list.each(&b)
    def grep(c) = @list.grep(c)
    def add_group
      d = Sketchup.active_model.definitions.add_group_def
      g = Group.new(d)
      g.parent = parent
      d.instances_list << g
      @list << g
      g
    end
    def add_instance(d, tr)
      i = ComponentInstance.new(d, tr)
      i.parent = parent
      d.instances_list << i
      @list << i
      i
    end
    def fill_from_mesh(mesh, _w, _f) = ((@meshes ||= []) << mesh; true)
    def add_faces_from_mesh(mesh, _f) = ((@meshes ||= []) << mesh; true)
    def add_face(pts) = Face.new(pts).tap { |f| f.parent = self; @list << f }
    def clear!
      @list.each { |e| e.definition.instances_list.delete(e) if e.respond_to?(:definition) }
      @list.clear
      @meshes = []
    end
    def polygon_count = (@meshes || []).sum { |m| m.polygons.size }
  end

  class ComponentDefinition < Entity
    attr_reader :entities, :instances_list
    attr_writer :group
    def initialize(name) = (@name = name; @entities = Entities.new(self); @instances_list = [])
    def instances = @instances_list
    def count_instances = @instances_list.size
    def group? = @group ? true : false
    def image? = false
    Bounds = Struct.new(:min, :max) do
      def center = Geom::Point3d.new((min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2)
      def width = max.x - min.x
      def height = max.y - min.y
      def depth = max.z - min.z
    end
    attr_writer :bounds
    def bounds = @bounds || Bounds.new(Geom::Point3d.new, Geom::Point3d.new(1, 1, 1))
  end

  class Group < Entity
    attr_accessor :transformation
    attr_reader :definition
    def initialize(d) = (@definition = d)
    def entities = @definition.entities
    def make_unique = self
  end

  class ComponentInstance < Group
    def initialize(d, tr) = (super(d); @transformation = tr)
  end

  class Definitions
    include Enumerable
    def initialize = (@list = [])
    def each(&b) = @list.each(&b)
    def add(name) = ComponentDefinition.new(name).tap { |d| d.parent = Sketchup.active_model; @list << d }
    def add_group_def = add("Group##{@list.size}").tap { |d| d.group = true }
    def [](n) = @list.find { |d| d.name == n }
    def remove(d) = @list.delete(d)
  end

  class Material
    attr_accessor :name, :color, :alpha
  end

  class Materials
    include Enumerable
    def initialize = (@h = {})
    def [](n) = @h[n]
    def add(n) = (@h[n] = Material.new.tap { |m| m.name = n })
    def each(&b) = @h.values.each(&b)
  end

  class Color
    def initialize(*a) = (@rgb = a)
  end

  class Selection < Array
    def add(x) = (Array(x).each { |e| push(e) }; self)
  end

  class Model
    include Attr
    attr_reader :entities, :definitions, :materials, :selection, :ops
    def initialize
      @entities = Entities.new(self)
      @definitions = Definitions.new
      @materials = Materials.new
      @selection = Selection.new
      @ops = []
    end
    def active_entities = @entities
    def edit_transform = Geom::Transformation.new
    def start_operation(*a) = @ops << [:start, *a]
    def commit_operation = @ops << [:commit]
    def abort_operation = @ops << [:abort]
  end

  class Vertex
    attr_reader :position
    def initialize(p) = (@position = p)
  end

  class Edge < Entity
    attr_reader :start, :end
    def initialize(a, b) = (@start = a; @end = b)
    def other_vertex(v) = v.equal?(@start) ? @end : @start
  end
end

class Numeric
  def mm = self / 25.4
end
