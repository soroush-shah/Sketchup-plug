# frozen_string_literal: true
require 'json'
require_relative 'gltf_writer'
require_relative 'exporter'
require_relative 'manifest'
require_relative 'jobs'
require_relative 'api_client'
require_relative 'publisher'

module SkpShare
  PREFS = 'SkpShare'

  module Plugin
    module_function

    def settings
      {
        'server' => Sketchup.read_default(PREFS, 'server', ''),
        'token' => Sketchup.read_default(PREFS, 'token', ''),
        'preset' => Sketchup.read_default(PREFS, 'preset', 'balanced'),
        'edges' => Sketchup.read_default(PREFS, 'edges', true),
        'include_skp' => Sketchup.read_default(PREFS, 'include_skp', true),
        'preview' => Sketchup.read_default(PREFS, 'preview', true),
        'scene_thumbs' => Sketchup.read_default(PREFS, 'scene_thumbs', true),
        'hidden_tags' => Sketchup.read_default(PREFS, 'hidden_tags', true),
        'gltfpack' => Compressor.available?
      }
    end

    def save_settings(h)
      %w[server token preset edges include_skp preview scene_thumbs hidden_tags].each do |k|
        Sketchup.write_default(PREFS, k, h[k]) if h.key?(k)
      end
    end

    def client
      s = settings
      ApiClient.new(s['server'], s['token'], SketchupTransport.new)
    end

    def js(code)
      @dialog&.execute_script(code)
    end

    def emit(event, payload)
      js("window.skp && window.skp(#{JSON.generate(event)}, #{JSON.generate(payload)})")
    end

    def model_info
      m = Sketchup.active_model
      {
        'title' => m.title.to_s.empty? ? 'Untitled' : m.title,
        'path' => m.path,
        'size' => (!m.path.to_s.empty? && File.exist?(m.path) ? File.size(m.path) : nil),
        'scenes' => m.pages.size,
        'linked_model_id' => m.get_attribute(Publisher::ATTR_DICT, 'model_id'),
        'linked_server' => m.get_attribute(Publisher::ATTR_DICT, 'server')
      }
    end

    def show_dialog
      if @dialog&.visible?
        @dialog.bring_to_front
        return
      end
      @dialog = UI::HtmlDialog.new(dialog_title: 'SkpShare – Publish', preferences_key: 'SkpShareDialog',
                                   width: 460, height: 720, min_width: 380, min_height: 520,
                                   style: UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_file(File.join(__dir__, 'ui', 'dialog.html'))

      @dialog.add_action_callback('ready') do |_ctx|
        emit('init', settings: settings, model: model_info, version: VERSION)
      end

      @dialog.add_action_callback('saveSettings') do |_ctx, json|
        save_settings(JSON.parse(json))
        emit('settings', settings)
      end

      @dialog.add_action_callback('api') do |_ctx, json|
        req = JSON.parse(json)
        client.call(req['method'], req['path'], req['body']) do |data, err|
          emit('api', id: req['id'], data: data, error: err&.message, status: err&.status)
        end
      end

      @dialog.add_action_callback('publish') do |_ctx, json|
        req = JSON.parse(json)
        target = {
          model_id: req['model_id'], project_id: req['project_id'], new_project_name: req['new_project_name'],
          new_model_name: req['new_model_name'], note: req['note']
        }
        @publisher = Publisher.new(Sketchup.active_model, client, target, req['options'] || {}, DialogUI.new)
        @publisher.start
      end

      @dialog.add_action_callback('cancel') { |_ctx| @publisher&.cancel }
      @dialog.add_action_callback('openUrl') { |_ctx, url| UI.openURL(url) }
      @dialog.show
    end

    # Bridges Publisher callbacks to the dialog.
    class DialogUI
      def progress(stage, fraction, message)
        Sketchup.status_text = "SkpShare: #{message}"
        Plugin.emit('progress', stage: stage, fraction: fraction, message: message)
      end

      def log(msg)
        puts "SkpShare: #{msg}"
        Plugin.emit('log', msg)
      end

      def done(url, summary)
        Sketchup.status_text = 'SkpShare: published'
        Plugin.emit('done', url: url, summary: summary)
      end

      def failed(msg)
        Sketchup.status_text = "SkpShare: #{msg}"
        Plugin.emit('failed', msg)
        true
      end
    end
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Extensions').add_submenu('SkpShare')
    menu.add_item('Publish to SkpShare…') { Plugin.show_dialog }
    menu.add_item('Open my SkpShare site') do
      s = Plugin.settings['server']
      s.to_s.empty? ? Plugin.show_dialog : UI.openURL(s)
    end

    tb = UI::Toolbar.new('SkpShare')
    cmd = UI::Command.new('Publish to SkpShare') { Plugin.show_dialog }
    # Windows renders SVG toolbar icons; macOS gets PNG.
    mac = Sketchup.platform == :platform_osx
    cmd.small_icon = File.join(__dir__, 'ui', mac ? 'icon_small.png' : 'icon.svg')
    cmd.large_icon = File.join(__dir__, 'ui', mac ? 'icon.png' : 'icon.svg')
    cmd.tooltip = 'Publish to SkpShare'
    cmd.status_bar_text = 'Upload this model to your SkpShare viewer'
    tb.add_item(cmd)
    tb.restore
    file_loaded(__FILE__)
  end
end
