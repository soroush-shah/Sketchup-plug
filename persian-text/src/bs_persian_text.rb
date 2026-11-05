# encoding: UTF-8
# Persian Text for SketchUp
# Write correctly shaped Persian / Arabic (RTL) text as 3D geometry, using any
# font installed on Windows. Text stays editable.

require 'sketchup.rb'
require 'extensions.rb'

module BanianStudio
  module PersianText
    PLUGIN_ID = 'bs_persian_text'.freeze
    PLUGIN_VERSION = '1.1.0'.freeze
    PLUGIN_DIR = File.join(File.dirname(__FILE__), PLUGIN_ID).freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new('Persian Text', File.join(PLUGIN_ID, 'main'))
      ext.description = 'Correctly shaped, editable Persian/Arabic 3D text using any installed Windows font. / نوشتن متن فارسی سه‌بعدی و قابل ویرایش با هر فونت نصب‌شده.'
      ext.version = PLUGIN_VERSION
      ext.creator = 'Banian Studio'
      ext.copyright = '2026 Banian Studio'
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
