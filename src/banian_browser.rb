# Banian Browser - offline model & material library manager for SketchUp.
# Copyright (c) Banian Studio. Plain, unencrypted Ruby: works on SketchUp 2017+.
require 'sketchup.rb'
require 'extensions.rb'

module BanianStudio
  module BanianBrowser
    PLUGIN_ID = 'banian_browser'.freeze
    VERSION = '1.2.0'.freeze
    PLUGIN_ROOT = File.dirname(__FILE__).dup.force_encoding('UTF-8').freeze
    PLUGIN_DIR = File.join(PLUGIN_ROOT, PLUGIN_ID).freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new('Banian Browser', File.join(PLUGIN_DIR, 'main'))
      ext.description = 'Offline library browser for models (.skp), materials (.skm) and ' \
                        'textures, with placement, material, texture and import tools.'
      ext.version = VERSION
      ext.creator = 'Banian Studio'
      ext.copyright = '(c) Banian Studio'
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
