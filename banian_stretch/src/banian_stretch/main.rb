# frozen_string_literal: true

require 'sketchup.rb'

module Banian
  module Stretch
    %w[
      settings
      i18n
      error_reporter
      region
      plan
      applier
      tools/base_tool
      tools/select_tool
      tools/box_tool
      tools/face_tool
      dialog
      ui
    ].each { |file| Sketchup.require(File.join(PLUGIN_ROOT, file)) }

    unless file_loaded?(__FILE__)
      Interface.setup
      file_loaded(__FILE__)
    end
  end
end
