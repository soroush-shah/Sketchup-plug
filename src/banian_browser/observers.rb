module BanianStudio
  module BanianBrowser
    # Keeps the browser in step with SketchUp:
    #  * the material chosen with SketchUp's paint bucket / Materials panel becomes the
    #    "picked" material (thumbnail in the panel, target of the texture tools);
    #  * the selection is summarised so the texture panel shows what will change.
    module Observers
      class MaterialsWatch < Sketchup::MaterialsObserver
        def onMaterialSetCurrent(_materials, _material)
          Observers.later(:picked)
        end

        def onMaterialChange(_materials, material)
          Observers.later(:picked) if material == MaterialOps.current
        end
      end

      class SelectionWatch < Sketchup::SelectionObserver
        def onSelectionBulkChange(_sel)
          Observers.later(:target)
        end

        def onSelectionCleared(_sel)
          Observers.later(:target)
        end

        def onSelectionAdded(_sel, _e)
          Observers.later(:target)
        end

        def onSelectionRemoved(_sel, _e)
          Observers.later(:target)
        end
      end

      class AppWatch < Sketchup::AppObserver
        def onNewModel(model)
          Observers.attach(model)
        end

        def onOpenModel(model)
          Observers.attach(model)
        end

        def onActivateModel(model)
          Observers.attach(model)
        end
      end

      class << self
        def install
          @mats = MaterialsWatch.new
          @sel = SelectionWatch.new
          @attached = {}
          Sketchup.add_observer(AppWatch.new)
          attach(Sketchup.active_model)
        end

        def attach(model)
          return unless model && @mats
          key = model.object_id
          return if @attached[key]
          @attached[key] = true
          model.materials.add_observer(@mats)
          model.selection.add_observer(@sel)
          later(:picked)
          later(:target)
        end

        # Coalesces bursts of events (a selection change fires many) into one update.
        def later(what)
          @due ||= {}
          @due[what] = true
          return if @timer
          @timer = UI.start_timer(0.15, false) do
            @timer = nil
            due = @due
            @due = {}
            flush(due)
          end
        end

        def flush(due)
          return unless Dialog.visible?
          Dialog.emit('picked', MaterialOps.info(MaterialOps.current)) if due[:picked]
          Dialog.emit('tex_target', TextureTools.summary) if due[:target]
        rescue StandardError => e
          Util.log_error(e, 'observers')
        end
      end
    end
  end
end
