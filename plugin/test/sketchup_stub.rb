# frozen_string_literal: true
# Minimal fake of the SketchUp Ruby API – just enough to run the exporter and manifest outside SketchUp.
require 'tmpdir'

module Geom
  class Point3d
    attr_accessor :x, :y, :z

    def initialize(x = 0, y = 0, z = 0)
      @x, @y, @z = x.to_f, y.to_f, z.to_f
    end

    def transform(t) = t.apply(self)
  end

  class Vector3d < Point3d
    def reverse = Vector3d.new(-x, -y, -z)
    def transform(t) = t.apply_vec(self)

    def normalize!
      l = Math.sqrt(x * x + y * y + z * z)
      @x /= l
      @y /= l
      @z /= l
      self
    end
  end

  class BoundingBox
    attr_reader :min, :max

    def initialize(min, max)
      @min = min
      @max = max
    end

    def width = max.x - min.x
    def height = max.y - min.y
    def depth = max.z - min.z
  end

  # Column-major 4x4
  class Transformation
    attr_reader :m

    def initialize(m = nil)
      @m = m || [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].map(&:to_f)
    end

    def self.translation(x, y, z)
      new([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1].map(&:to_f))
    end

    def *(other)
      a = m
      b = other.m
      r = Array.new(16, 0.0)
      4.times { |c| 4.times { |row| r[c * 4 + row] = 4.times.sum { |k| a[k * 4 + row] * b[c * 4 + k] } } }
      Transformation.new(r)
    end

    def to_a = m.dup
    def apply(p) = Point3d.new(m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12], m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13], m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14])
    def apply_vec(p) = Vector3d.new(m[0] * p.x + m[4] * p.y + m[8] * p.z, m[1] * p.x + m[5] * p.y + m[9] * p.z, m[2] * p.x + m[6] * p.y + m[10] * p.z)
  end

  class PolygonMesh
    def initialize(points, normal, polys, uvs = nil)
      @points = points
      @normal = normal
      @polys = polys
      @uvs = uvs
    end

    def count_points = @points.size
    def point_at(i) = @points[i - 1]
    def normal_at(_i) = @normal
    def polygons = @polys
    def uv_at(i, _front) = @uvs ? @uvs[i - 1] : Point3d.new(0, 0, 1)
  end
end

module Sketchup
  def self.temp_dir = Dir.tmpdir
  def self.version = '24.0.0'
  def self.status_text=(_v); end

  class Color
    attr_reader :red, :green, :blue

    def initialize(r, g, b)
      @red, @green, @blue = r, g, b
    end
  end

  class Entity
    @@next = 0
    attr_reader :entityID

    def initialize
      @entityID = (@@next += 1)
    end
  end

  class Layer < Entity
    attr_reader :name, :color
    attr_accessor :visible

    def initialize(name, visible = true)
      super()
      @name = name
      @visible = visible
      @color = Color.new(200, 100, 50)
    end

    def visible? = @visible
    def display_name = name
  end

  class Texture
    attr_reader :filename

    def initialize(file)
      @filename = file
    end

    # Writes a real 64x64 checker PNG.
    def write(path, _colorize)
      require 'zlib'
      w = 64
      rows = (0...w).map { |y| "\0" + (0...w).map { |x| ((x / 8 + y / 8).even? ? [235, 228, 215] : [205, 196, 182]).pack('C3') }.join }
      chunk = ->(t, d) { [d.bytesize].pack('N') + t + d + [Zlib.crc32(t + d)].pack('N') }
      png = "\x89PNG\r\n\x1a\n".b + chunk.('IHDR', [w, w, 8, 2, 0, 0, 0].pack('NNC5')) + chunk.('IDAT', Zlib::Deflate.deflate(rows.join)) + chunk.('IEND', '')
      File.binwrite(path, png)
    end
  end

  class Material < Entity
    attr_reader :name, :color, :alpha, :texture

    def initialize(name, rgb, alpha: 1.0, texture: nil)
      super()
      @name = name
      @color = Color.new(*rgb)
      @alpha = alpha
      @texture = texture ? Texture.new(texture) : nil
    end

    def display_name = name
  end

  class Drawingelement < Entity
    attr_accessor :layer, :material, :hidden

    def hidden? = !!@hidden
  end

  class Face < Drawingelement
    attr_accessor :back_material

    # quad in XY plane at given z
    def initialize(layer, pts, material: nil)
      super()
      @layer = layer
      @pts = pts
      @material = material
    end

    def normal
      a, b, c = @pts
      u = [b.x - a.x, b.y - a.y, b.z - a.z]
      v = [c.x - a.x, c.y - a.y, c.z - a.z]
      n = Geom::Vector3d.new(u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
      l = Math.sqrt(n.x**2 + n.y**2 + n.z**2)
      l.zero? ? Geom::Vector3d.new(0, 0, 1) : n.normalize!
    end

    def mesh(_flags)
      uvs = @pts.map { |p| Geom::Point3d.new((p.x + p.y) / 40, p.z / 40 + p.y / 40, 1) }
      Geom::PolygonMesh.new(@pts, normal, [[1, 2, -3], [1, 3, 4]], uvs)
    end
  end

  class Vertex
    attr_reader :position

    def initialize(p)
      @position = p
    end
  end

  class Edge < Drawingelement
    attr_reader :start, :end

    def initialize(layer, a, b)
      super()
      @layer = layer
      @start = Vertex.new(a)
      @end = Vertex.new(b)
    end

    def soft? = false
    def smooth? = false
    def faces = []
  end

  class Entities < Array
    attr_accessor :parent, :active_section_plane
  end

  class ComponentDefinition < Entity
    attr_reader :name, :entities
    attr_accessor :instances_count

    def initialize(name)
      super()
      @name = name
      @entities = Entities.new
      @entities.parent = self
      @instances_count = 0
    end

    def description = ''
    def image? = false
    def group? = false
    def count_used_instances = instances_count
    def bounds = Geom::BoundingBox.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 10, 10))
  end

  class ComponentInstance < Drawingelement
    attr_reader :definition, :transformation

    def initialize(defn, tr, layer)
      super()
      @definition = defn
      @transformation = tr
      @layer = layer
      defn.instances_count += 1
    end
  end

  class Group < ComponentInstance; end

  class SectionPlane < Drawingelement
    def initialize(plane)
      super()
      @plane = plane
    end

    def get_plane = @plane
    def name = 'Section A'
  end

  class Camera
    attr_reader :eye, :target, :up, :fov, :height

    def initialize(eye, target, up, persp = true, fov = 35.0)
      @eye, @target, @up, @persp, @fov = eye, target, up, persp, fov
      @height = 100
    end

    def perspective? = @persp
    attr_writer :height
  end

  class Page
    attr_reader :name, :camera, :layers

    def initialize(name, camera, hidden_layers)
      @name = name
      @camera = camera
      @layers = hidden_layers
    end

    def description = ''
    def use_camera? = true
    def use_hidden_layers? = true
  end

  class Layers < Array; end

  class Model
    attr_reader :entities, :layers, :pages, :definitions, :title

    def initialize
      @entities = Entities.new
      @entities.parent = self
      @layers = Layers.new([Layer.new('Layer0')])
      def @layers.[](k) = k.is_a?(String) ? find { |l| l.name == k } : super
      @pages = []
      @definitions = []
      @title = 'Test model'
    end

    def options = { 'UnitsOptions' => { 'LengthUnit' => 2, 'LengthPrecision' => 0 } }
    def bounds = Geom::BoundingBox.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1000, 1000, 300))
  end
end
