# Minimal SketchUp API mock - only for smoke-testing the plugin logic.
ORIGIN_A = [0, 0, 0].freeze

module Geom
  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      @x, @y, @z = x.to_f, y.to_f, z.to_f
    end
    def clone; Vector3d.new(x, y, z); end
    def length; Math.sqrt(x * x + y * y + z * z); end
    def normalize!; l = length; @x /= l; @y /= l; @z /= l; self; end
    def reverse!; @x, @y, @z = -x, -y, -z; self; end
    def cross(o); Vector3d.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x); end
    def dot(o); x * o.x + y * o.y + z * o.z; end
    def angle_between(o); Math.acos([[dot(o) / (length * o.length), 1].min, -1].max); end
    def to_a; [x, y, z]; end
  end

  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      x, y, z = x if x.is_a?(Array)
      @x, @y, @z = x.to_f, y.to_f, z.to_f
    end
    def transform(t); t.apply(self); end
    def to_a; [x, y, z]; end
    def -(o); Vector3d.new(x - o.x, y - o.y, z - o.z); end
  end

  class Transformation
    attr_reader :m
    def initialize(arg = nil)
      @m = [[1.0, 0, 0, 0], [0, 1.0, 0, 0], [0, 0, 1.0, 0]]
      if arg.is_a?(Point3d)
        @m[0][3] = arg.x; @m[1][3] = arg.y; @m[2][3] = arg.z
      elsif arg.is_a?(Array) && arg.length == 3 && arg[0].is_a?(Array)
        @m = arg
      end
    end
    def self.axes(o, x, y, z)
      Transformation.new([[x.x, y.x, z.x, o.x], [x.y, y.y, z.y, o.y], [x.z, y.z, z.z, o.z]])
    end
    def self.rotation(pt, axis, ang)
      a = axis.clone.normalize!
      c = Math.cos(ang); s = Math.sin(ang); t = 1 - c
      r = [[t * a.x * a.x + c, t * a.x * a.y - s * a.z, t * a.x * a.z + s * a.y],
           [t * a.x * a.y + s * a.z, t * a.y * a.y + c, t * a.y * a.z - s * a.x],
           [t * a.x * a.z - s * a.y, t * a.y * a.z + s * a.x, t * a.z * a.z + c]]
      p = [pt.x, pt.y, pt.z]
      m = (0..2).map { |i| r[i] + [p[i] - (0..2).inject(0) { |acc, j| acc + r[i][j] * p[j] }] }
      Transformation.new(m)
    end
    def apply(p)
      Point3d.new(*(0..2).map { |i| @m[i][0] * p.x + @m[i][1] * p.y + @m[i][2] * p.z + @m[i][3] })
    end
    def *(o)
      m = (0..2).map do |i|
        (0..3).map do |j|
          v = (0..2).inject(0) { |acc, k| acc + @m[i][k] * o.m[k][j] }
          j == 3 ? v + @m[i][3] : v
        end
      end
      Transformation.new(m)
    end
    def inverse
      rt = (0..2).map { |i| (0..2).map { |j| @m[j][i] } }
      tr = (0..2).map { |i| -(0..2).inject(0) { |acc, j| acc + rt[i][j] * @m[j][3] } }
      Transformation.new((0..2).map { |i| rt[i] + [tr[i]] })
    end
    def zaxis; Vector3d.new(@m[0][2], @m[1][2], @m[2][2]); end
  end

  class PolygonMesh
    attr_reader :pts, :polys
    def initialize(*_a); @pts = []; @polys = []; end
    def add_point(p); @pts << p; @pts.length; end
    def add_polygon(*idx); @polys << idx.flatten; @polys.length; end
  end
end

ORIGIN = Geom::Point3d.new(0, 0, 0)
X_AXIS = Geom::Vector3d.new(1, 0, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)
MF_ENABLED = 0
MF_GRAYED = 2

