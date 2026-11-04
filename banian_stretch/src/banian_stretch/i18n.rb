# frozen_string_literal: true

module Banian
  module Stretch
    # Translations for menus and message boxes.
    # Toolbar tooltips and status bar texts are always English (see ui.rb).
    module I18n
      STRINGS = {
        'en' => {
          menu_root: 'Banian Stretch',
          tool_select: 'Stretch (Window / Click)',
          tool_box: 'Stretch by Box Bounds',
          tool_face: 'Stretch by Face Bounds',
          filter_instances: 'Filter: Groups & Components',
          filter_faces: 'Filter: Faces',
          filter_edges: 'Filter: Edges',
          filter_vertices: 'Filter: Vertices',
          make_unique: 'Make Unique',
          settings: 'Settings && Help...',
          error_apply: 'Banian Stretch could not complete the operation:'
        },
        'fa' => {
          menu_root: "بانیان استرچ (Banian Stretch)",
          tool_select: "کشش با کادر / کلیک",
          tool_box: "کشش با جعبه (Box Bounds)",
          tool_face: "کشش با وجه (Face Bounds)",
          filter_instances: "فیلتر: گروه و کامپوننت",
          filter_faces: "فیلتر: وجه‌ها",
          filter_edges: "فیلتر: لبه‌ها",
          filter_vertices: "فیلتر: رأس‌ها",
          make_unique: "یکتاسازی (Make Unique)",
          settings: "تنظیمات و راهنما...",
          error_apply: "عملیات بانیان استرچ انجام نشد:"
        }
      }.freeze

      def self.t(key)
        lang = Settings.language
        STRINGS.fetch(lang, STRINGS['en'])[key] || STRINGS['en'][key] || key.to_s
      end
    end
  end
end
