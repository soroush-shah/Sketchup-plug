# encoding: UTF-8
# The HtmlDialog that hosts the editor UI and the text engine.

require 'json'

module BanianStudio
  module PersianText
    class Dialog

      FONT_CHUNK = 400_000

      class << self
        # Opens the dialog for creating a new text.
        def open_create
          dlg = instance
          dlg.configure(:create, nil)
          dlg.show
        end

        # Opens the dialog for editing an existing text instance.
        def open_edit(inst)
          params = Builder.params_of(inst.definition)
          unless params
            UI.messagebox('این آبجکت با پلاگین متن فارسی ساخته نشده است.')
            return
          end
          dlg = instance
          dlg.configure(:edit, inst)
          dlg.show
        end

        def instance
          @instance ||= new
        end
      end

      def initialize
        @mode = :create
        @target = nil
        @inbox = {}
        @dialog = nil
      end

      def configure(mode, target)
        @mode = mode
        @target = target
        push_mode if visible?
      end

      def visible?
        @dialog && @dialog.visible?
      end

      def show
        if visible?
          @dialog.bring_to_front
          return
        end
        @dialog = build_dialog
        @dialog.show
      end

      # -----------------------------------------------------------------------
      private

      def build_dialog
        dlg = UI::HtmlDialog.new(
          dialog_title: 'متن فارسی',
          preferences_key: 'BanianStudio_PersianText_v1',
          scrollable: true,
          resizable: true,
          width: 980,
          height: 720,
          min_width: 720,
          min_height: 520,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        dlg.set_file(File.join(PLUGIN_DIR, 'ui', 'index.html'))
        dlg.add_action_callback('msg') do |_ctx, id, idx, total, chunk|
          receive(id.to_s, idx.to_i, total.to_i, chunk.to_s)
        end
        dlg.set_on_closed { @dialog = nil } if dlg.respond_to?(:set_on_closed)
        dlg
      end

      def js(code)
        return unless @dialog
        @dialog.execute_script(code)
      end

      def send_js(fn, data)
        json = JSON.generate(data).gsub(" ", ' ').gsub(" ", ' ')
        js("PT.#{fn}(#{json});")
      end

      # Messages from JS may be split into several chunks.
      def receive(id, idx, total, chunk)
        parts = (@inbox[id] ||= Array.new(total))
        parts[idx] = chunk
        return if parts.any?(&:nil?)
        @inbox.delete(id)
        msg = JSON.parse(parts.join)
        dispatch(msg['action'].to_s, msg['data'] || {}, msg['req'])
      rescue StandardError => e
        report_error(e)
      end

      def dispatch(action, data, req)
        case action
        when 'ready' then on_ready
        when 'getFont' then on_get_font(data, req)
        when 'lengths' then reply(req, parse_lengths(data))
        when 'build' then on_build(data)
        when 'saveSettings' then save_settings(data)
        when 'rescanFonts' then send_js('onFonts', fonts_payload(true))
        when 'browseFont' then on_browse_font
        when 'pickSelection' then on_pick_selection
        when 'close' then @dialog.close if @dialog
        end
      end

      def reply(req, data)
        send_js('onReply', 'req' => req, 'data' => data)
      end

      def report_error(e)
        msg = "#{e.class}: #{e.message}"
        puts "[PersianText] #{msg}\n#{(e.backtrace || []).first(6).join("\n")}"
        send_js('onError', 'message' => msg)
      end

      # -----------------------------------------------------------------------
      # Handlers

      def on_ready
        model = Sketchup.active_model
        units = model.options['UnitsOptions']['LengthUnit'] rescue 2
        payload = {
          'version' => PLUGIN_VERSION,
          'suVersion' => Sketchup.version.to_i,
          'units' => units,
          'settings' => load_settings,
          'materials' => materials_payload
        }
        send_js('onInit', payload)
        send_js('onFonts', fonts_payload(false))
        push_mode
      end

      def push_mode
        data = { 'mode' => @mode.to_s, 'materials' => materials_payload }
        if @mode == :edit && @target && @target.valid?
          data['params'] = Builder.params_of(@target.definition)
          data['shared'] = @target.definition.count_used_instances > 1
        end
        send_js('onMode', data)
      end

      def fonts_payload(force)
        list = Fonts.list(force)
        list += custom_fonts
        { 'fonts' => list }
      end

      def materials_payload
        Sketchup.active_model.materials.map do |m|
          c = m.color
          { 'name' => m.name, 'display' => (m.respond_to?(:display_name) ? m.display_name : m.name),
            'color' => format('#%02x%02x%02x', c.red, c.green, c.blue) }
        end
      rescue StandardError
        []
      end

      def on_get_font(data, req)
        path = data['path'].to_s
        unless File.exist?(path)
          reply(req, 'error' => "فایل فونت پیدا نشد:\n#{path}")
          return
        end
        b64 = [File.binread(path)].pack('m0')
        n = (b64.length.to_f / FONT_CHUNK).ceil
        n = 1 if n < 1
        js("PT.fontBegin(#{req.to_i}, #{n});")
        n.times do |i|
          js("PT.fontChunk(#{req.to_i}, #{i}, '#{b64[i * FONT_CHUNK, FONT_CHUNK]}');")
        end
        js("PT.fontEnd(#{req.to_i});")
      end

      def parse_lengths(data)
        out = {}
        data.each do |k, v|
          s = v.to_s.strip.tr('۰۱۲۳۴۵۶۷۸۹٫', '0123456789.')
          if s.empty?
            out[k] = nil
            next
          end
          begin
            out[k] = s.to_l.to_f
          rescue StandardError
            out[k] = 'error'
          end
        end
        out
      end

      def on_build(data)
        params = data['params'] || {}
        polys = data['polys'] || []
        if polys.empty?
          UI.messagebox('متنی برای ساخت وجود ندارد.')
          return
        end
        lengths = parse_lengths('extrude' => params['extrude'], 'zOffset' => params['zOffset'])
        params['extrudeIn'] = lengths['extrude'].is_a?(Float) ? lengths['extrude'] : 0.0
        params['zOffsetIn'] = lengths['zOffset'].is_a?(Float) ? lengths['zOffset'] : 0.0
        model = Sketchup.active_model

        if @mode == :edit
          unless @target && @target.valid?
            UI.messagebox('آبجکت متن دیگر در مدل وجود ندارد.')
            return
          end
          model.start_operation('ویرایش متن فارسی', true)
          begin
            @target.make_unique if @target.definition.count_used_instances > 1 && !data['editAll']
            Builder.fill(@target.definition, params, polys)
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            raise e
          end
          @dialog.close if @dialog && !params['keepOpen']
        else
          model.start_operation('متن فارسی', true)
          begin
            defn = Builder.create_definition(model, params, polys)
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            raise e
          end
          @dialog.close if @dialog && !params['keepOpen']
          model.place_component(defn, false)
        end
        save_settings(params)
      end

      def on_browse_font
        path = UI.openpanel('انتخاب فایل فونت', '', 'Font Files|*.ttf;*.otf;*.ttc;*.otc||')
        return unless path
        faces = Fonts.parse_file(path).map { |f| f.merge('path' => path, 'custom' => true) }
        if faces.empty?
          UI.messagebox('این فایل فونت قابل خواندن نیست.')
          return
        end
        list = (custom_fonts.reject { |f| f['path'] == path } + faces)
        write_json('custom_fonts.json', list)
        send_js('onFonts', fonts_payload(false).merge('select' => faces.first))
      end

      def on_pick_selection
        sel = Sketchup.active_model.selection
        inst = sel.grep(Sketchup::ComponentInstance).find { |i| Builder.text_definition?(i.definition) }
        if inst
          @mode = :edit
          @target = inst
          push_mode
        else
          send_js('onError', 'message' => 'یک متن فارسی (ساخته‌شده با همین پلاگین) را انتخاب کنید.')
        end
      end

      # -----------------------------------------------------------------------
      # Persistence

      def custom_fonts
        list = read_json('custom_fonts.json')
        list.is_a?(Array) ? list.select { |f| File.exist?(f['path'].to_s) } : []
      end

      def load_settings
        s = read_json('settings.json')
        s.is_a?(Hash) ? s : {}
      end

      def save_settings(params)
        keep = params.reject { |k, _| %w[text extrudeIn zOffsetIn].include?(k) }
        write_json('settings.json', keep)
      end

      def read_json(name)
        dir = Fonts.data_dir
        return nil unless dir
        path = File.join(dir, name)
        File.exist?(path) ? JSON.parse(File.read(path, encoding: 'UTF-8')) : nil
      rescue StandardError
        nil
      end

      def write_json(name, data)
        dir = Fonts.data_dir
        return unless dir
        File.open(File.join(dir, name), 'w:UTF-8') { |f| f.write(JSON.generate(data)) }
      rescue StandardError
        nil
      end

    end
  end
end
