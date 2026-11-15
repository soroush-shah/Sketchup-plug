# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module BanianStudio
  module MaterialUV
    PLUGIN_DIR = File.dirname(__FILE__) unless defined?(PLUGIN_DIR)

    Sketchup.require File.join(PLUGIN_DIR, 'core')
    Sketchup.require File.join(PLUGIN_DIR, 'settings')
    Sketchup.require File.join(PLUGIN_DIR, 'mapper')
    Sketchup.require File.join(PLUGIN_DIR, 'dialog')
    Sketchup.require File.join(PLUGIN_DIR, 'paint_tool')

    MODES = %w[auto natural quad cylindrical spherical box planar]

    # ------------------------------------------------------------------
    # Shared actions
    # ------------------------------------------------------------------
    def self.chosen_material(model, s)
      case s['mat_source']
      when 'existing' then [nil, true]
      when 'current'
        m = model.materials.current
        [m, !m.nil?]
      else
        name = s['material'].to_s
        m = name.empty? ? nil : model.materials[name]
        [m, !m.nil?]
      end
    end

    def self.run(targets, overrides = {}, start_target = nil, silent = false)
      model = Sketchup.active_model
      s = Settings.get.merge(overrides)
      if targets.empty?
        UI.messagebox(T.t('nothing')) unless silent
        return nil
      end
      mat, ok = chosen_material(model, s)
      unless ok
        UI.messagebox(T.t('no_material')) unless silent
        return nil
      end
      res = nil
      model.start_operation('Banian Material UV', true)
      begin
        res = Mapper.apply(model, targets, s, mat, start_target)
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        puts "Banian Material UV error: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        UI.messagebox("Banian Material UV error:\n#{e.message}") unless silent
        return nil
      end
      Sketchup.status_text = T.t('done', res[:faces])
      res
    end

    def self.selection_targets(s = Settings.get)
      model = Sketchup.active_model
      Mapper.collect(model, model.selection.to_a, :expand => s['expand'] == true)
    end

    def self.apply_selection(overrides = {}, silent = false)
      s = Settings.get.merge(overrides)
      run(selection_targets(s), overrides, nil, silent)
    end

    def self.reset_selection(silent = false)
      model = Sketchup.active_model
      targets = selection_targets
      if targets.empty?
        UI.messagebox(T.t('nothing')) unless silent
        return 0
      end
      model.start_operation('Banian Material UV Reset', true)
      n = Mapper.reset(model, targets, Settings.get['sides'] || 'front')
      model.commit_operation
      Sketchup.status_text = T.t('reset', n)
      n
    end

    def self.activate_tool
      Sketchup.active_model.select_tool(PaintTool.new)
    end

    def self.about
      UI.messagebox(T.t('about', VERSION))
    end

    def self.icon(name)
      dir = File.join(PLUGIN_DIR, 'icons')
      vec = Sketchup.version.to_i >= 16 && !(RUBY_PLATFORM =~ /darwin/)
      svg = File.join(dir, "#{name}.svg")
      return [svg, svg] if vec && File.exist?(svg)
      [File.join(dir, "#{name}_16.png"), File.join(dir, "#{name}_24.png")]
    end

    def self.make_cmd(title, tip, icon_name = nil, &blk)
      cmd = UI::Command.new(title) { blk.call }
      cmd.tooltip = title
      cmd.status_bar_text = tip
      if icon_name
        small, large = icon(icon_name)
        cmd.small_icon = small
        cmd.large_icon = large
      end
      cmd
    end

    def self.has_paintable_selection?
      Sketchup.active_model.selection.any? do |e|
        e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end
    end

    # ------------------------------------------------------------------
    # Menus / toolbar (English)
    # ------------------------------------------------------------------
    unless file_loaded?(__FILE__)
      cmd_panel = make_cmd('Banian Material UV Panel', 'Open the Banian Material UV panel', 'panel') { Dialog.show }
      cmd_tool = make_cmd('UV Paint Tool', 'Click surfaces to paint and map the texture', 'tool') { activate_tool }
      cmd_apply = make_cmd('Apply UV to Selection', 'Map the texture on the selection with the current settings', 'apply') { apply_selection }
      cmd_reset = make_cmd('Reset Texture Position', 'Restore default texture placement on the selection', 'reset') { reset_selection }

      quick = [
        ['Auto (Smart Detect)', 'auto'],
        ['Natural / Unfold', 'natural'],
        ['Quad Grid (follow mesh)', 'quad'],
        ['Cylindrical', 'cylindrical'],
        ['Spherical', 'spherical'],
        ['Box / Tri-Planar', 'box'],
        ['Planar Projection', 'planar']
      ]

      menu = UI.menu('Extensions').add_submenu('Banian Material UV')
      menu.add_item(cmd_panel)
      menu.add_item(cmd_tool)
      menu.add_separator
      menu.add_item(cmd_apply)
      qm = menu.add_submenu('Quick Apply')
      quick.each { |label, mode| qm.add_item(label) { apply_selection('mode' => mode) } }
      menu.add_item(cmd_reset)
      menu.add_separator
      menu.add_item('About Banian Material UV') { about }

      UI.add_context_menu_handler do |cm|
        next unless has_paintable_selection?
        sub = cm.add_submenu('Banian Material UV')
        sub.add_item('Open Panel...') { Dialog.show }
        sub.add_item('Apply UV (current settings)') { apply_selection }
        sub.add_separator
        quick.each { |label, mode| sub.add_item(label) { apply_selection('mode' => mode) } }
        sub.add_separator
        sub.add_item('Reset Texture Position') { reset_selection }
      end

      tb = UI::Toolbar.new('Banian Material UV')
      tb.add_item(cmd_panel)
      tb.add_item(cmd_tool)
      tb.add_item(cmd_apply)
      tb.add_item(cmd_reset)
      tb.restore if tb.get_last_state != 0

      file_loaded(__FILE__)
    end
  end
end
