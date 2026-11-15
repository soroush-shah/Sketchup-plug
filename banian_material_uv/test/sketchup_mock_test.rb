# Minimal SketchUp API mock to exercise the adapter, menus and dialog code.
# Run: ruby banian_material_uv/test/sketchup_mock_test.rb
require 'minitest/autorun'
require 'json'

$calls = []

module Geom
  class Point3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0) @x = x.to_f; @y = y.to_f; @z = z.to_f end
    def to_a() [@x, @y, @z] end
  end
  class Vector3d < Point3d
    def *(o) a = to_a; b = o.to_a; Vector3d.new(a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]) end
    def %(o) a = to_a; b = o.to_a; a[0]*b[0]+a[1]*b[1]+a[2]*b[2] end
  end
  class Transformation
    def initialize(off = [0, 0, 0], sc = 1.0) @off = off; @sc = sc end
    def *(o)
      if o.is_a?(Transformation)
        Transformation.new([@off[0] + o.off[0] * @sc, @off[1] + o.off[1] * @sc, @off[2] + o.off[2] * @sc], @sc * o.sc)
      else
        a = o.to_a; Point3d.new(a[0] * @sc + @off[0], a[1] * @sc + @off[1], a[2] * @sc + @off[2])
      end
    end
    attr_reader :off, :sc
    def xaxis() Vector3d.new(1, 0, 0) end
    def yaxis() Vector3d.new(0, 1, 0) end
    def zaxis() Vector3d.new(0, 0, 1) end
  end
  class BoundingBox; def add(*) end; end
end

module Sketchup
  @ids = 0
  def self.next_id() @ids += 1 end
  def self.version() '27.0.100' end
  def self.status_text=(s) $calls << [:status, s] end
  def self.read_default(*) nil end
  def self.write_default(*) true end
  def self.temp_dir() Dir.pwd end
  def self.require(p) Kernel.require(p) end
  def self.active_model() $model end
  def self.register_extension(*) true end

  class Entity
    attr_reader :entityID
    def initialize() @entityID = Sketchup.next_id end
    def valid?() true end
    def hidden?() false end
  end
  class Vertex < Entity
    attr_reader :position
    def initialize(p) super(); @position = Geom::Point3d.new(*p) end
  end
  class Edge < Entity
    attr_accessor :faces, :start, :end, :soft
    def initialize(a, b) super(); @start = a; @end = b; @faces = []; @soft = true end
    def soft?() @soft end
    def smooth?() @soft end
  end
  class Loop
    attr_reader :vertices
    def initialize(v) @vertices = v end
  end
  class Face < Entity
    attr_accessor :material, :back_material, :parent, :edges, :positioned
    def initialize(verts) super(); @verts = verts; @edges = []; @positioned = [] end
    def outer_loop() Loop.new(@verts) end
    def position_material(mat, pts, front)
      raise ArgumentError, 'odd' if pts.size.odd? || pts.size < 2 || pts.size > 8
      pts.each { |p| raise ArgumentError, 'nan' unless p.to_a.all? { |x| x.finite? } }
      front ? (@material = mat) : (@back_material = mat)
      @positioned << [front, pts.size / 2]
    end
  end
  class Entities < Array
    attr_accessor :parent
  end
  class Group < Entity
    attr_accessor :material, :transformation
    attr_reader :entities
    def initialize(ents) super(); @entities = ents; @transformation = Geom::Transformation.new; ents.parent = self end
    def definition() self end
    def hidden?() false end
  end
  class ComponentInstance < Entity; end
  class Texture
    attr_reader :width, :height, :filename, :image_width
    def initialize(w, h) @width = w; @height = h; @filename = 'x.jpg'; @image_width = 512 end
  end
  class Color
    attr_reader :red, :green, :blue
    def initialize(r = 0, g = 0, b = 0) @red = r; @green = g; @blue = b end
  end
  class Material
    attr_accessor :name, :texture, :color
    def initialize(n, tex) @name = n; @texture = tex; @color = Color.new(100, 120, 140) end
    def display_name() @name end
  end
  class Materials
    include Enumerable
    attr_accessor :current
    def initialize() @m = [] end
    def add(n) m = Material.new(n, nil); @m << m; m end
    def <<(m) @m << m end
    def [](n) @m.find { |x| x.name == n } end
    def each(&b) @m.each(&b) end
  end
  class Selection < Array
    def add_observer(*) end
    def remove_observer(*) end
  end
  class SelectionObserver; end
  class Model
    attr_reader :materials, :selection
    def initialize() @materials = Materials.new; @selection = Selection.new end
    def start_operation(*) $calls << :start end
    def commit_operation() $calls << :commit end
    def abort_operation() $calls << :abort end
    def edit_transform() Geom::Transformation.new end
    def options() { 'UnitsOptions' => { 'LengthUnit' => 4 } } end
    def select_tool(t) $calls << [:tool, t.class.name] end
  end
end

class SketchupExtension
  attr_accessor :creator, :version, :copyright, :description
  def initialize(*) end
end

