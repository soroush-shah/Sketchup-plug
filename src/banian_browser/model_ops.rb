module BanianStudio
  module BanianBrowser
    # Everything that loads / places / saves components from the library.
    module ModelOps
      class << self
        attr_accessor :last_definition

        def model
          Sketchup.active_model
        end

        # Refuses models saved by a newer SketchUp (they cannot be loaded).
        def check_version(path)
          v = Util.skp_version(path)
          return true if v.nil? || v <= Util.su_major
          UI.messagebox(format(I18n.t(:too_new), Util.su_year(v), Util.su_year(Util.su_major)))
          false
        end

        def check_file(path)
          return true if File.file?(path)
          UI.messagebox(I18n.t(:not_found))
          false
        end

        # Loads (or reuses) a component definition for a library .skp file.
        def load_definition(path)
          path = Util.norm(path)
          return nil unless check_file(path) && check_version(path)
          mtime = File.mtime(path).to_i
          d = model.definitions.find do |x|
            x.get_attribute(DICT, 'source') == path && x.get_attribute(DICT, 'mtime') == mtime
          end
          return d if d
          model.start_operation(I18n.t(:op_load), true)
          begin
            d = model.definitions.load(path)
            if d
              d.set_attribute(DICT, 'source', path)
              d.set_attribute(DICT, 'mtime', mtime)
            end
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            Util.log_error(e, 'load definition')
            UI.messagebox(I18n.t(:load_failed) + "\n" + e.message)
            return nil
          end
          d
        end

        # Main entry from the browser: place according to the chosen mode.
        def place(path, mode = nil)
          mode ||= Settings['place_mode']
          if mode == 'proxy'
            return Proxy.place_as_proxy(path)
          end
          d = load_definition(path)
          return false unless d
          self.last_definition = d
          Settings.record_use(path)
          case mode
          when 'fit3' then model.select_tool(FitPlaceTool.new(d, 'three'))
          when 'fit2' then model.select_tool(FitPlaceTool.new(d, 'two'))
          when 'surface' then model.select_tool(SurfacePlaceTool.new(d))
          else model.place_component(d, false)
          end
          true
        end

        def replace_selection(path)
          insts = Util.instances_in(model.selection.to_a)
          if insts.empty?
            UI.messagebox(I18n.t(:select_components))
            return false
          end
          d = load_definition(path)
          return false unless d
          model.start_operation(I18n.t(:op_replace), true)
          new_sel = []
          insts.each do |inst|
            if inst.is_a?(Sketchup::ComponentInstance)
              inst.definition = d
              new_sel << inst
            else
              parent = inst.parent.entities
              n = parent.add_instance(d, inst.transformation)
              n.material = inst.material if inst.material
              n.layer = inst.layer
              inst.erase!
              new_sel << n
            end
          end
          model.commit_operation
          model.selection.clear
          model.selection.add(new_sel)
          Settings.record_use(path)
          true
        end

        # Saves the selected group/component into a library folder.
        def save_selection(folder)
          sel = Util.instances_in(model.selection.to_a)
          if sel.length != 1
            UI.messagebox(I18n.t(:select_one))
            return nil
          end
          inst = sel.first
          d = Util.definition_of(inst)
          unless d.respond_to?(:save_as)
            UI.messagebox(I18n.t(:needs_newer_su))
            return nil
          end
          default = inst.respond_to?(:name) && !inst.name.to_s.empty? ? inst.name : d.name
          res = UI.inputbox([I18n.t(:file_name)], [Util.utf8(default)], I18n.t(:save_model))
          return nil unless res
          path = Util.unique_path(Util.join(folder, Util.safe_filename(res[0]) + '.skp'))
          d.save_as(path)
          write_cached_thumb(d, path)
          Library.rescan_for(path)
          path
        end

        def save_current_model(folder)
          title = model.title.to_s.empty? ? 'model' : model.title
          res = UI.inputbox([I18n.t(:file_name)], [Util.utf8(title)], I18n.t(:save_model))
          return nil unless res
          path = Util.unique_path(Util.join(folder, Util.safe_filename(res[0]) + '.skp'))
          model.save_copy(path)
          Library.rescan_for(path)
          path
        end

        def write_cached_thumb(definition, path)
          return unless definition.respond_to?(:save_thumbnail)
          definition.save_thumbnail(Thumbnails.cache_file(path))
        rescue StandardError
          nil
        end

        def open(path)
          return false unless check_file(path) && check_version(path)
          Settings.record_use(path)
          Sketchup.open_file(Util.norm(path))
        end

        # Windows: opens a new SketchUp process; macOS: SketchUp is multi-window.
        def open_new_window(path)
          return false unless check_file(path) && check_version(path)
          if Util.mac?
            Sketchup.open_file(Util.norm(path))
          else
            Util.open_with_os(path)
          end
          true
        end
      end
    end
  end
end
