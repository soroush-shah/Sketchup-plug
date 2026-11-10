# encoding: UTF-8
# Banian Profile Builder - entry point: menus, toolbar, observers.

require 'sketchup.rb'

module BanianStudio
  module ProfileBuilder
    dir = File.dirname(__FILE__)
    dir = dir.dup.force_encoding('UTF-8') if dir.respond_to?(:force_encoding)
    PLUGIN_DIR = dir unless defined?(PLUGIN_DIR)

    %w[core/vec core/profiles core/path core/sweep core/assembly core/presets
       su/library su/builder su/quantities su/controller su/editing
       tools/draw_tool tools/extend_tool tools/pick_tools tools/path_edit_tool].each { |f| require File.join(PLUGIN_DIR, f) }

    class SelObserver < Sketchup::SelectionObserver
      def onSelectionBulkChange(_s)
        Controller.selection_changed
      end

      def onSelectionCleared(_s)
        Controller.selection_changed
      end

      def onSelectionAdded(_s, _e)
        Controller.selection_changed
      end

      def onSelectionRemoved(_s, _e)
        Controller.selection_changed
      end
    end

    class AppObs < Sketchup::AppObserver
      def onNewModel(model)
        ProfileBuilder.attach(model)
      end

      def onOpenModel(model)
        ProfileBuilder.attach(model)
      end

      def onActivateModel(model)
        ProfileBuilder.attach(model)
        Controller.selection_changed
      end
    end

    def self.attach(model)
      @attached ||= {}
      return if @attached[model.object_id]
      @sel_obs ||= SelObserver.new
      model.selection.add_observer(@sel_obs)
      @attached[model.object_id] = true
    end

    def self.icon(name)
      vector = File.join(PLUGIN_DIR, 'icons', "#{name}.svg")
      return [vector, vector] if Sketchup.platform != :platform_osx && File.exist?(vector)
      [File.join(PLUGIN_DIR, 'icons', "#{name}_24.png"), File.join(PLUGIN_DIR, 'icons', "#{name}_32.png")]
    end

    def self.command(title, icon_name, tip, &block)
      cmd = UI::Command.new(title, &block)
      small, large = icon(icon_name)
      cmd.small_icon = small
      cmd.large_icon = large
      cmd.tooltip = title
      cmd.status_bar_text = tip
      cmd
    end

    def self.has_pb_selection
      Sketchup.active_model.selection.any? { |e| Builder.pb?(e) } ? MF_ENABLED : MF_GRAYED
    end

    unless file_loaded?(__FILE__)
      cmds = {}
      cmds[:panel] = command('Banian Panel', 'panel', 'Open the Banian Profile Builder panel (profiles, assemblies, quantities).') { Controller.show }
      cmds[:draw] = command('Draw Profile Path', 'draw', 'Draw a path and build the current profile or assembly along it.') do
        Sketchup.active_model.select_tool(DrawTool.new)
      end
      cmds[:build] = command('Build on Selection', 'build', 'Build the current profile or assembly on selected edges, curves or faces.') do
        Controller.build_on_selection
      end
      cmds[:extend] = command('Extend / Trim', 'extend', 'Extend or shorten a Banian object. Type 3000s to set the total length.') do
        Sketchup.active_model.select_tool(ExtendTool.new)
      end
      cmds[:rotate] = command('Rotate Profile 90°', 'rotate', 'Rotate the profile of selected Banian members by 90 degrees.') { Controller.rotate_selected }
      cmds[:flip] = command('Flip Side', 'flip', 'Mirror selected Banian objects to the other side of their path.') { Controller.flip_selected }
      cmds[:qty] = command('Quantities Report', 'quantities', 'Open the instant quantity / cost report.') do
        Controller.show
        Controller.send_js('type' => 'tab', 'tab' => 'qty')
      end
      cmds[:face] = command('Add My Profile (Pick Face)', 'face', 'Click any face (or use the selected one) to save it as your own profile.') { Controller.pick_face }
      cmds[:path] = command('Edit Path', 'edit_path', 'Move, add or delete path points directly on a Banian object.') do
        Sketchup.active_model.select_tool(PathEditTool.new)
      end
      cmds[:match] = command('Eyedropper (Reuse Object)', 'match', 'Click a Banian object to reuse its profile / assembly, then draw a new path.') do
        Sketchup.active_model.select_tool(MatchTool.new)
      end
      cmds[:shape] = command('Edit Profile Shape', 'shape', 'Edit the cross-section of the selected profile with SketchUp tools; all users of the profile update.') do
        Controller.show
        Controller.begin_shape_edit
      end
      cmds[:continue] = command('Build Same on Selected Path', 'build', 'Repeat the selected Banian object on the selected edges / faces.') { Controller.continue_on_selected_path }
      cmds[:replace] = command('Move Object to Selected Path', 'edit_path', 'Rebuild the selected Banian object on the selected edges / face.') { Controller.replace_path }
      [:rotate, :flip, :shape].each { |k| cmds[k].set_validation_proc { has_pb_selection } }

      menu = UI.menu('Extensions').add_submenu('Banian Profile Builder')
      [:panel, :draw, :build, :match].each { |k| menu.add_item(cmds[k]) }
      menu.add_separator
      [:path, :extend, :rotate, :flip, :shape].each { |k| menu.add_item(cmds[k]) }
      menu.add_separator
      [:face, :continue, :replace].each { |k| menu.add_item(cmds[k]) }
      menu.add_separator
      menu.add_item(cmds[:qty])
      menu.add_item('User Guide') do
        Controller.show
        Controller.send_js('type' => 'tab', 'tab' => 'guide')
      end
      menu.add_item('About') do
        UI.messagebox("Banian Profile Builder #{VERSION}\nBanian Studio\n\nFast parametric profiles, assemblies and quantities.")
      end

      tb = UI::Toolbar.new('Banian Profile Builder')
      [:panel, :draw, :build, :match, :path, :extend, :rotate, :flip, :face, :qty].each { |k| tb.add_item(cmds[k]) }
      tb.restore if tb.get_last_state != TB_HIDDEN

      UI.add_context_menu_handler do |cm|
        sel = Sketchup.active_model.selection
        has_pb = sel.any? { |e| Builder.pb?(e) }
        has_path = sel.any? { |e| e.is_a?(Sketchup::Edge) || e.is_a?(Sketchup::Face) }
        next unless has_pb || has_path
        sub = cm.add_submenu('Banian Profile Builder')
        if has_pb
          sub.add_item('Edit in Panel') { Controller.show }
          [:path, :extend, :rotate, :flip].each { |k| sub.add_item(cmds[k]) }
          sub.add_item(cmds[:shape]) if sel.any? { |e| Builder.kind(e) == 'member' }
          sub.add_item(cmds[:match])
        end
        if has_path && has_pb
          sub.add_separator
          sub.add_item(cmds[:continue])
          sub.add_item(cmds[:replace])
        elsif has_path
          sub.add_item(cmds[:build])
          sub.add_item(cmds[:face]) if sel.grep(Sketchup::Face).size == 1
        end
      end

      Sketchup.add_observer(AppObs.new)
      attach(Sketchup.active_model) if Sketchup.active_model
      file_loaded(__FILE__)
    end
  end
end
