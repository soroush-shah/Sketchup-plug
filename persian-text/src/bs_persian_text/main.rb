# encoding: UTF-8
require 'sketchup.rb'
require File.join(File.dirname(__FILE__), 'fonts')
require File.join(File.dirname(__FILE__), 'builder')
require File.join(File.dirname(__FILE__), 'dialog')

module BanianStudio
  module PersianText

    MIN_SU_VERSION = 17

    def self.supported?
      if Sketchup.version.to_i < MIN_SU_VERSION || !defined?(UI::HtmlDialog)
        UI.messagebox("Persian Text requires SketchUp 2017 or newer.\nپلاگین متن فارسی به SketchUp 2017 یا جدیدتر نیاز دارد.")
        return false
      end
      true
    end

    def self.new_text
      Dialog.open_create if supported?
    end

    def self.selected_text_instance
      sel = Sketchup.active_model.selection
      return nil unless sel.length == 1
      inst = sel.first
      return nil unless inst.is_a?(Sketchup::ComponentInstance)
      Builder.text_definition?(inst.definition) ? inst : nil
    end

    def self.edit_selected
      return unless supported?
      inst = selected_text_instance
      if inst
        Dialog.open_edit(inst)
      else
        UI.messagebox("Select a text created with Persian Text.\nیک متن ساخته‌شده با همین پلاگین را انتخاب کنید.")
      end
    end

    unless file_loaded?(__FILE__)
      icons = File.join(PLUGIN_DIR, 'icons')
      ext = Sketchup.platform == :platform_win ? 'svg' : 'pdf'
      ext = 'png' unless File.exist?(File.join(icons, "new_text.#{ext}"))

      cmd_new = UI::Command.new('New Persian Text') { new_text }
      cmd_new.tooltip = 'New Persian Text'
      cmd_new.status_bar_text = 'Create shaped Persian/Arabic 3D text with any installed font'
      cmd_new.small_icon = File.join(icons, "new_text.#{ext}")
      cmd_new.large_icon = File.join(icons, "new_text.#{ext}")

      cmd_edit = UI::Command.new('Edit Persian Text') { edit_selected }
      cmd_edit.tooltip = 'Edit Persian Text'
      cmd_edit.status_bar_text = 'Edit the selected Persian text'
      cmd_edit.small_icon = File.join(icons, "edit_text.#{ext}")
      cmd_edit.large_icon = File.join(icons, "edit_text.#{ext}")
      cmd_edit.set_validation_proc { selected_text_instance ? MF_ENABLED : MF_GRAYED }

      menu = UI.menu('Extensions').add_submenu('Persian Text')
      menu.add_item(cmd_new)
      menu.add_item(cmd_edit)

      tb = UI::Toolbar.new('Persian Text')
      tb.add_item(cmd_new)
      tb.add_item(cmd_edit)
      tb.restore

      UI.add_context_menu_handler do |cm|
        cm.add_item(cmd_edit) if selected_text_instance
      end

      file_loaded(__FILE__)
    end
  end
end
