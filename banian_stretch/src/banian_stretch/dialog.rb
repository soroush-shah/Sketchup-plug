# frozen_string_literal: true

require 'json'

module Banian
  module Stretch
    # Settings & Help window (English / Persian).
    module Dialog
      BOOLEAN_KEYS = (Settings::FILTER_KEYS + ['make_unique']).freeze

      class << self
        def show
          if @dialog&.visible?
            @dialog.bring_to_front
            return
          end

          @dialog = create
          @dialog.show
        end

        def refresh
          push_state if @dialog&.visible?
        end

        private

        def create
          dialog = UI::HtmlDialog.new(
            dialog_title: EXTENSION_NAME,
            preferences_key: 'Banian_Stretch_Dialog',
            scrollable: true,
            resizable: true,
            width: 470,
            height: 680,
            min_width: 380,
            min_height: 420,
            style: UI::HtmlDialog::STYLE_DIALOG
          )
          dialog.set_file(File.join(PLUGIN_ROOT, 'html', 'settings.html'))

          dialog.add_action_callback('ready') { |_ctx| push_state }

          dialog.add_action_callback('setBool') do |_ctx, key, value|
            Settings[key] = value ? true : false if BOOLEAN_KEYS.include?(key)
          end

          dialog.add_action_callback('setLanguage') do |_ctx, lang|
            Settings['language'] = lang if %w[en fa].include?(lang)
            push_state
          end

          dialog.add_action_callback('setBoundHeight') do |_ctx, text|
            begin
              length = text.to_s.strip.to_l
              raise ArgumentError, 'zero' if length.zero?

              Settings['bound_height'] = length.abs.to_f
            rescue ArgumentError
              UI.beep
            end
            push_state
          end

          dialog.add_action_callback('activateTool') do |_ctx, id|
            Interface.activate_tool(id.to_s.to_sym)
          end

          dialog
        end

        def push_state
          return unless @dialog

          state = Settings.to_h.merge(
            'bound_height_text' => Sketchup.format_length(Settings.bound_height),
            'version' => VERSION,
            'mac' => Sketchup.platform == :platform_osx
          )
          @dialog.execute_script("window.BS && BS.setState(#{JSON.generate(state)});")
        end
      end
    end
  end
end
