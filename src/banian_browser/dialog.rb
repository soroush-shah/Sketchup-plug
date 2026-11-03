module BanianStudio
  module BanianBrowser
    # HtmlDialog + JSON message bridge.
    #   JS -> Ruby : sketchup.bb_call(JSON.stringify({id, cmd, args}))
    #   Ruby -> JS : BB.reply(id, data)  /  BB.emit(event, data)
    module Dialog
      class << self
        def dialog
          @dlg
        end

        def visible?
          @dlg && @dlg.visible?
        end

        def show
          if visible?
            @dlg.bring_to_front
            return
          end
          @dlg = UI::HtmlDialog.new(
            :dialog_title => 'Banian Browser',
            :preferences_key => 'BanianStudio_BanianBrowser',
            :scrollable => false,
            :resizable => true,
            :width => 1120,
            :height => 740,
            :left => 120,
            :top => 90,
            :min_width => 560,
            :min_height => 420,
            :style => UI::HtmlDialog::STYLE_DIALOG
          )
          @dlg.set_file(File.join(PLUGIN_DIR, 'ui', 'index.html'))
          @dlg.add_action_callback('bb_call') { |_ctx, payload| handle(payload) }
          @dlg.set_on_closed { @dlg = nil } if @dlg.respond_to?(:set_on_closed)
          @dlg.show
        end

        def toggle
          if visible?
            @dlg.close
            @dlg = nil
          else
            show
          end
        end

        def reset_position
          show
          @dlg.set_position(120, 90)
          @dlg.set_size(1120, 740)
        end

        def to_js(obj)
          JSON.generate(obj).gsub(" ", ' ').gsub(" ", ' ')
        end

        def js(code)
          @dlg.execute_script(code) if visible?
        rescue StandardError => e
          Util.log_error(e, 'execute_script')
        end

        def emit(event, data)
          js("window.BB && BB.emit(#{to_js(event)}, #{to_js(data)});")
        end

        def reply(id, data)
          js("window.BB && BB.reply(#{to_js(id)}, #{to_js(data)});")
        end

        def handle(payload)
          msg = payload.is_a?(String) ? JSON.parse(payload) : payload
          id = msg['id']
          result = Commands.run(msg['cmd'].to_s, msg['args'] || {})
          reply(id, 'ok' => true, 'data' => result) if id
        rescue StandardError => e
          Util.log_error(e, "command #{msg ? msg['cmd'] : '?'}")
          reply(id, 'ok' => false, 'error' => e.message) if id
        end
      end
    end

    # Every command the dialog can run.
    module Commands
      class << self
        def model
          Sketchup.active_model
        end

        def run(cmd, a)
          name = "cmd_#{cmd}"
          raise ArgumentError, "unknown command #{cmd}" unless respond_to?(name)
          send(name, a)
        end

        def choose_folder(title_key, default = nil)
          dir = default && File.directory?(default) ? default : Settings['last_save_dir']
          opts = { :title => I18n.t(title_key) }
          opts[:directory] = dir if dir && !dir.to_s.empty? && File.directory?(dir)
          res = UI.select_directory(opts)
          return nil unless res
          res = Util.norm(res)
          Settings['last_save_dir'] = res
          res
        end

        def folder_arg(a)
          f = a['folder']
          f && File.directory?(f) ? Util.norm(f) : choose_folder(:choose_folder)
        end

        # ---- app / settings ----------------------------------------------------------
        def cmd_init(_a)
          {
            'settings' => Settings.data,
            'version' => VERSION,
            'su' => Util.su_major,
            'su_year' => Util.su_year(Util.su_major),
            'platform' => Util.win? ? 'win' : 'mac',
            'data_dir' => Settings.data_dir,
            'picked' => MaterialOps.info(MaterialOps.current)
          }
        end

        def cmd_settings(a)
          Settings.update(a['values'] || {})
          Settings.data
        end

        def cmd_reset_window(_a)
          Dialog.reset_position
          true
        end

        def cmd_open_url(a)
          UI.openURL(a['url'].to_s)
          true
        end

        def cmd_clear_thumb_cache(_a)
          Thumbnails.clear_cache
          true
        end

        def cmd_choose_folder(_a)
          choose_folder(:choose_folder)
        end

        # ---- library -------------------------------------------------------------------
        def cmd_indexes(a)
          Library.scan_all if a['rescan']
          Library.all_cached
        end

        def cmd_scan(a)
          Library.scan(a['root'])
          true
        end

        def cmd_add_root(a)
          path = choose_folder(:choose_root)
          return nil unless path
          Library.add_root(path, a['type'] || 'both')
          Settings['roots']
        end

        def cmd_remove_root(a)
          Library.remove_root(a['root'])
          Settings['roots']
        end

        def cmd_set_root(a)
          Library.set_root(a['root'], a)
          Settings['roots']
        end

        def cmd_thumbs(a)
          Thumbnails.request(Array(a['paths']))
          true
        end

        def cmd_gen_thumb(a)
          Thumbnails.generate_with_sketchup(a['path'])
        end

        def cmd_set_thumb(a)
          img = UI.openpanel(I18n.t(:choose_image), File.dirname(a['path']), 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.webp||')
          return nil unless img
          Thumbnails.set_custom(a['path'], Util.norm(img))
        end

        def cmd_clear_thumb(a)
          Thumbnails.clear_custom(a['path'])
          Thumbnails.resolve(a['path'])
        end

        def cmd_fav(a)
          Settings.toggle_favorite(a['path'])
        end

        def cmd_rename(a)
          Library.rename(a['path'], a['name'])
        end

        def cmd_delete(a)
          Library.delete(a['paths'])
        end

        def cmd_mkdir(a)
          Library.mkdir(a['parent'], a['name'])
        end

        def cmd_move(a)
          Library.move(a['paths'], a['dest'])
        end

        def cmd_reveal(a)
          Util.open_folder(a['path'])
          true
        end

        def cmd_add_files(a)
          dest = a['dest']
          files = UI.openpanel(I18n.t(:choose_folder), '', 'SketchUp|*.skp;*.skm;*.jpg;*.jpeg;*.png;*.tif;*.tga;*.bmp||')
          return nil unless files
          Library.copy_in([Util.norm(files)], dest)
          true
        end

        # ---- models --------------------------------------------------------------------
        def cmd_place(a)
          return Importer.open_file(a['path']) && true if Util.kind_of_ext(File.extname(a['path'].to_s)) == 'mesh'
          ModelOps.place(a['path'], a['mode'])
        end

        def cmd_open(a)
          ModelOps.open(a['path'])
        end

        def cmd_open_new(a)
          ModelOps.open_new_window(a['path'])
        end

        def cmd_replace_sel(a)
          ModelOps.replace_selection(a['path'])
        end

        def cmd_array_path(a)
          PathTools.array_along(a['path'])
        end

        def cmd_sweep(a)
          PathTools.sweep_profile(a['path'])
        end

        def cmd_save_sel(a)
          folder = folder_arg(a)
          folder ? ModelOps.save_selection(folder) : nil
        end

        def cmd_save_model(a)
          folder = folder_arg(a)
          folder ? ModelOps.save_current_model(folder) : nil
        end

        # ---- materials -------------------------------------------------------------------
        def cmd_mat_paint(a)
          MaterialOps.import_and_paint(a['path'])
        end

        def cmd_mat_apply(a)
          MaterialOps.import_and_apply(a['path'])
        end

        def cmd_mat_add(a)
          m = MaterialOps.import(a['path'])
          m ? true : false
        end

        def cmd_mat_replace_with(a)
          MaterialOps.replace_with_path(a['path'], a['remove'] != false)
        end

        def cmd_pick_tool(_a)
          model.select_tool(MaterialPickerTool.new)
          true
        end

        def cmd_bucket_tool(_a)
          model.select_tool(MaterialBucketTool.new)
          true
        end

        def cmd_native_paint(_a)
          Sketchup.send_action('selectPaintTool:')
          true
        end

        def cmd_apply_sel(_a)
          MaterialOps.apply_to_selection
        end

        def cmd_picked(_a)
          MaterialOps.info(MaterialOps.current)
        end

        def cmd_model_mats(_a)
          MaterialOps.list
        end

        def cmd_model_mat_select(a)
          m = model.materials[a['name']]
          MaterialOps.current = m if m
          MaterialOps.info(m)
        end

        def cmd_model_mat_replace(a)
          MaterialOps.replace_with_material_name(a['src'], a['dst'], a['remove'] != false)
        end

        def cmd_model_mat_save(a)
          folder = folder_arg(a)
          return nil unless folder
          m = a['name'] ? model.materials[a['name']] : MaterialOps.current
          MaterialOps.save_to_library(m, folder)
        end

        def cmd_model_mat_delete(a)
          m = model.materials[a['name']]
          return false unless m && model.materials.respond_to?(:remove)
          model.start_operation(I18n.t(:op_edit_mat), true)
          model.materials.remove(m)
          model.commit_operation
          true
        end

        def cmd_export_mats(a)
          folder = folder_arg(a)
          folder ? MaterialOps.export_all(folder) : nil
        end

        def cmd_collect_tex(a)
          folder = folder_arg(a)
          folder ? MaterialOps.collect_textures(folder) : nil
        end

        def cmd_purge_mats(_a)
          MaterialOps.purge_unused
        end

        def cmd_mat_props(a)
          MaterialOps.set_props(a['name'], a['props'] || {})
        end

        # ---- importer (Skimp-style) / replace textures / image conversion ----------------
        def cmd_import_file(a)
          Importer.open_file(a['path'])
          true
        end

        def cmd_import_browse(_a)
          Importer.browse_and_open
          true
        end

        def cmd_simplify_sel(_a)
          Importer.open_selection('simplify')
          true
        end

        def cmd_replace_tex_tool(_a)
          model.select_tool(ReplaceTextureTool.new)
          true
        end

        def cmd_import_mat_file(_a)
          f = UI.openpanel(I18n.t(:import_mat_file), Settings['last_save_dir'].to_s,
                           'Materials|*.skm;*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff;*.tga;*.gif;*.webp||')
          return nil unless f
          f = Util.norm(f)
          return { 'convert' => f } if MaterialOps.needs_conversion?(f) && File.extname(f).downcase != '.skm' &&
                                       !File.file?(MaterialOps.converted_file(f))
          MaterialOps.import_and_paint(f)
        end

        def cmd_import_mat_folder(a)
          folder = folder_arg(a)
          folder ? MaterialOps.import_folder(folder) : nil
        end

        # Image formats SketchUp cannot read are converted to PNG by the dialog.
        def cmd_needs_convert(a)
          p = Util.norm(a['path'])
          MaterialOps.needs_conversion?(p) && !File.file?(MaterialOps.converted_file(p))
        end

        def cmd_read_b64(a)
          p = Util.norm(a['path'])
          return nil unless File.file?(p) && File.size(p) < 64 * 1024 * 1024
          [File.binread(p)].pack('m0')
        end

        def cmd_save_converted(a)
          p = Util.norm(a['path'])
          File.open(MaterialOps.converted_file(p), 'wb') { |f| f.write(a['png'].to_s.unpack('m0')[0]) }
          true
        end

        # ---- texture positioning --------------------------------------------------------
        def cmd_tex(a)
          v = a['value']
          case a['op']
          when 'rotate' then TextureTools.rotate(v.to_f)
          when 'flip' then TextureTools.flip(v.to_s)
          when 'scale' then TextureTools.scale(v.to_f)
          when 'nudge' then TextureTools.nudge(a['du'].to_f, a['dv'].to_f)
          when 'fit' then TextureTools.fit
          when 'align' then TextureTools.align
          when 'reset' then TextureTools.reset
          when 'copy' then TextureTools.copy_mapping
          when 'paste' then TextureTools.paste_mapping
          else raise ArgumentError, 'unknown texture op'
          end
        end

        # ---- proxies -----------------------------------------------------------------------
        def cmd_proxy(a)
          case a['op']
          when 'make' then Proxy.convert_selection(a['mode'])
          when 'all_full' then Proxy.to_full('all')
          when 'all_proxy' then Proxy.to_proxy('all')
          when 'sel_full' then Proxy.to_full('selection')
          when 'sel_proxy' then Proxy.to_proxy('selection')
          when 'open' then Proxy.open_source
          when 'regular' then Proxy.make_regular
          when 'place' then Proxy.place_as_proxy(a['path'])
          when 'decimated' then Importer.open_selection('proxy')
          when 'choose_dir'
            d = choose_folder(:choose_folder)
            Settings['proxy_dir'] = d if d
            Proxy.stats
          when 'stats' then Proxy.stats
          else raise ArgumentError, 'unknown proxy op'
          end
        end

        def cmd_tool(a)
          d = ModelOps.last_definition
          d = nil if d && !d.valid?
          case a['name']
          when 'fit3' then d && model.select_tool(FitPlaceTool.new(d, 'three'))
          when 'fit2' then d && model.select_tool(FitPlaceTool.new(d, 'two'))
          when 'surface' then d && model.select_tool(SurfacePlaceTool.new(d))
          end
          d ? true : false
        end
      end
    end
  end
end
