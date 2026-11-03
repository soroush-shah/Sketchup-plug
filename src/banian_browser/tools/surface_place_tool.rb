module BanianStudio
  module BanianBrowser
    # Place a component on any surface (walls, ceilings, slopes...). The component
    # follows the face under the cursor and can be placed many times.
    #
    # Left / Right arrows: rotate by the rotate step (45 deg by default)
    # Up / Down: rotate 90 deg      Ctrl: align to face normal / keep upright
    # Shift: lock the current surface     Type an angle + Enter: exact rotation
    class SurfacePlaceTool
      include ToolBase

      def initialize(definition)
        @defn = definition
        @bb = definition.bounds
        @angle = 0.0
        @align = Settings['surface_align'] == 'upright' ? 'upright' : 'normal'
      end

      def activate
        @ip = Sketchup::InputPoint.new
        @tr = nil
        @locked = nil
        status
      end

      def resume(view)
        status
        view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def status
        align = @align == 'normal' ? I18n.t(:align_normal) : I18n.t(:align_upright)
        Sketchup.status_text = "#{I18n.t(:surface_status)}  |  Ctrl: #{align}"
        Sketchup.vcb_label = I18n.t(:angle)
        Sketchup.vcb_value = format('%.1f', @angle)
      end

      def enableVCB?
        true
      end

      def onUserText(text, view)
        @angle = text.to_f % 360
        status
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        step = Settings['rotate_step'].to_f
        step = 45.0 if step <= 0
        case key
        when VK_RIGHT then @angle = (@angle + step) % 360
        when VK_LEFT then @angle = (@angle - step) % 360
        when VK_UP then @angle = (@angle + 90) % 360
        when VK_DOWN then @angle = (@angle - 90) % 360
        when COPY_MODIFIER_KEY
          @align = @align == 'normal' ? 'upright' : 'normal'
          Settings['surface_align'] = @align
        when CONSTRAIN_MODIFIER_KEY
          @locked = @last_plane
        else return false
        end
        status
        update(view)
        true
      end

      def onKeyUp(key, _repeat, _flags, _view)
        @locked = nil if key == CONSTRAIN_MODIFIER_KEY
        false
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        view.tooltip = @ip.tooltip
        update(view)
      end

      def surface
        f = @ip.face
        n = if f
              v = f.normal.transform(@ip.transformation)
              v.normalize!
              v
            else
              Z_AXIS.clone
            end
        pt = @ip.position
        if @locked
          lp, ln = @locked
          return [pt.project_to_plane([lp, ln]), ln]
        end
        @last_plane = [pt, n]
        [pt, n]
      end

      def update(view)
        return unless @ip.valid?
        pt, n = surface
        za = @align == 'normal' ? n : Z_AXIS.clone
        xa = za.parallel?(Z_AXIS) ? X_AXIS.clone : Z_AXIS.cross(za)
        xa.normalize!
        ya = za.cross(xa)
        ya.normalize!
        rot = Geom::Transformation.rotation(ORIGIN, Z_AXIS, @angle * Math::PI / 180.0)
        @tr = Geom::Transformation.axes(pt, xa, ya, za) * rot
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, _view)
        return unless @tr
        model = Sketchup.active_model
        model.start_operation(I18n.t(:op_place), true)
        model.active_entities.add_instance(@defn, @tr)
        model.commit_operation
      end

      def draw(view)
        @ip.draw(view) if @ip.display?
        return unless @tr
        draw_box(view, bounds_corners(@bb, @tr), 'DodgerBlue', 2)
        o = ORIGIN.transform(@tr)
        len = [@bb.diagonal * 0.25, 1.0].max
        { 'Red' => X_AXIS, 'Green' => Y_AXIS, 'Blue' => Z_AXIS }.each do |color, axis|
          view.drawing_color = color
          view.draw(GL_LINES, [o, o.offset(axis.transform(@tr), len)])
        end
      end

      def getExtents
        bb = Sketchup.active_model.bounds
        bounds_corners(@bb, @tr).each { |p| bb.add(p) } if @tr
        bb
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
