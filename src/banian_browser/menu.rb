module BanianStudio
  module BanianBrowser
    # Extensions menu, toolbar and right-click menu. Always in English: SketchUp's own
    # menus are English and right-to-left text does not display well inside them.
    module Menu
      class << self
        def t(key)
          I18n.en(key)
        end

        def icon(name)
          base = File.join(PLUGIN_DIR, 'icons', name)
          if Util.win? && Util.su_major >= 16 && File.exist?(base + '.svg')
            [base + '.svg', base + '.svg']
          else
            [base + '_24.png', base + '_32.png']
          end
        end

        def command(label_key, icon_name = nil, tip_key = nil, &block)
          cmd = UI::Command.new(t(label_key)) do
            begin
              block.call
            rescue StandardError => e
              Util.log_error(e, label_key.to_s)
              UI.messagebox(e.message)
            end
          end
          if icon_name
            small, large = icon(icon_name)
            cmd.small_icon = small
            cmd.large_icon = large
          end
          cmd.tooltip = t(tip_key || label_key)
          cmd.status_bar_text = t(tip_key || label_key)
          cmd
        end

        def model
          Sketchup.active_model
        end

        def install
          c = {}
          c[:open] = command(:open_browser, 'browser') { Dialog.toggle }
          c[:pick] = command(:eyedropper, 'dropper') { model.select_tool(MaterialPickerTool.new) }
          c[:bucket] = command(:bucket, 'bucket') { model.select_tool(MaterialBucketTool.new) }
          c[:rot] = command(:tex_rot_cw, 'tex_rotate') { TextureTools.rotate(-90) }
          c[:rot_ccw] = command(:tex_rot_ccw) { TextureTools.rotate(90) }
          c[:rot180] = command(:tex_rot_180) { TextureTools.rotate(180) }
          c[:flip_h] = command(:tex_flip_h) { TextureTools.flip('h') }
          c[:flip_v] = command(:tex_flip_v) { TextureTools.flip('v') }
          c[:fit] = command(:tex_fit, 'tex_fit') { TextureTools.fit }
          c[:align] = command(:tex_align) { TextureTools.align }
          c[:reset] = command(:tex_reset) { TextureTools.reset }
          c[:import] = command(:import_model, 'import') { Importer.browse_and_open }
          c[:simplify] = command(:simplify_sel, 'simplify') { Importer.open_selection('simplify') }
          c[:replace_tex] = command(:replace_tex, 'replace_tex') { model.select_tool(ReplaceTextureTool.new) }
          c[:imp_mat] = command(:import_mat_file) do
            Dialog.show
            Commands.cmd_import_mat_file({})
          end
          c[:imp_mat_dir] = command(:import_mat_folder) do
            folder = Commands.choose_folder(:choose_folder)
            MaterialOps.import_folder(folder) if folder
          end
          c[:save_sel] = command(:save_to_library) do
            folder = Commands.choose_folder(:choose_folder)
            ModelOps.save_selection(folder) if folder
          end
          c[:reset_win] = command(:reset_window) { Dialog.reset_position }
          c[:about] = command(:about) do
            UI.messagebox("Banian Browser #{VERSION}\nBanian Studio\n\n#{Settings.data_dir}")
          end

          has_sel = proc { model.selection.empty? ? MF_GRAYED : MF_ENABLED }
          [:save_sel, :simplify].each do |k|
            c[k].set_validation_proc(&has_sel)
          end

          root = UI.menu('Extensions').add_submenu('Banian Browser')
          root.add_item(c[:open])
          root.add_separator
          root.add_item(c[:import])
          root.add_item(c[:simplify])
          root.add_separator
          root.add_item(c[:pick])
          root.add_item(c[:bucket])
          root.add_item(c[:replace_tex])
          root.add_item(c[:imp_mat])
          root.add_item(c[:imp_mat_dir])
          tex = root.add_submenu(t(:texture))
          [:rot, :rot_ccw, :rot180, :flip_h, :flip_v, :fit, :align, :reset].each { |k| tex.add_item(c[k]) }
          root.add_item(c[:save_sel])
          root.add_separator
          root.add_item(c[:reset_win])
          root.add_item(c[:about])

          tb = UI::Toolbar.new('Banian Browser')
          [:open, :import, :simplify, :pick, :bucket, :replace_tex, :rot, :fit].each { |k| tb.add_item(c[k]) }
          state = tb.get_last_state
          if state == TB_NEVER_SHOWN
            tb.show
          elsif state == TB_VISIBLE
            tb.restore
          end

          UI.add_context_menu_handler do |menu|
            sel = model.selection
            next if sel.empty?
            sub = menu.add_submenu('Banian Browser')
            has_faces = sel.any? { |e| e.is_a?(Sketchup::Face) } || !Util.instances_in(sel.to_a).empty?
            if has_faces
              ts = sub.add_submenu(t(:texture))
              [:rot, :rot_ccw, :rot180, :flip_h, :flip_v, :fit, :align, :reset].each { |k| ts.add_item(c[k]) }
            end
            unless Util.instances_in(sel.to_a).empty?
              sub.add_item(c[:simplify])
              sub.add_item(c[:save_sel])
            end
          end
        end
      end
    end
  end
end
