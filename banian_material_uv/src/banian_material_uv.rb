# encoding: UTF-8
#
# Banian Material UV - by Banian Studio
# UV / texture mapping for curved surfaces (spheres, cylinders, domes,
# arches, curved walls, free-form meshes) in SketchUp 2014 - 2027.
#
require 'sketchup.rb'
require 'extensions.rb'

module BanianStudio
  module MaterialUV
    VERSION = '1.0.0'.freeze unless defined?(VERSION)
    PLUGIN_ROOT = File.dirname(__FILE__) unless defined?(PLUGIN_ROOT)

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new('Banian Material UV', File.join(PLUGIN_ROOT, 'banian_material_uv', 'main'))
      ext.creator = 'Banian Studio'
      ext.version = VERSION
      ext.copyright = "(c) #{Time.now.year} Banian Studio"
      ext.description = 'Correct texture / UV mapping on curved surfaces: Natural unfold, ' \
                        'Quad grid, Cylindrical, Spherical, Box and Planar projection. ' \
                        'Bilingual panel (Persian / English).'
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
