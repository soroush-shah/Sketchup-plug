# encoding: UTF-8
require 'json'

module BanianStudio
  module MaterialUV
    module Dialog
      @dlg = nil
      @thumbs = {}
      @observer = nil
      @observed_sel = nil
      @timer = nil
      @last_result = nil

      def self.html_dialog?
        defined?(UI::HtmlDialog) ? true : false
      end

      def self.visible?
        @dlg && @dlg.visible?
      end

      def self.show
        if visible?
          @dlg.bring_to_front
          push_state
          return
        end
        @dlg = html_dialog? ? build_html : build_web
        attach_observer
        if html_dialog?
          @dlg.show
        elsif RUBY_PLATFORM =~ /darwin/
          @dlg.show_modal
        else
          @dlg.show
        end
      end

      def self.build_html
        d = UI::HtmlDialog.new(
          :dialog_title => 'Banian Material UV',
          :preferences_key => 'BanianMaterialUV_Dialog',
          :scrollable => true, :resizable => true,
          :width => 420, :height => 760, :left => 120, :top => 90,
          :min_width => 360, :min_height => 420,
          :style => UI::HtmlDialog::STYLE_DIALOG
        )
        d.set_file(File.join(PLUGIN_DIR, 'ui', 'dialog.html'))
        callbacks.each do |name|
          d.add_action_callback(name) { |_ctx, payload| handle(name, payload.to_s) }
        end
        d.set_on_closed { detach_observer } if d.respond_to?(:set_on_closed)
        d
      end

      def self.build_web
        d = UI::WebDialog.new('Banian Material UV', true, 'BanianMaterialUV_WebDialog', 420, 760, 120, 90, true)
        d.set_file(File.join(PLUGIN_DIR, 'ui', 'dialog.html'))
        callbacks.each do |name|
          d.add_action_callback(name) do |dlg, _param|
            handle(name, dlg.get_element_value('bmuv_payload').to_s)
          end
        end
        d.set_on_close { detach_observer }
        d
      end

      def self.callbacks
        %w[ready apply reset detect tool browse current sample refresh save close about]
      end

      def self.parse(payload)
        return {} if payload.nil? || payload.empty?
        h = JSON.parse(payload)
        h.is_a?(Hash) ? h : {}
      rescue StandardError
        {}
      end

      def self.handle(name, payload)
        data = parse(payload)
        Settings.update(data['settings']) if data['settings'].is_a?(Hash)
        model = Sketchup.active_model
        case name
        when 'ready', 'refresh'
          push_state
        when 'save'
          nil
        when 'apply'
          res = MaterialUV.apply_selection({}, true)
          @last_result = if res
                           { 'ok' => true, 'faces' => res[:faces], 'skipped' => res[:skipped],
                             'modes' => res[:modes], 'no_texture' => res[:no_texture] }
                         else
                           { 'ok' => false, 'error' => error_code(model) }
                         end
          push_state
        when 'reset'
          n = MaterialUV.reset_selection(true)
          @last_result = n > 0 ? { 'ok' => true, 'reset' => n } : { 'ok' => false, 'error' => 'nothing' }
          push_state
        when 'detect'
          targets = MaterialUV.selection_targets
          modes = Mapper.detect(targets)
          @last_result = modes.empty? ? { 'ok' => false, 'error' => 'nothing' } : { 'ok' => true, 'detected' => modes }
          push_state
        when 'tool'
          MaterialUV.activate_tool
        when 'browse'
          browse_texture(model)
          push_state
        when 'current'
          m = model.materials.current
          if m
            Settings.update('material' => m.name, 'mat_source' => 'chosen')
          end
          push_state
        when 'sample'
          f = model.selection.grep(Sketchup::Face).first
          m = f ? (f.material || f.back_material) : nil
          if m.nil?
            inst = model.selection.find { |e| e.respond_to?(:material) && !e.is_a?(Sketchup::Face) && e.material }
            m = inst.material if inst
          end
          if m
            Settings.update('material' => m.name, 'mat_source' => 'chosen')
          else
            @last_result = { 'ok' => false, 'error' => 'no_sample' }
          end
          push_state
        when 'about'
          MaterialUV.about
        when 'close'
          @dlg.close if @dlg
        end
      rescue StandardError => e
        puts "Banian Material UV dialog error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end

      def self.error_code(model)
        return 'nothing' if MaterialUV.selection_targets.empty?
        'no_material'
      end

      def self.browse_texture(model)
        path = UI.openpanel('Choose texture image', '', 'Images|*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff;*.tga;*.webp||')
        return unless path && File.exist?(path)
        name = File.basename(path, '.*')
        model.start_operation('Banian Material UV - New Material', true)
        mat = model.materials.add(name)
        mat.texture = path
        model.commit_operation
        Settings.update('material' => mat.name, 'mat_source' => 'chosen')
        model.materials.current = mat rescue nil
      end

      # ------------------------------------------------------------------
      # State
      # ------------------------------------------------------------------
      def self.thumb(mat)
        return nil unless mat.texture && mat.respond_to?(:write_thumbnail)
        key = "#{mat.name}|#{mat.texture.filename}|#{mat.texture.image_width}"
        return @thumbs[key] if @thumbs.key?(key)
        dir = Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir : (ENV['TMPDIR'] || ENV['TEMP'] || ENV['TMP'] || '.')
        path = File.join(dir, "bmuv_thumb_#{rand(1_000_000)}.png")
        data = nil
        begin
          if mat.write_thumbnail(path, 64) && File.exist?(path)
            bin = File.open(path, 'rb') { |f| f.read }
            data = 'data:image/png;base64,' + [bin].pack('m0')
          end
        rescue StandardError
          data = nil
        ensure
          File.delete(path) if File.exist?(path) rescue nil
        end
        @thumbs[key] = data
      end

      def self.materials_info(model)
        f = Mapper.unit_factor(model)
        list = []
        model.materials.each do |m|
          c = m.color
          item = {
            'name' => m.name,
            'label' => (m.respond_to?(:display_name) ? m.display_name : m.name),
            'color' => format('#%02x%02x%02x', c.red, c.green, c.blue),
            'textured' => !m.texture.nil?
          }
          if m.texture
            item['tw'] = (m.texture.width.to_f / f).round(3)
            item['th'] = (m.texture.height.to_f / f).round(3)
            item['thumb'] = thumb(m)
          end
          list << item
        end
        list.sort_by { |x| x['label'].to_s.downcase }
      end

      def self.selection_info(model)
        sel = model.selection
        faces = 0; objects = 0
        sel.each do |e|
          faces += 1 if e.is_a?(Sketchup::Face)
          objects += 1 if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        end
        total = sel.length > 0 ? MaterialUV.selection_targets.size : 0
        { 'faces' => faces, 'objects' => objects, 'total' => total }
      end

      def self.state
        model = Sketchup.active_model
        cur = model.materials.current
        {
          'version' => VERSION,
          'settings' => Settings.get,
          'materials' => materials_info(model),
          'current' => cur ? cur.name : nil,
          'selection' => selection_info(model),
          'units' => Mapper.unit_name(model),
          'su' => Sketchup.version.to_i,
          'result' => @last_result
        }
      end

      def self.push_state
        return unless @dlg
        js = "BMUV.receive(#{js_json(state)});"
        @last_result = nil
        @dlg.execute_script(js)
      rescue StandardError => e
        puts "Banian Material UV: #{e.message}"
      end

      def self.push_selection
        return unless visible?
        js = "BMUV.selection(#{js_json(selection_info(Sketchup.active_model))});"
        @dlg.execute_script(js)
      rescue StandardError
        nil
      end

      # JSON safe for execute_script (ASCII only)
      def self.js_json(obj)
        s = JSON.generate(obj)
        s = s.encode('UTF-8', :invalid => :replace, :undef => :replace)
        out = ''
        s.each_char do |ch|
          o = ch.ord
          if o > 126 || ch == " " || ch == " "
            if o > 0xFFFF
              o -= 0x10000
              out << format('\\u%04x\\u%04x', 0xD800 + (o >> 10), 0xDC00 + (o & 0x3FF))
            else
              out << format('\\u%04x', o)
            end
          elsif ch == '<'
            out << '\\u003c'
          else
            out << ch
          end
        end
        out
      end

      # ------------------------------------------------------------------
      # Selection observer (keeps the face counter live)
      # ------------------------------------------------------------------
      class SelObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(_sel) Dialog.schedule_selection end
        def onSelectionCleared(_sel) Dialog.schedule_selection end
        def onSelectionAdded(*_a) Dialog.schedule_selection end
        def onSelectionRemoved(*_a) Dialog.schedule_selection end
      end

      def self.schedule_selection
        return if @timer
        @timer = UI.start_timer(0.25, false) do
          @timer = nil
          push_selection
        end
      end

      def self.attach_observer
        detach_observer
        @observer ||= SelObserver.new
        @observed_sel = Sketchup.active_model.selection
        @observed_sel.add_observer(@observer)
      rescue StandardError
        nil
      end

      def self.detach_observer
        @observed_sel.remove_observer(@observer) if @observed_sel && @observer
        @observed_sel = nil
      rescue StandardError
        nil
      end

      def self.notify_material_picked
        push_state if visible?
      end
    end
  end
end
