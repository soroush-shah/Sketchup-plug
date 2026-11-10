# encoding: UTF-8
# Banian Profile Builder - SketchUp extension loader.
# Copyright (c) Banian Studio.

require 'sketchup.rb'
require 'extensions.rb'

module BanianStudio
  module ProfileBuilder
    VERSION = '1.1.0'.freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new('Banian Profile Builder', 'banian_profile_builder/main')
      ext.creator = 'Banian Studio'
      ext.version = VERSION
      ext.copyright = '2026 Banian Studio'
      ext.description = 'Fast parametric profiles, assemblies (walls, fences, railings, partitions, trims), ' \
                        'openings and instant quantities. Bilingual panel: English / Persian.'
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
