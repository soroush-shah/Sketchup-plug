# frozen_string_literal: true

# Minimal stand-in for the parts of the SketchUp Ruby API used by the
# Banian Stretch core (plan, region, applier). Only for offline tests.

module Geom
  class Vector3d
    attr_accessor :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      x, y, z = x if x.is_a?(Array)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def %(other) = x * other.x + y * other.y + z * other.z

    def *(other)
      return Vector3d.new(x * other, y * other, z * other) if other.is_a?(Numeric)

      Vector3d.new(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
    end

    def +(other) = Vector3d.new(x + other.x, y + other.y, z + other.z)
    def -(other) = Vector3d.new(x - other.x, y - other.y, z - other.z)
    def length = Math.sqrt(self % self)

    def length=(len)
      n = normalize
      @x = n.x * len
      @y = n.y * len
      @z = n.z * len
    end

    def normalize
      l = length
      Vector3d.new(x / l, y / l, z / l)
    end

    def reverse = Vector3d.new(-x, -y, -z)
    def valid? = length > 1e-12
    def to_a = [x, y, z]
    def clone = Vector3d.new(x, y, z)
  end

  class Point3d
    attr_accessor :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      x, y, z = x if x.is_a?(Array)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def -(other)
      return Vector3d.new(x - other.x, y - other.y, z - other.z) if other.is_a?(Point3d)

      Point3d.new(x - other.x, y - other.y, z - other.z)
    end

    def +(other) = Point3d.new(x + other.x, y + other.y, z + other.z)
    def to_a = [x, y, z]
    def clone = Point3d.new(x, y, z)
    def distance(other) = (self - other).length

    def ==(other)
      other.is_a?(Point3d) && distance(other) < 1e-6
    end
  end

  # Row-major 4x4 internally; to_a is column-major like SketchUp.
  class Transformation
    attr_reader :m

    def initialize(m = nil)
      @m = m || [[1.0, 0, 0, 0], [0, 1.0, 0, 0], [0, 0, 1.0, 0], [0, 0, 0, 1.0]]
    end

    def self.translation(v) = new([[1.0, 0, 0, v.x], [0, 1.0, 0, v.y], [0, 0, 1.0, v.z], [0, 0, 0, 1.0]])

    def self.rotation_z(deg)
      a = deg * Math::PI / 180.0
      c = Math.cos(a)
      s = Math.sin(a)
      new([[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1.0, 0], [0, 0, 0, 1.0]])
    end

    def self.scaling(sx, sy, sz) = new([[sx, 0, 0, 0], [0, sy, 0, 0], [0, 0, sz, 0], [0, 0, 0, 1.0]])

    def *(other)
      case other
      when Transformation
        Transformation.new(Array.new(4) { |i| Array.new(4) { |j| (0..3).sum { |k| m[i][k] * other.m[k][j] } } })
      when Point3d
        Point3d.new(*(0..2).map { |i| m[i][0] * other.x + m[i][1] * other.y + m[i][2] * other.z + m[i][3] })
      when Vector3d
        Vector3d.new(*(0..2).map { |i| m[i][0] * other.x + m[i][1] * other.y + m[i][2] * other.z })
      end
    end

    def inverse
      # Gauss-Jordan.
      a = m.map { |r| r.map(&:to_f) }
      inv = Transformation.new.m.map(&:dup)
      4.times do |c|
        p = (c..3).max_by { |r| a[r][c].abs }
        a[c], a[p] = a[p], a[c]
        inv[c], inv[p] = inv[p], inv[c]
        d = a[c][c]
        4.times { |j| a[c][j] /= d; inv[c][j] /= d }
        4.times do |r|
          next if r == c

          f = a[r][c]
          4.times { |j| a[r][j] -= f * a[c][j]; inv[r][j] -= f * inv[c][j] }
        end
      end
      Transformation.new(inv)
    end

    def to_a = (0..3).flat_map { |j| (0..3).map { |i| m[i][j] } }
  end

  class BoundingBox
    def initialize
      @min = nil
      @max = nil
    end

    def add(*pts)
      pts.flatten.each do |p|
        if p.is_a?(BoundingBox)
          next if p.empty?

          add(p.corner(0), p.corner(7))
          next
        end
        @min = @min ? Point3d.new([@min.x, p.x].min, [@min.y, p.y].min, [@min.z, p.z].min) : p.clone
        @max = @max ? Point3d.new([@max.x, p.x].max, [@max.y, p.y].max, [@max.z, p.z].max) : p.clone
      end
      self
    end

    def empty? = @min.nil?

    def corner(i)
      Point3d.new(i & 1 == 0 ? @min.x : @max.x, i & 2 == 0 ? @min.y : @max.y, i & 4 == 0 ? @min.z : @max.z)
    end
  end
end

module Sketchup
  class Entity
    @@next_id = 1
    attr_reader :entityID

    def initialize
      @entityID = @@next_id
      @@next_id += 1
      @valid = true
    end

    def valid? = @valid
    def erase! = (@valid = false)
    def inspect = "#<#{self.class.name} #{@entityID}>"
  end

  class Drawingelement < Entity
    attr_accessor :layer, :hidden

    def hidden? = !!@hidden
  end

  class Vertex < Entity
    attr_accessor :position
    attr_reader :edges

    def initialize(pos)
      super()
      @position = pos
      @edges = []
    end
  end

  class Edge < Drawingelement
    attr_reader :start, :end

    def initialize(a, b)
      super()
      @start = a
      @end = b
      a.edges << self
      b.edges << self
    end

    def vertices = [@start, @end]
  end

  class Face < Drawingelement
    attr_reader :vertices

    def initialize(vertices)
      super()
      @vertices = vertices
    end
  end

  class ComponentDefinition < Entity
    attr_reader :entities
    attr_accessor :instances_list, :root

    def initialize
      super()
      @entities = Entities.new(self)
      @instances_list = []
    end

    def bounds
      bb = Geom::BoundingBox.new
      @entities.each do |e|
        case e
        when Edge then e.vertices.each { |v| bb.add(v.position) }
        when Group, ComponentInstance
          b = e.definition.bounds
          (0..7).each { |i| bb.add(e.transformation * b.corner(i)) } unless b.empty?
        end
      end
      bb
    end

    # Recursive count, like SketchUp's count_used_instances.
    def count_used_instances
      @instances_list.select(&:valid?).sum do |inst|
        parent = inst.parent_definition
        parent.nil? ? 1 : parent.count_used_instances
      end
    end

    def deep_copy
      copy = ComponentDefinition.new
      vmap = {}
      items = @entities.to_a.shuffle(random: Random.new(42)) # order must not matter
      items.each do |e|
        case e
        when Edge
          a = vmap[e.start.entityID] ||= Vertex.new(e.start.position.clone)
          b = vmap[e.end.entityID] ||= Vertex.new(e.end.position.clone)
          copy.entities.add(Edge.new(a, b))
        end
      end
      items.each do |e|
        case e
        when Face
          copy.entities.add(Face.new(e.vertices.map { |v| vmap[v.entityID] }))
        when Group, ComponentInstance
          copy.entities.add(e.class.new(e.definition, e.transformation))
        end
      end
      copy
    end
  end

  class Entities
    include Enumerable
    attr_reader :parent

    def initialize(parent)
      @parent = parent
      @items = []
    end

    def add(e)
      @items << e
      if e.respond_to?(:parent_definition=)
        e.parent_definition = @parent.is_a?(ComponentDefinition) && !@parent.root ? @parent : nil
      end
      e
    end

    def each(&) = @items.select(&:valid?).each(&)
    def to_a = @items.select(&:valid?)

    def transform_entities(tr, ents)
      @transforms = (@transforms || 0) + 1
      ents.each do |e|
        case e
        when Vertex then e.position = tr * e.position
        when Group, ComponentInstance then e.transformation = tr * e.transformation
        else raise "unsupported #{e.class}"
        end
      end
    end

    def transform_count = @transforms || 0
  end

  class ComponentInstance < Drawingelement
    attr_accessor :transformation, :parent_definition, :locked
    attr_reader :definition

    def initialize(definition, transformation = Geom::Transformation.new)
      super()
      @definition = definition
      @transformation = transformation
      definition.instances_list << self
    end

    def locked? = !!@locked

    def make_unique
      @definition.instances_list.delete(self)
      @definition = @definition.deep_copy
      @definition.instances_list << self
      self
    end
  end

  class Group < ComponentInstance; end

  class Model
    attr_reader :active_entities, :operations
    attr_accessor :edit_transform

    def initialize
      @root = ComponentDefinition.new
      @root.root = true
      @active_entities = @root.entities
      @edit_transform = Geom::Transformation.new
      @operations = []
    end

    def start_operation(name, _disable_ui = false) = @operations << [:start, name]
    def commit_operation = @operations << [:commit]
    def abort_operation = @operations << [:abort]
  end
end

# ---- Builders ---------------------------------------------------------------

module MockBuild
  module_function

  # Axis-aligned box made of 12 edges and 6 faces, added to `entities`.
  # Returns the 8 vertices (ordered like BoundingBox#corner).
  def box(entities, min, max)
    verts = (0..7).map do |i|
      Sketchup::Vertex.new(Geom::Point3d.new(i & 1 == 0 ? min[0] : max[0],
                                             i & 2 == 0 ? min[1] : max[1],
                                             i & 4 == 0 ? min[2] : max[2]))
    end
    [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]].each do |a, b|
      entities.add(Sketchup::Edge.new(verts[a], verts[b]))
    end
    [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]].each do |f|
      entities.add(Sketchup::Face.new(f.map { |i| verts[i] }))
    end
    verts
  end

  def xs(entities)
    entities.to_a.grep(Sketchup::Edge).flat_map(&:vertices).uniq.map { |v| v.position.x.round(6) }.uniq.sort
  end
end
