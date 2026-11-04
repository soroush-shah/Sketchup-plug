require 'json'
require 'fileutils'
require 'digest/md5'
require 'zlib'

module BanianStudio
  module BanianBrowser
    DICT = 'BanianBrowser'.freeze

    %w[
      util settings i18n zip_reader thumbnails library
      model_ops material_ops texture_tools path_tools importer
      tools/tool_base tools/material_picker tools/material_bucket tools/replace_texture_tool
      tools/fit_place_tool tools/surface_place_tool tools/place_tool
      dialog menu
    ].each { |f| Sketchup.require(File.join(PLUGIN_DIR, f)) }

    Menu.install unless file_loaded?(__FILE__)
    file_loaded(__FILE__)
  end
end
