# frozen_string_literal: true

# UI-level stand-ins (view, input point, commands, dialogs) so the tools can
# be driven by simulated mouse/keyboard events. The fake view is a top view:
# screen x = world x, screen y = -world y.

require 'tmpdir'
require_relative 'mock_sketchup'

MF_CHECKED = 1
MF_UNCHECKED = 0
TB_HIDDEN = 0
TB_VISIBLE = 1
SB_PROMPT = 0
GL_LINES = 1
GL_LINE_LOOP = 2
GL_QUADS = 7
GL_POLYGON = 9
VK_LEFT = 37
VK_UP = 38
VK_RIGHT = 39
VK_DOWN = 40
CONSTRAIN_MODIFIER_KEY = 16
CONSTRAIN_MODIFIER_MASK = 4
COPY_MODIFIER_KEY = 17
COPY_MODIFIER_MASK = 8

$loaded_files = {}
def file_loaded?(f) = $loaded_files.key?(f)
def file_loaded(f) = ($loaded_files[f] = true)

class String
  def to_l
    Float(delete('"').strip)
  rescue StandardError
    raise ArgumentError, "Cannot convert #{self} to Length"
  end
end

module Geom
  class Vector3d
    def parallel?(other) = (self * other).length < 1e-9
    def samedirection?(other) = parallel?(other) && (self % other).positive?
  end

  class Point3d
    def offset(v, len = nil)
      v = v.normalize * len if len
      self + v
    end

    def project_to_plane(plane)
      origin, normal = plane
      n = normal.normalize
      self - n * ((self - origin) % n)
    end

    def project_to_line(line)
      origin, dir = line
      d = dir.normalize
      origin + d * ((self - origin) % d)
    end
  end

  def self.intersect_line_plane(line, plane)
    p, d = line
    o, n = plane
    denom = d % n
    return nil if denom.abs < 1e-12

    t = ((o - p) % n) / denom
    p + d * t
  end

  def self.closest_points(line1, line2)
    p1, d1 = line1
    p2, d2 = line2
    w = p1 - p2
    a = d1 % d1
    b = d1 % d2
    c = d2 % d2
    d = d1 % w
    e = d2 % w
    denom = a * c - b * b
    if denom.abs < 1e-12
      return [p1, p2 + d2 * (e / c)]
    end

    s = (b * e - c * d) / denom
    t = (a * e - b * d) / denom
    [p1 + d1 * s, p2 + d2 * t]
  end
end

