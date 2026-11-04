# frozen_string_literal: true

# Banian Stretch - stretch geometry through nested groups and components.
# Loader file: registers the extension with SketchUp.

require 'sketchup.rb'
require 'extensions.rb'

module Banian
  module Stretch
    EXTENSION_NAME = 'Banian Stretch'
    VERSION = '1.0.0'

    file = __FILE__.dup
    file.force_encoding('UTF-8') if file.respond_to?(:force_encoding)
    PLUGIN_ROOT = File.join(File.dirname(file), 'banian_stretch').freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(EXTENSION_NAME, File.join(PLUGIN_ROOT, 'main'))
      ext.description = 'Stretch geometry with Move mechanics, straight through ' \
                        'nested groups and components. Window, Box Bounds and ' \
                        'Face Bounds selection, entity filters and Make Unique.'
      ext.version = VERSION
      ext.creator = 'Banian Studio'
      ext.copyright = "© 2026 Banian Studio"
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
