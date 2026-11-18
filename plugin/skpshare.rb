# frozen_string_literal: true
# SkpShare – publish SketchUp models to your SkpShare web viewer.
require 'sketchup'
require 'extensions'

module SkpShare
  VERSION = '1.0.0'
  PLUGIN_DIR = File.join(__dir__, 'skpshare')

  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('SkpShare', File.join(PLUGIN_DIR, 'main'))
    ext.description = 'Publish models to your SkpShare website: compressed 3D viewer files, ' \
                      'scenes, tags, section planes and the original .skp – straight from SketchUp.'
    ext.version = VERSION
    ext.creator = 'SkpShare'
    ext.copyright = '2026'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
