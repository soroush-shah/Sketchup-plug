# frozen_string_literal: true

module Banian
  module Stretch
    # Commands, toolbar and menu.
    # Tooltips and status bar texts are English on purpose; menu labels
    # follow the language chosen in Settings.
    module Interface
      ICON_DIR = File.join(PLUGIN_ROOT, 'icons')

      TOOLS = [
        {
          id: :select, klass: 'SelectTool', icon: 'stretch_select', menu: :tool_select,
          tooltip: 'Stretch (Window / Click)',
          status: 'Drag a window or click edges/faces, then pick two points to stretch them ' \
                  'through nested groups and components.'
        },
        {
          id: :box, klass: 'BoxTool', icon: 'stretch_box', menu: :tool_box,
          tooltip: 'Stretch by Box Bounds',
          status: 'Draw a rectangle and a Bound Height; everything inside the box is stretched.'
        },
        {
          id: :face, klass: 'FaceTool', icon: 'stretch_face', menu: :tool_face,
          tooltip: 'Stretch by Face Bounds',
          status: 'Click a face; everything within the Bound Height around it is stretched.'
        }
      ].freeze

      TOGGLES = [
        {
          key: 'filter_instances', icon: 'filter_instances', menu: :filter_instances,
          tooltip: 'Filter: Groups & Components',
          status: 'When on, groups and components that are completely inside the selection move as a whole.'
        },
        {
          key: 'filter_faces', icon: 'filter_faces', menu: :filter_faces,
          tooltip: 'Filter: Faces',
          status: 'When on, faces whose vertices are all inside the selection are stretched.'
        },
        {
          key: 'filter_edges', icon: 'filter_edges', menu: :filter_edges,
          tooltip: 'Filter: Edges',
          status: 'When on, edges with both ends inside the selection are stretched.'
        },
        {
          key: 'filter_vertices', icon: 'filter_vertices', menu: :filter_vertices,
          tooltip: 'Filter: Vertices',
          status: 'When on, every vertex inside the selection is stretched (the most inclusive filter).'
        },
        {
          key: 'make_unique', icon: 'make_unique', menu: :make_unique,
          tooltip: 'Make Unique',
          status: 'When on, shared components that would be edited get their own unique definition. ' \
                  'When off they are highlighted red and every copy changes.'
        }
      ].freeze

      class << self
        def setup
          return if @setup

          @setup = true
          build_toolbar
          build_menu
          Settings.on_change { |_key, _value| refresh }
        end

        def activate_tool(id)
          spec = TOOLS.find { |s| s[:id] == id }
          return unless spec

          Sketchup.active_model.select_tool(Stretch.const_get(spec[:klass]).new)
        end

        def active_tool_class
          tools = Sketchup.active_model.tools
          return nil unless tools.respond_to?(:active_tool)

          tools.active_tool&.class
        rescue StandardError
          nil
        end

        # Repaint the view and let the active tool refresh its status text.
        def refresh
          model = Sketchup.active_model
          return unless model

          tool = model.tools.respond_to?(:active_tool) ? model.tools.active_tool : nil
          tool.send(:update_ui) if tool.is_a?(BaseTool)
          model.active_view.invalidate
          Dialog.refresh
        rescue StandardError
          nil
        end

        def icon(name)
          ext = Sketchup.platform == :platform_osx ? 'pdf' : 'svg'
          path = File.join(ICON_DIR, "#{name}.#{ext}")
          File.exist?(path) ? path : File.join(ICON_DIR, "#{name}.png")
        end

        private

        def tool_action(spec)
          [-> { activate_tool(spec[:id]) },
           lambda do
             active_tool_class == Stretch.const_get(spec[:klass]) ? MF_CHECKED : MF_UNCHECKED
           end]
        end

        def toggle_action(spec)
          [-> { Settings.toggle(spec[:key]) },
           -> { Settings[spec[:key]] ? MF_CHECKED : MF_UNCHECKED }]
        end

        def command(label, status, action, validation = nil, tooltip: nil, icon_name: nil)
          cmd = UI::Command.new(label) { action.call }
          cmd.status_bar_text = status
          cmd.set_validation_proc { validation.call } if validation
          if icon_name
            cmd.tooltip = tooltip || label
            cmd.small_icon = icon(icon_name)
            cmd.large_icon = icon(icon_name)
          end
          cmd
        end

        def settings_spec
          {
            tooltip: 'Settings & Help',
            status: 'Open Banian Stretch settings and help (English / Persian).',
            action: -> { Dialog.show }
          }
        end

        def build_toolbar
          toolbar = UI::Toolbar.new(EXTENSION_NAME)
          TOOLS.each do |spec|
            action, validation = tool_action(spec)
            toolbar.add_item(command(spec[:tooltip], spec[:status], action, validation,
                                     tooltip: spec[:tooltip], icon_name: spec[:icon]))
          end
          toolbar.add_separator
          TOGGLES.each do |spec|
            toolbar.add_separator if spec[:key] == 'make_unique'
            action, validation = toggle_action(spec)
            toolbar.add_item(command(spec[:tooltip], spec[:status], action, validation,
                                     tooltip: spec[:tooltip], icon_name: spec[:icon]))
          end
          toolbar.add_separator
          s = settings_spec
          toolbar.add_item(command(s[:tooltip], s[:status], s[:action], tooltip: s[:tooltip], icon_name: 'settings'))
          toolbar.restore if toolbar.get_last_state != TB_HIDDEN
          @toolbar = toolbar
        end

        # Menu labels follow the chosen language (applied on next start).
        def build_menu
          menu = UI.menu('Extensions').add_submenu(I18n.t(:menu_root))
          TOOLS.each do |spec|
            action, validation = tool_action(spec)
            menu.add_item(command(I18n.t(spec[:menu]), spec[:status], action, validation))
          end
          menu.add_separator
          TOGGLES.each do |spec|
            menu.add_separator if spec[:key] == 'make_unique'
            action, validation = toggle_action(spec)
            menu.add_item(command(I18n.t(spec[:menu]), spec[:status], action, validation))
          end
          menu.add_separator
          s = settings_spec
          menu.add_item(command(I18n.t(:settings), s[:status], s[:action]))
        end
      end
    end
  end
end
