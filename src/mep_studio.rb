# frozen_string_literal: true

# MEP Studio - mechanical / fire / plumbing / electrical modelling and clash
# detection for SketchUp (2021 - 2027, Windows & macOS). Pure Ruby, no binaries.
require 'sketchup'
require 'extensions'

module MEPStudio
  PLUGIN_ID = 'mep_studio'
  VERSION = '1.0.0'
  PLUGIN_DIR = File.join(File.dirname(__FILE__), 'mep_studio')

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('MEP Studio', File.join(PLUGIN_DIR, 'main'))
    ex.description = 'Fan coils, ducts along a path, pipes, sprinkler layout with pipe sizing, ' \
                     'cable trays, lighting layout, bill of quantities and MEP clash detection.'
    ex.version = VERSION
    ex.creator = 'Banian Studio'
    ex.copyright = '2026 Banian Studio'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end