module Sketchup
  class Color
    attr_reader :red, :green, :blue
    def initialize(r, g, b); @red, @green, @blue = r.to_i, g.to_i, b.to_i; end
  end

  class Entity
    attr_accessor :parent
    def initialize; @attrs = {}; @valid = true; end
    def valid?; @valid; end
    def erase!; @valid = false; parent.entities.remove(self) if parent; end
    def set_attribute(d, k, v); (@attrs[d] ||= {})[k] = v; end
    def get_attribute(d, k, default = nil); (@attrs[d] || {}).fetch(k, default); end
    def entityID; object_id; end
  end

  class Vertex
    attr_reader :position
    def initialize(p); @position = p; end
  end

  class Edge < Entity
    attr_accessor :soft, :smooth
    def initialize(a, b); super(); @a = a; @b = b; end
    def length; Math.sqrt((@b.x - @a.x)**2 + (@b.y - @a.y)**2 + (@b.z - @a.z)**2); end
    def line; [@a, (@b - @a).normalize!]; end
    def faces; []; end
  end

  class Loop
    def initialize(pts, outer); @pts = pts; @outer = outer; end
    def vertices; @pts.map { |p| Vertex.new(p) }; end
    def edges; @pts.each_with_index.map { |p, i| Edge.new(p, @pts[(i + 1) % @pts.length]) }; end
    def outer?; @outer; end
  end

  class Face < Entity
    attr_accessor :material, :back_material, :hidden
    def initialize(pts); super(); @pts = pts; @holes = []; end
    def normal
      n = Geom::Vector3d.new
      @pts.each_with_index do |p, i|
        q = @pts[(i + 1) % @pts.length]
        n.x += (p.y - q.y) * (p.z + q.z); n.y += (p.z - q.z) * (p.x + q.x); n.z += (p.x - q.x) * (p.y + q.y)
      end
      n.normalize!
    end
    def reverse!; @pts.reverse!; self; end
    def outer_loop; Loop.new(@pts, true); end
    def loops; [outer_loop] + @holes.map { |h| Loop.new(h, false) }; end
    def add_hole(h); @holes << h; end
    def vertices; outer_loop.vertices; end
    def pushpull(t); @pts = @pts.map { |p| Geom::Point3d.new(p.x, p.y, p.z + t) }; end
    def area
      a = 0.0
      @pts.each_with_index { |p, i| q = @pts[(i + 1) % @pts.length]; a += p.x * q.y - q.x * p.y }
      a.abs / 2
    end
    def mesh(_f = 0)
      pts = @pts
      Object.new.tap { |o| o.define_singleton_method(:polygon_points_at) { |_i| pts[0, 3] } }
    end
    def position_material(mat, pts, front)
      raise 'bad uv pts' unless pts.length == 8
      $uv_calls += 1
      front ? @material = mat : @back_material = mat
    end
  end
  $uv_calls = 0

  class Entities
    include Enumerable
    attr_reader :list
    def initialize(owner = nil); @list = []; @owner = owner; end
    def each(&b); @list.dup.each(&b); end
    def remove(e); @list.delete(e); end
    def add(e); e.parent = (@owner || Sketchup.active_model); @list << e; e; end
    def length; @list.length; end
    def clear!; @list.clear; end
    def add_face(pts)
      pts = pts.map { |p| p.is_a?(Array) ? Geom::Point3d.new(*p) : p }
      raise 'face needs 3 pts' if pts.length < 3
      f = Face.new(pts)
      f.reverse! if f.normal.z < -0.5 # mimic ground-plane flip
      add(f)
    end
    def add_line(a, b); add(Edge.new(a, b)); end
    def add_group; add(Group.new); end
    def add_instance(d, t); add(ComponentInstance.new(d, t)); end
    def add_faces_from_mesh(mesh, _flags, mat, _bm)
      mesh.polys.each { |idx| f = add(Face.new(idx.map { |i| mesh.pts[i.abs - 1] })); f.material = mat }
    end
  end

  class Group < Entity
    attr_accessor :transformation, :name, :material
    attr_reader :entities
    def initialize; super(); @entities = Entities.new(self); @transformation = Geom::Transformation.new; end
    def explode; ents = @entities.list.dup; ents.each { |e| parent.entities.add(e) }; erase!; ents; end
  end

  class ComponentDefinition < Entity
    attr_reader :entities, :name
    def initialize(n); super(); @name = n; @entities = Entities.new(self); @count = 0; end
    def count_instances; @count; end
    def inc; @count += 1; end
  end

  class ComponentInstance < Entity
    attr_accessor :transformation, :material
    attr_reader :definition
    def initialize(d, t); super(); @definition = d; @transformation = t; d.inc; end
  end

  class Definitions
    include Enumerable
    def initialize; @l = []; end
    def add(n); d = ComponentDefinition.new(n); @l << d; d; end
    def each(&b); @l.each(&b); end
    def remove(d); @l.delete(d); end
    def length; @l.length; end
  end

  class Texture
    attr_accessor :filename
    def initialize(f); @filename = f; @w = 39.37; @h = 39.37; end
    def width; @w; end
    def height; @h; end
    def size=(a); @w, @h = a; end
  end

  class Material
    attr_accessor :name, :color
    attr_reader :texture
    def initialize(n); @name = n; @color = Color.new(200, 200, 200); end
    def texture=(f); @texture = f ? Texture.new(f) : nil; end
    def display_name; @name; end
  end

  class Materials
    include Enumerable
    def initialize; @h = {}; end
    def [](n); @h[n]; end
    def add(n); n = "#{n}#1" if @h[n]; @h[n] = Material.new(n); end
    def each(&b); @h.values.each(&b); end
    def length; @h.length; end
  end

  class Selection
    include Enumerable
    def initialize; @l = []; end
    def each(&b); @l.each(&b); end
    def length; @l.length; end
    def first; @l.first; end
    def clear; @l.clear; end
    def add(*e); @l.concat(e.flatten); end
    def add_observer(_o); end
    def remove_observer(_o); end
  end

  class SelectionObserver; end

  class Model
    attr_reader :entities, :materials, :definitions, :selection, :ops
    def initialize
      @entities = Entities.new; @materials = Materials.new; @definitions = Definitions.new
      @selection = Selection.new; @ops = []
    end
    def edit_transform; Geom::Transformation.new; end
    def select_tool(t); @tool = t; end
    def options; { 'UnitsOptions' => { 'LengthUnit' => 2 } }; end
    def start_operation(n, _d); @ops << [:start, n]; end
    def commit_operation; @ops << [:commit]; end
    def abort_operation; @ops << [:abort]; end
  end

  def self.active_model; $model ||= Model.new; end
  def self.status_text=(_s); end
  def self.temp_dir; Dir.tmpdir; end
  def self.write_default(_a, k, v); ($defaults ||= {})[k] = v; end
  def self.read_default(_a, k, d = nil); ($defaults ||= {}).fetch(k, d); end
  def self.require(f); Kernel.require(f); end
  def self.version; '27.0.0'; end
