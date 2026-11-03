module BanianStudio
  module BanianBrowser
    # Eyedropper: click any face / group to pick its material. The picked material
    # becomes the "current" material for the bucket, replace and texture tools.
    class MaterialPickerTool
      include ToolBase

      def initialize(then_tool = nil)
        @then_tool = then_tool
      end

      def activate
        @hover = nil
        Sketchup.status_text = I18n.t(:picker_status)
      end

      def resume(_view)
        Sketchup.status_text = I18n.t(:picker_status)
      end

      def onSetCursor
        c = @hover ? ToolBase.cursor('dropper_valid', 3, 21) : ToolBase.cursor('dropper', 3, 21)
        UI.set_cursor(c) if c && c > 0
      end

      def onMouseMove(_flags, x, y, view)
        @hover = material_under(view, x, y)
        view.tooltip = @hover ? Util.utf8(@hover.display_name) : ''
      end

      def onLButtonDown(_flags, x, y, view)
        mat = material_under(view, x, y)
        unless mat
          UI.beep
          return
        end
        MaterialOps.current = mat
        Sketchup.status_text = "#{I18n.t(:picked)}: #{Util.utf8(mat.display_name)}"
        Sketchup.active_model.select_tool(@then_tool) if @then_tool
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
