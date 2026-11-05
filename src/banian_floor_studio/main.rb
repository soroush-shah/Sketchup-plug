# Menus, toolbar and context menu. The engine is loaded lazily on first use,
# so the extension adds nothing to SketchUp's startup time.
require 'sketchup.rb'

module BanianStudio
  module FloorStudio
    PATH = File.dirname(__FILE__).freeze
    DICT_NAME = 'BanianFloorStudio'.freeze
    CORE = %w[core/geom2d core/patterns core/params core/region core/materials core/builder ui/dialog].freeze

    def self.load_core
      return if @core_loaded
      CORE.each { |f| Sketchup.require(File.join(PATH, f)) }
      @core_loaded = true
    end

    def self.min_version?
      Sketchup.version.to_i >= 17
    end

    def self.open(mode = nil)
      unless min_version?
        UI.messagebox('Banian Floor Studio requires SketchUp 2017 or newer.')
        return
      end
      load_core
      Studio.open(mode)
    end

    def self.shuffle
      load_core
      Studio.shuffle
    end

    def self.generated_selected?
      sel = Sketchup.active_model.selection
      sel.length == 1 && !sel.first.get_attribute(DICT_NAME, 'params').nil?
    rescue StandardError
      false
    end

    def self.faces_selected?
      Sketchup.active_model.selection.any? { |e| e.is_a?(Sketchup::Face) }
    end

    def self.icon(name)
      ext = Sketchup.platform == :platform_osx ? 'pdf' : 'svg'
      vec = File.join(PATH, 'icons', "#{name}.#{ext}")
      return vec if File.exist?(vec)
      File.join(PATH, 'icons', "#{name}_24.png")
    end

    def self.command(title, tip, icon_name, &blk)
      c = UI::Command.new(title, &blk)
      c.tooltip = title
      c.status_bar_text = tip
      if icon_name
        small = File.join(PATH, 'icons', "#{icon_name}_16.png")
        c.small_icon = Sketchup.version.to_i >= 16 ? icon(icon_name) : small
        c.large_icon = Sketchup.version.to_i >= 16 ? icon(icon_name) : File.join(PATH, 'icons', "#{icon_name}_24.png")
      end
      c
    end

    unless file_loaded?(__FILE__)
      cmd_studio = command('Floor Studio', 'Open Banian Floor Studio', 'studio') { open }
      cmd_tiles = command('Generate 3D Tiles', 'Generate 3D tiles on the selected faces', 'tiles') { open('3d') }
      cmd_divide = command('Divide Face', 'Split the selected faces into a pattern (no 3D)', 'divide') { open('divide') }
      cmd_texture = command('Pattern Texture', 'Create a seamless pattern texture for the selected faces', 'texture') { open('texture') }
      cmd_edit = command('Edit Selected Layout', 'Edit the selected Floor Studio layout', 'edit') { open('edit') }
      cmd_edit.set_validation_proc { generated_selected? ? MF_ENABLED : MF_GRAYED }
      cmd_shuffle = command('Shuffle Randomness', 'Re-generate the selected layout with a new random seed', 'shuffle') { shuffle }
      cmd_shuffle.set_validation_proc { generated_selected? ? MF_ENABLED : MF_GRAYED }

      menu = UI.menu('Extensions').add_submenu('Banian Floor Studio')
      menu.add_item(cmd_studio)
      menu.add_separator
      menu.add_item(cmd_tiles)
      menu.add_item(cmd_divide)
      menu.add_item(cmd_texture)
      menu.add_separator
      menu.add_item(cmd_edit)
      menu.add_item(cmd_shuffle)
      menu.add_separator
      menu.add_item('About Banian Floor Studio') do
        UI.messagebox("Banian Floor Studio #{VERSION}\nTiles, parquet & pattern generator for SketchUp.\n(c) Banian Studio")
      end

      tb = UI::Toolbar.new('Banian Floor Studio')
      [cmd_studio, cmd_tiles, cmd_divide, cmd_texture, cmd_edit, cmd_shuffle].each { |c| tb.add_item(c) }
      if tb.get_last_state == TB_NEVER_SHOWN
        tb.show
      else
        tb.restore
      end

      UI.add_context_menu_handler do |cm|
        if generated_selected?
          sub = cm.add_submenu('Banian Floor Studio')
          sub.add_item(cmd_edit)
          sub.add_item(cmd_shuffle)
        elsif faces_selected?
          sub = cm.add_submenu('Banian Floor Studio')
          sub.add_item(cmd_tiles)
          sub.add_item(cmd_divide)
          sub.add_item(cmd_texture)
        end
      end
      file_loaded(__FILE__)
    end
  end
end