module Sketchup
  class Color
    def initialize(*args) = (@rgba = args)
  end

  module RegionalSettings
    def self.list_separator = ','
  end

  class Face
    def normal
      pts = vertices.map(&:position)
      Banian::Stretch::Geometry.polygon_normal(pts)
    end

    def outer_loop = Struct.new(:vertices).new(vertices)
    def parent = @parent_obj
    attr_writer :parent_obj
  end

  class Edge
    def parent = @parent_obj
    attr_writer :parent_obj
  end

  class Axes
    def xaxis = Geom::Vector3d.new(1, 0, 0)
    def yaxis = Geom::Vector3d.new(0, 1, 0)
    def zaxis = Geom::Vector3d.new(0, 0, 1)
  end

  class Selection
    def initialize = (@items = [])
    def to_a = @items
    def size = @items.size
    def add(*e) = @items.concat(e.flatten)
  end

  class Camera
    def perspective? = false
    def eye = Geom::Point3d.new(0, 0, 1000)
    def direction = Geom::Vector3d.new(0, 0, -1)
  end

  class PickHelper
    attr_accessor :result # [leaf, path, transformation]

    def do_pick(_x, _y) = nil
    def picked_edge = result && result[0].is_a?(Edge) ? result[0] : nil
    def picked_face = result && result[0].is_a?(Face) ? result[0] : nil
    def count = result ? 1 : 0
    def leaf_at(_i) = result[0]
    def path_at(_i) = result[1] + [result[0]]
    def transformation_at(_i) = result[2]
  end

  class View
    attr_reader :draw_calls, :pick_helper
    attr_accessor :tooltip, :drawing_color, :line_width, :line_stipple

    def initialize
      @draw_calls = 0
      @pick_helper = PickHelper.new
      @locked = false
    end

    def camera = Camera.new
    def screen_coords(pt) = Geom::Point3d.new(pt.x, -pt.y, 0)
    def pickray(x, y) = [Geom::Point3d.new(x, -y, 1000), Geom::Vector3d.new(0, 0, -1)]
    def invalidate = self
    def lock_inference(*args) = (@locked = !args.empty?)
    def inference_locked? = @locked

    def draw(mode, pts)
      raise 'bad points' unless pts.all? { |p| p.is_a?(Geom::Point3d) }
      raise 'odd line count' if mode == GL_LINES && pts.size.odd?

      @draw_calls += 1
    end

    attr_reader :draw2d_calls

    def draw2d(mode, pts)
      @draw2d_calls = (@draw2d_calls || 0) + 1
      draw(mode, pts)
    end
    def draw_points(pts, *_rest) = draw(GL_POLYGON, pts)
  end

  class InputPoint
    attr_reader :position

    def initialize = (@position = nil)

    def pick(_view, x, y, _ref = nil)
      @position = Geom::Point3d.new(x, -y, 0)
      true
    end

    def copy!(other) = (@position = other.position&.clone; self)
    def valid? = !@position.nil?
    def degrees_of_freedom = 2
    def display? = valid?
    def draw(_view) = nil
    def tooltip = ''
    def face = nil
    def transformation = Geom::Transformation.new
  end

  class Tools
    attr_accessor :active_tool
  end

  class Model
    attr_reader :selection, :active_view, :tools

    alias_method :core_initialize, :initialize
    def initialize
      core_initialize
      @selection = Selection.new
      @active_view = View.new
      @tools = Tools.new
    end

    def active_path = nil
    def axes = Axes.new
    def entities = @active_entities
    def bounds = @root.bounds

    def select_tool(tool)
      @tools.active_tool = tool
      tool&.activate
    end
  end

  class << self
    attr_accessor :active_model, :status_text, :vcb_label, :vcb_value

    def require(path) = Kernel.require(path)
    def platform = :platform_win
    def format_length(l) = "#{l.to_f.round(4)}\""
    def set_status_text(*args) = (self.status_text = args.first)
    def get_locale = 'en-US'
    def version = '26.0.0-mock'
    def temp_dir = Dir.tmpdir
  end
end

module UI
  @beeps = 0
  @messages = []
  class << self
    attr_reader :beeps, :messages

    def beep = (@beeps += 1)
    def messagebox(text) = (@messages << text)
    def menu(_name) = Menu.new
  end

  class Menu
    def add_submenu(_name) = Menu.new
    def add_item(cmd) = cmd
    def add_separator = nil
  end

  class Command
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon
    attr_reader :label, :validation

    @all = []
    class << self
      attr_reader :all
    end

    def initialize(label, &block)
      @label = label
      @block = block
      Command.all << self
    end

    def set_validation_proc(&block) = (@validation = block)
    def invoke = @block.call
  end

  class Toolbar
    attr_reader :items

    def initialize(_name) = (@items = [])
    def add_item(cmd) = (@items << cmd)
    def add_separator = (@items << :separator)
    def get_last_state = TB_VISIBLE
    def restore = nil
  end

  class HtmlDialog
    STYLE_DIALOG = 1
    attr_reader :callbacks, :scripts

    def initialize(_opts)
      @callbacks = {}
      @scripts = []
      @visible = false
    end

    def set_file(path) = (raise "missing #{path}" unless File.exist?(path))
    def add_action_callback(name, &block) = (@callbacks[name] = block)
    def show = (@visible = true)
    def visible? = @visible
    def bring_to_front = nil
    def execute_script(js) = (@scripts << js)
  end
end