module UI
  class Command
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon
    def initialize(t, &b) @t = t; @b = b end
  end
  class Menu
    def add_submenu(*) Menu.new end
    def add_item(*) 1 end
    def add_separator() end
  end
  class Toolbar
    def initialize(*) end
    def add_item(*) end
    def get_last_state() -1 end
    def restore() end
  end
  def self.menu(*) Menu.new end
  def self.add_context_menu_handler(&b) $ctx = b end
  def self.messagebox(m) $calls << [:msg, m] end
  def self.start_timer(*) end
end

$loaded = {}
def file_loaded?(f) $loaded[f] end
def file_loaded(f) $loaded[f] = true end
module Kernel; alias_method :orig_require, :require; end
def require(n) return true if %w[sketchup.rb extensions.rb].include?(n); orig_require(n) end

$model = Sketchup::Model.new
SRC = File.expand_path('../src', __dir__)
load File.join(SRC, 'banian_material_uv.rb')
Kernel.require File.join(SRC, 'banian_material_uv', 'main')

# Build a lat-long sphere group inside the mock model
def make_sphere_group(r = 1000.0, seg = 16, rings = 8)
  ents = Sketchup::Entities.new
  verts = {}
  top = Sketchup::Vertex.new([0, 0, r]); bot = Sketchup::Vertex.new([0, 0, -r])
  (1...rings).each do |j|
    lat = Math::PI / 2 - Math::PI * j / rings
    seg.times { |i| lon = 2 * Math::PI * i / seg; verts[[i, j]] = Sketchup::Vertex.new([r * Math.cos(lat) * Math.cos(lon), r * Math.cos(lat) * Math.sin(lon), r * Math.sin(lat)]) }
  end
  edges = {}
  mk = lambda do |vs|
    f = Sketchup::Face.new(vs)
    vs.each_with_index do |a, k|
      b = vs[(k + 1) % vs.size]
      key = [a.entityID, b.entityID].sort
      e = (edges[key] ||= Sketchup::Edge.new(a, b))
      e.faces << f; f.edges << e
    end
    ents << f
  end
  seg.times do |i|
    i2 = (i + 1) % seg
    mk.call([top, verts[[i, 1]], verts[[i2, 1]]])
    (1...rings - 1).each { |j| mk.call([verts[[i, j]], verts[[i, j + 1]], verts[[i2, j + 1]], verts[[i2, j]]]) }
    mk.call([bot, verts[[i2, rings - 1]], verts[[i, rings - 1]]])
  end
  g = Sketchup::Group.new(ents)
  ents.each { |f| f.parent = g }
  g.transformation = Geom::Transformation.new([5000, 0, 0])
  g
end

class MockTest < Minitest::Test
  M = BanianStudio::MaterialUV

  def setup
    $calls.clear
    $model = Sketchup::Model.new
    @mat = Sketchup::Material.new('Brick', Sketchup::Texture.new(39.37, 39.37))
    $model.materials << @mat
    @g = make_sphere_group
    $model.selection << @g
    M::Settings.get.merge!(M::Settings::DEFAULTS)
  end

  def test_apply_all_modes
    %w[auto natural quad cylindrical spherical box planar].each do |mode|
      M::Settings.update('material' => 'Brick', 'mode' => mode, 'sides' => 'both')
      res = M.apply_selection
      assert res, "mode #{mode} returned nil: #{$calls.inspect}"
      assert_equal @g.entities.size, res[:faces], "mode #{mode}"
      assert_equal 0, res[:skipped]
    end
    assert @g.entities.all? { |f| f.material == @mat && f.back_material == @mat }
    assert_includes $calls, :commit
    refute_includes $calls, :abort
  end

  def test_auto_detects_sphere
    M::Settings.update('material' => 'Brick', 'mode' => 'auto')
    res = M.apply_selection
    assert_equal({ 'spherical' => 1 }, res[:modes])
  end

  def test_fit_and_transform
    M::Settings.update('material' => 'Brick', 'mode' => 'spherical', 'size_mode' => 'fit',
                       'rotation' => 45, 'scale_u' => 50, 'flip_u' => true, 'tile_w' => 2)
    res = M.apply_selection
    assert_equal @g.entities.size, res[:faces]
  end

  def test_existing_material_and_no_selection
    M::Settings.update('mat_source' => 'existing')
    @g.material = @mat
    res = M.apply_selection
    assert_equal @g.entities.size, res[:faces]
    $model.selection.clear
    assert_nil M.apply_selection
    assert($calls.any? { |c| c.is_a?(Array) && c[0] == :msg })
  end

  def test_targets_for_face_scopes
    f = @g.entities.first
    tr = @g.transformation
    assert_equal 1, M::Mapper.targets_for_face(f, tr, @g, 'face').size
    assert_equal @g.entities.size, M::Mapper.targets_for_face(f, tr, @g, 'surface').size
    assert_equal @g.entities.size, M::Mapper.targets_for_face(f, tr, @g, 'object').size
  end

  def test_dialog_state_json
    st = M::Dialog.state
    js = M::Dialog.js_json(st)
    assert js.ascii_only?
    back = JSON.parse(js)
    assert_equal 'Brick', back['materials'][0]['name']
    assert_equal 'm', back['units']
    assert_equal @g.entities.size, back['selection']['total']
    assert_equal '"' + 92.chr + 'u0628"', M::Dialog.js_json([0x628].pack('U'))
  end
end