end

module UI
  def self.start_timer(_t, _r); yield; nil; end
  def self.beep; end
  def self.messagebox(m); puts "MSG: #{m}"; end
end

# ---- topology support (shared vertices / edges) for curved-surface tests ----
module Geom
  class Transformation
    alias_method :__init_orig, :initialize
    def initialize(arg = nil)
      if arg.is_a?(Array) && arg.length == 16
        a = arg
        @m = [[a[0], a[4], a[8], a[12]], [a[1], a[5], a[9], a[13]], [a[2], a[6], a[10], a[14]]]
      else
        __init_orig(arg)
      end
    end
    def to_a
      [@m[0][0], @m[1][0], @m[2][0], 0.0, @m[0][1], @m[1][1], @m[2][1], 0.0,
       @m[0][2], @m[1][2], @m[2][2], 0.0, @m[0][3], @m[1][3], @m[2][3], 1.0]
    end
  end
end

module Sketchup
  class Vertex
    def edges; @edges ||= []; end
    def common_edge(o); edges.find { |e| e.start == o || e.end == o }; end
  end

  class Edge
    attr_accessor :start, :end, :hidden_flag
    def soft?; !!@soft; end
    def smooth?; !!@smooth; end
    def hidden?; !!@hidden_flag; end
    def faces; @faces ||= []; end
    def reversed_in?(f)
      vs = f.topo_vertices
      n = vs.length
      n.times { |i| return false if vs[i] == @start && vs[(i + 1) % n] == @end }
      true
    end
  end

  class Face
    attr_reader :topo_vertices
    def set_topo(vs, edges); @topo_vertices = vs; @topo_edges = edges; end
    alias_method :__edges_orig, :outer_loop
    def edges; @topo_edges || outer_loop.edges; end
    def loops
      return [Loop.new(@pts, true)] + @holes.map { |h| Loop.new(h, false) } unless @topo_vertices
      [TopoLoop.new(@topo_vertices)]
    end
    def vertices; @topo_vertices || outer_loop.vertices; end
  end

  class TopoLoop
    def initialize(vs); @vs = vs; end
    def vertices; @vs; end
    def outer?; true; end
  end

  module Topo
    # pts: array of [x,y,z]; polys: arrays of indices; soft: mark inner edges soft
    def self.build(ents, pts, polys, soft = true)
      vs = pts.map { |p| Vertex.new(Geom::Point3d.new(*p)) }
      emap = {}
      faces = polys.map do |idx|
        fv = idx.map { |i| vs[i] }
        f = Face.new(fv.map(&:position))
        es = []
        fv.each_with_index do |a, k|
          b = fv[(k + 1) % fv.length]
          key = [a.object_id, b.object_id].sort
          e = emap[key]
          unless e
            e = Edge.new(a.position, b.position)
            e.start = a
            e.end = b
            a.edges << e
            b.edges << e
            emap[key] = e
          end
          e.faces << f
          es << e
        end
        f.set_topo(fv, es)
        ents.add(f)
      end
      emap.each_value { |e| e.soft = e.smooth = soft if e.faces.length > 1 }
      faces
    end
  end
end
