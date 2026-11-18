# frozen_string_literal: true

# Very small subset of the SketchUp Ruby API - just enough to unit test the
# pure logic of MEP Studio (clash detection, chains, layout math) on CI.
class Numeric
  def degrees = self * Math::PI / 180.0
  def mm = self / 25.4
end

module Geom
  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0) = (@x, @y, @z = x.to_f, y.to_f, z.to_f)
    def length = Math.sqrt(x * x + y * y + z * z)
    def normalize! = (l = length; @x /= l; @y /= l; @z /= l; self)
    def transform(t) = t.apply_vec(self)
    def dot(o) = x * o.x + y * o.y + z * o.z
  end

  class Point3d < Vector3d
    def transform(t) = t.apply(self)
  end

  class Transformation
    attr_reader :m # column-major 16
    def initialize(m = nil) = (@m = m || [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].map(&:to_f))
    def self.translation(p) = new([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, p.x, p.y, p.z, 1].map(&:to_f))
    def self.rotation(_o, _axis, a)
      c = Math.cos(a)
      s = Math.sin(a)
      new([c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].map(&:to_f))
    end
    def to_a = @m.dup
    def inverse = Transformation.new(@m.dup.tap { |a| a[12], a[13], a[14] = -a[12], -a[13], -a[14] }) # translations only
    def *(o)
      a = @m
      b = o.m
      r = Array.new(16, 0.0)
      4.times { |c| 4.times { |rr| r[c * 4 + rr] = (0..3).sum { |k| a[k * 4 + rr] * b[c * 4 + k] } } }
      Transformation.new(r)
    end
    def apply(p)
      Point3d.new(@m[0] * p.x + @m[4] * p.y + @m[8] * p.z + @m[12], @m[1] * p.x + @m[5] * p.y + @m[9] * p.z + @m[13],
                  @m[2] * p.x + @m[6] * p.y + @m[10] * p.z + @m[14])
    end
    def apply_vec(v)
      Vector3d.new(@m[0] * v.x + @m[4] * v.y + @m[8] * v.z, @m[1] * v.x + @m[5] * v.y + @m[9] * v.z,
                   @m[2] * v.x + @m[6] * v.y + @m[10] * v.z)
    end
  end

  class BoundingBox
    attr_reader :min, :max
    def add(*ps)
      ps.flatten.each do |p|
        @min = @min ? Point3d.new([@min.x, p.x].min, [@min.y, p.y].min, [@min.z, p.z].min) : Point3d.new(p.x, p.y, p.z)
        @max = @max ? Point3d.new([@max.x, p.x].max, [@max.y, p.y].max, [@max.z, p.z].max) : Point3d.new(p.x, p.y, p.z)
      end
      self
    end
    def center = Point3d.new((min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2)
    def width = max.x - min.x
    def height = max.y - min.y
    def depth = max.z - min.z
  end
end

module Sketchup
  class Layer
    attr_reader :name
    def initialize(n) = @name = n
    def visible? = true
  end
  DEFAULT_LAYER = Layer.new('Untagged')

  module Attr
    def attrs = (@attrs ||= {})
    def get_attribute(_d, k, default = nil) = attrs.key?(k) ? attrs[k] : default
    def set_attribute(_d, k, v) = attrs[k] = v
    def attribute_dictionary(_d) = @attrs.nil? ? nil : attrs
    def layer = (@layer || DEFAULT_LAYER)
    attr_writer :layer
    def hidden? = false
    def valid? = true
  end

  class Entity; end
  class Entities < Array; end

  class Definition
    include Attr
    attr_accessor :name, :entities, :bounds
    def initialize(name) = (@name, @entities = name, Entities.new)
  end

  class Group < Entity
    include Attr
    attr_accessor :name, :transformation, :definition
    def initialize(name = '') = (@name, @transformation, @definition = name, Geom::Transformation.new, Definition.new(name))
    def entities = definition.entities
    def typename = 'Group'
  end

  class ComponentInstance < Group
    def typename = 'ComponentInstance'
  end

  class Mesh
    attr_reader :points, :polygons
    def initialize(pts, polys) = (@points, @polygons = pts, polys)
  end

  class Face < Entity
    include Attr
    def initialize(pts) = @pts = pts
    def mesh(_f = 0)
      polys = (1...@pts.size - 1).map { |i| [1, i + 1, i + 2] }
      Mesh.new(@pts, polys)
    end
  end

  class Model
    attr_reader :entities
    def initialize = @entities = Entities.new
  end

  def self.active_model = (@model ||= Model.new)
  def self.reset_model! = @model = Model.new
end
