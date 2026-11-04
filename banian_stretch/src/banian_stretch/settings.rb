# frozen_string_literal: true

module Banian
  module Stretch
    # Persistent user preferences (stored with Sketchup.write_default).
    module Settings
      SECTION = 'Banian_Stretch'

      FILTER_KEYS = %w[filter_instances filter_faces filter_edges filter_vertices].freeze

      DEFAULTS = {
        'filter_instances' => true,
        'filter_faces' => true,
        'filter_edges' => true,
        'filter_vertices' => true,
        'make_unique' => false,
        'language' => nil, # resolved from the SketchUp locale on first use
        'bound_height' => 0.5 # inches (internal SketchUp unit)
      }.freeze

      @cache = {}
      @listeners = []

      class << self
        def [](key)
          key = key.to_s
          return @cache[key] if @cache.key?(key)

          value = read(key)
          @cache[key] = value
        end

        def []=(key, value)
          key = key.to_s
          @cache[key] = value
          Sketchup.write_default(SECTION, key, value) if defined?(Sketchup.write_default)
          @listeners.each { |l| l.call(key, value) }
        end

        def toggle(key)
          self[key] = !self[key]
        end

        def filters
          {
            instances: self['filter_instances'] ? true : false,
            faces: self['filter_faces'] ? true : false,
            edges: self['filter_edges'] ? true : false,
            vertices: self['filter_vertices'] ? true : false
          }
        end

        def make_unique?
          self['make_unique'] ? true : false
        end

        def language
          lang = self['language']
          return lang if %w[en fa].include?(lang)

          locale = defined?(Sketchup.get_locale) ? Sketchup.get_locale.to_s : ''
          locale.downcase.start_with?('fa') ? 'fa' : 'en'
        end

        def bound_height
          value = self['bound_height'].to_f
          value.positive? ? value : DEFAULTS['bound_height']
        end

        def to_h
          {
            'filter_instances' => self['filter_instances'] ? true : false,
            'filter_faces' => self['filter_faces'] ? true : false,
            'filter_edges' => self['filter_edges'] ? true : false,
            'filter_vertices' => self['filter_vertices'] ? true : false,
            'make_unique' => make_unique?,
            'language' => language,
            'bound_height' => bound_height
          }
        end

        # Called with (key, value) whenever a setting changes.
        def on_change(&block)
          @listeners << block
        end

        # Test helper.
        def reset!
          @cache = {}
        end

        private

        def read(key)
          default = DEFAULTS[key]
          return default unless defined?(Sketchup.read_default)

          Sketchup.read_default(SECTION, key, default)
        end
      end
    end
  end
end
