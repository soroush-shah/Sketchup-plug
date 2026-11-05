# Banian Floor Studio - floor / wall tile & pattern generator for SketchUp.
# Loader: registers the extension only (no work at startup).
require 'sketchup.rb'
require 'extensions.rb'

module BanianStudio
  module FloorStudio
    PLUGIN_ID = 'banian_floor_studio'.freeze
    VERSION = '1.1.0'.freeze

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new('Banian Floor Studio', File.join(PLUGIN_ID, 'main'))
      ex.description = 'Generate 3D floor & wall tiles, parquet, herringbone, chevron, hexagon, ' \
                       'stone and siding patterns - or simply divide faces into a pattern.'
      ex.version = VERSION
      ex.creator = 'Banian Studio'
      ex.copyright = "(c) #{Time.now.year} Banian Studio"
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
