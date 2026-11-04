# frozen_string_literal: true

# Drives the real tools with simulated mouse / keyboard events. Run with:
#   ruby banian_stretch/tests/test_tools.rb

require 'minitest/autorun'
require_relative 'mock_ui'

module Sketchup
  class ComponentInstance
    attr_writer :parent_obj

    def parent = @parent_obj
  end
end

module Banian
  module Stretch
    EXTENSION_NAME = 'Banian Stretch'
    VERSION = '1.0.0-test'
    PLUGIN_ROOT = File.expand_path('../src/banian_stretch', __dir__)
  end
end

Sketchup.active_model = Sketchup::Model.new
require File.join(Banian::Stretch::PLUGIN_ROOT, 'main')

class ToolsTest < Minitest::Test
  include Banian::Stretch

  def setup
    Settings.reset!
    Settings::DEFAULTS.each_key { |k| Settings.instance_variable_get(:@cache).delete(k) }
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @view = @model.active_view
    @verts = MockBuild.box(@model.active_entities, [0, 0, 0], [100, 50, 50])
    @model.active_entities.each { |e| e.parent_obj = @model if e.respond_to?(:parent_obj=) }
  end

  def xs = MockBuild.xs(@model.active_entities)

  def use(tool)
    @model.select_tool(tool)
    tool
  end

  def drag(tool, from, to, flags = 0)
    tool.onLButtonDown(flags, *from, @view)
    tool.onMouseMove(flags, (from[0] + to[0]) / 2, (from[1] + to[1]) / 2, @view)
    tool.onMouseMove(flags, *to, @view)
    tool.draw(@view)
    tool.onLButtonUp(flags, *to, @view)
  end

  def click(tool, x, y, flags = 0)
    tool.onMouseMove(0, x, y, @view)
    tool.onLButtonDown(flags, x, y, @view)
    tool.onLButtonUp(flags, x, y, @view) if tool.respond_to?(:onLButtonUp)
    tool.draw(@view)
  end

  def test_extension_setup_builds_commands
    labels = UI::Command.all.map(&:label)
    assert_includes labels, 'Stretch (Window / Click)'
    assert_includes labels, 'Make Unique'
    tooltips = UI::Command.all.map(&:tooltip).compact
    assert tooltips.all? { |t| t.ascii_only? }, 'toolbar tooltips must be English'
    icons = UI::Command.all.map(&:small_icon).compact
    refute_empty icons
    icons.each { |path| assert File.exist?(path), "missing icon #{path}" }
    UI::Command.all.each { |c| c.validation&.call }
  end

  def test_toggle_commands_change_settings
    cmd = UI::Command.all.find { |c| c.label == 'Make Unique' }
    before = Settings.make_unique?
    cmd.invoke
    assert_equal !before, Settings.make_unique?
    cmd.invoke
  end

  def test_select_tool_window_and_two_clicks
    tool = use(SelectTool.new)
    drag(tool, [60, -60], [200, 10])
    assert_equal 4, tool.instance_variable_get(:@plan).vertex_count
    assert_match(/Selected: 4 vertices/, Sketchup.status_text)
    click(tool, 100, -25) # start point
    assert_equal :move, tool.instance_variable_get(:@state)
    tool.onMouseMove(0, 110, -25, @view)
    tool.draw(@view)
    tool.getExtents
    click(tool, 110, -25) # end point
    assert_equal [0.0, 110.0], xs
    assert_equal :select, tool.instance_variable_get(:@state)
  end

  def test_select_tool_typed_distance_and_axis_lock
    tool = use(SelectTool.new)
    drag(tool, [60, -60], [200, 10])
    click(tool, 100, -25)
    tool.onKeyDown(VK_RIGHT, 1, 0, @view)
    tool.onMouseMove(0, 130, -40, @view) # off-axis mouse, locked to X
    tool.draw(@view)
    tool.onUserText('25', @view)
    assert_equal [0.0, 125.0], xs
  end

  def test_negative_typed_distance
    tool = use(SelectTool.new)
    drag(tool, [60, -60], [200, 10])
    click(tool, 100, -25)
    tool.onMouseMove(0, 120, -25, @view)
    tool.onUserText('-30', @view)
    assert_equal [0.0, 70.0], xs
  end

  def test_shift_window_removes_and_escape_clears
    tool = use(SelectTool.new)
    drag(tool, [-10, -60], [200, 10])
    assert_equal 8, tool.instance_variable_get(:@plan).vertex_count
    drag(tool, [-10, -60], [50, 10], CONSTRAIN_MODIFIER_MASK)
    assert_equal 4, tool.instance_variable_get(:@plan).vertex_count
    tool.onCancel(0, @view)
    assert tool.instance_variable_get(:@plan).empty?
  end

  def test_click_on_face_selects_and_starts_move
    face = @model.active_entities.to_a.grep(Sketchup::Face).last # x = 100
    @view.pick_helper.result = [face, [], Geom::Transformation.new]
    tool = use(SelectTool.new)
    click(tool, 100, -25)
    assert_equal :move, tool.instance_variable_get(:@state)
    tool.onMouseMove(0, 115, -25, @view)
    click(tool, 115, -25)
    assert_equal [0.0, 115.0], xs
  end

  def test_escape_during_move_returns_to_selection
    tool = use(SelectTool.new)
    drag(tool, [60, -60], [200, 10])
    click(tool, 100, -25)
    tool.onCancel(0, @view)
    assert_equal :select, tool.instance_variable_get(:@state)
    assert_equal 4, tool.instance_variable_get(:@plan).vertex_count
    assert_equal [0.0, 100.0], xs
  end

  def test_box_tool_flow
    tool = use(BoxTool.new)
    click(tool, 60, -60)            # corner 1 (world 60, 60)
    tool.onMouseMove(0, 200, 10, @view)
    tool.draw(@view)
    click(tool, 200, 10)            # corner 2 (world 200, -10)
    assert_equal :height, tool.instance_variable_get(:@state)
    tool.draw(@view)
    tool.onUserText('100', @view)   # bound height
    assert_equal :selected, tool.instance_variable_get(:@state)
    assert_equal 4, tool.instance_variable_get(:@plan).vertex_count
    click(tool, 100, -25)
    tool.onMouseMove(0, 112, -25, @view)
    tool.getExtents
    click(tool, 112, -25)
    assert_equal [0.0, 112.0], xs
  end

  def test_box_tool_typed_dimensions_and_rotated
    tool = use(BoxTool.new)
    tool.onKeyDown(BaseTool::TAB_KEY, 1, 0, @view) # rotated mode
    click(tool, 60, 10)             # corner 1 (world 60, -10)
    click(tool, 60, -60)            # first side along +Y, 70 long
    assert_equal :corner3, tool.instance_variable_get(:@state)
    tool.onMouseMove(0, 200, -30, @view)
    tool.onUserText('140', @view)   # width
    tool.onUserText('100', @view)   # height
    assert_equal 4, tool.instance_variable_get(:@plan).vertex_count

    tool2 = use(BoxTool.new)
    click(tool2, 60, 10)
    tool2.onMouseMove(0, 100, -20, @view)
    tool2.onUserText('140,70', @view)
    assert_equal :height, tool2.instance_variable_get(:@state)
  end

  def test_face_tool_flow_and_bound_height
    face = @model.active_entities.to_a.grep(Sketchup::Face).last # x = 100
    @view.pick_helper.result = [face, [], Geom::Transformation.new]
    tool = use(FaceTool.new)
    tool.onUserText('5', @view)
    assert_in_delta 5.0, Settings.bound_height
    tool.onMouseMove(0, 100, -25, @view)
    tool.draw(@view)
    click(tool, 100, -25)
    assert_equal :selected, tool.instance_variable_get(:@state)
    assert_equal 4, tool.instance_variable_get(:@plan).vertex_count
    @view.pick_helper.result = nil
    click(tool, 100, -25)
    tool.onMouseMove(0, 90, -25, @view)
    click(tool, 90, -25)
    assert_equal [0.0, 90.0], xs
  end

  def test_preselection_limits_selection
    other = Sketchup::ComponentDefinition.new
    MockBuild.box(other.entities, [0, 0, 0], [10, 10, 10])
    inst = @model.active_entities.add(Sketchup::ComponentInstance.new(other, Geom::Transformation.translation(Geom::Vector3d.new(150, 0, 0))))
    inst.parent_obj = @model
    @model.selection.add(inst)
    tool = use(SelectTool.new)
    drag(tool, [60, -60], [200, 10])
    plan = tool.instance_variable_get(:@plan)
    assert_equal 0, plan.vertex_count # loose box vertices are not preselected
    assert_equal 1, plan.instance_count
    tool.draw(@view)
  end

  def test_dialog_round_trip
    Dialog.show
    dialog = Dialog.instance_variable_get(:@dialog)
    dialog.callbacks['ready'].call(nil)
    assert_match(/BS\.setState/, dialog.scripts.last)
    dialog.callbacks['setBool'].call(nil, 'filter_edges', false)
    refute Settings['filter_edges']
    dialog.callbacks['setBool'].call(nil, 'filter_edges', true)
    dialog.callbacks['setLanguage'].call(nil, 'fa')
    assert_equal 'fa', Settings.language
    assert_match(/\"language\":\"fa\"/, dialog.scripts.last)
    dialog.callbacks['setBoundHeight'].call(nil, '3')
    assert_in_delta 3.0, Settings.bound_height
    dialog.callbacks['activateTool'].call(nil, 'box')
    assert_kind_of BoxTool, @model.tools.active_tool
    Settings['language'] = 'en'
  end

  def test_selection_is_drawn_on_top_in_2d
    tool = use(SelectTool.new)
    drag(tool, [60, -60], [200, 10])
    before = @view.draw2d_calls || 0
    tool.draw(@view)
    assert_operator @view.draw2d_calls, :>, before
  end

  def test_empty_window_explains_why
    tool = use(SelectTool.new)
    drag(tool, [20, -60], [80, 10]) # crosses the middle only, no vertex inside
    assert tool.instance_variable_get(:@plan).empty?
    assert_match(/Nothing was caught/, Sketchup.status_text)
  end

  def test_errors_in_callbacks_are_reported_not_raised
    tool = use(SelectTool.new)
    tool.define_singleton_method(:select_window) { |*_a| raise 'boom' }
    UI.messages.clear
    drag(tool, [60, -60], [200, 10])
    assert_equal 1, UI.messages.size
    assert_match(/boom/, UI.messages.first)
    assert_match(/SelectTool#onLButtonUp/, UI.messages.first)
    drag(tool, [60, -60], [200, 10]) # same error again: no second message box
    assert_equal 1, UI.messages.size
    assert_equal :select, tool.instance_variable_get(:@state)
  end

  def test_diagnostics_command
    UI.messages.clear
    UI::Command.all.find { |c| c.label.start_with?('Diagnostics') }.invoke
    assert_match(/Banian Stretch .*SketchUp/m, UI.messages.last)
  end

  def test_status_texts_are_english
    [SelectTool, BoxTool, FaceTool].each do |klass|
      use(klass.new)
      assert Sketchup.status_text.ascii_only?, "#{klass} status must be English"
    end
  end
end
