module BanianStudio
  module BanianBrowser
    # "Stretch by area": place a component so it exactly fills a box you draw.
    #
    # three-point mode: 1) bottom-left  2) bottom-right (width)  3) top (height)
    #                   depth = model depth (type a value to change it)
    # two-point mode:   draw a rectangle (diagonal) on a face / the ground.
    #                   on floors: width x depth, height = model height
    #                   on walls:  width x height, depth = model depth
    #
    # Tab: switch mode   Ctrl: flip side   Arrows: lock axis (Right=X Left=Y Up=Z, Down=free)
    # Type a length + Enter: depth (or height on floors)   Esc: restart / exit
    class FitPlaceTool
      include ToolBase

      def initialize(definition, mode = 'three')
        @defn = definition
        @mode = mode
        @bb = definition.bounds
        @depth = nil
        @flip = false
      end

      def activate
        @ip = Sketchup::InputPoint.new
        @ip_prev = Sketchup::InputPoint.new
        reset
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        status
        view.invalidate
      end

      def reset
        @pts = []
        @normal = nil
        @lock = nil
        @cur = nil
        status
      end

      def needed
        @mode == 'three' ? 3 : 2
      end

      def status
        mode = @mode == 'three' ? I18n.t(:three_point) : I18n.t(:two_point)
        step = [I18n.t(:fit_p1), I18n.t(:fit_p2), I18n.t(:fit_p3)][@pts ? @pts.length : 0]
        Sketchup.status_text = "#{I18n.t(:mode)}: #{mode} (Tab)  |  #{step}  |  Ctrl: #{I18n.t(:flip)}"
        Sketchup.vcb_label = I18n.t(:depth)
        v = @depth || original_depth
        Sketchup.vcb_value = v.to_l.to_s
      rescue StandardError
        nil
      end

      def floor_mode?
        @mode == 'two' && @normal && @normal.parallel?(Z_AXIS)
      end

      def original_depth
        floor_mode? ? @bb.depth : @bb.height
      end

      def enableVCB?
        true
      end

      def onUserText(text, view)
        len = text.to_l
        if len > 0
          @depth = len
          status
          view.invalidate
        end
      rescue ArgumentError
        UI.beep
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when 9
          @mode = @mode == 'three' ? 'two' : 'three'
          Settings['place_mode'] = @mode == 'three' ? 'fit3' : 'fit2'
          reset
        when COPY_MODIFIER_KEY
          @flip = !@flip
        when VK_RIGHT then @lock = X_AXIS
        when VK_LEFT then @lock = Y_AXIS
        when VK_UP then @lock = Z_AXIS
        when VK_DOWN then @lock = nil
        else return false
        end
        status
        view.invalidate
        true
      end

      def onMouseMove(_flags, x, y, view)
        if @pts.empty?
          @ip.pick(view, x, y)
        else
          @ip.pick(view, x, y, @ip_prev)
        end
        view.tooltip = @ip.tooltip
        pt = @ip.position
        if @lock && !@pts.empty?
          pt = pt.project_to_line([@pts.last, @lock])
        end
        @cur = pt
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        return unless @cur
        if @pts.empty?
          @normal = input_normal
        end
        @pts << @cur
        @ip_prev.copy!(@ip)
        @lock = nil
        if @pts.length >= needed
          create(view)
          reset
        end
        status
        view.invalidate
      end

      def input_normal
        f = @ip.face
        return Z_AXIS.clone unless f
        n = f.normal.transform(@ip.transformation)
        n.normalize!
        n
      end

      def onCancel(_reason, view)
        if @pts.empty?
          Sketchup.active_model.select_tool(nil)
        else
          reset
          view.invalidate
        end
      end

      # => [origin, xa, ya, za, w, d, h] or nil
      def box(pts)
        if @mode == 'three'
          return nil if pts.length < 3
          p1, p2, p3 = pts
          xv = p2 - p1
          return nil if xv.length < 1e-6
          xa = xv.clone
          xa.normalize!
          v3 = p3 - p1
          k = v3 % xa
          zv = Geom::Vector3d.new(v3.x - xa.x * k, v3.y - xa.y * k, v3.z - xa.z * k)
          return nil if zv.length < 1e-6
          za = zv.clone
          za.normalize!
          ya = za.cross(xa)
          ya.normalize!
          d = @depth || @bb.height
          o = p1
          o = o.offset(ya, -d) if @flip
          [o, xa, ya, za, xv.length, d, zv.length]
        else
          return nil if pts.length < 2
          p1, p2 = pts
          n = @normal || Z_AXIS
          if n.parallel?(Z_AXIS)
            u = X_AXIS.clone
            v = Y_AXIS.clone
          else
            u = Z_AXIS.cross(n)
            u.normalize!
            v = n.cross(u)
            v.normalize!
          end
          dv = p2 - p1
          a = dv % u
          b = dv % v
          return nil if a.abs < 1e-6 || b.abs < 1e-6
          o = p1.offset(u, [a, 0].min).offset(v, [b, 0].min)
          w = a.abs
          hh = b.abs
          if n.parallel?(Z_AXIS)
            h = @depth || @bb.depth
            o = o.offset(u, w).offset(v, hh) if @flip
            xa = @flip ? u.reverse : u
            ya = @flip ? v.reverse : v
            return [o, xa, ya, Z_AXIS.clone, w, hh, h]
          end
          d = @depth || @bb.height
          xa = u
          za = v
          ya = za.cross(xa)
          ya.normalize!
          # front of the model faces away from the wall unless flipped (inset)
          o = o.offset(ya, -d) unless @flip
          [o, xa, ya, za, w, d, hh]
        end
      end

      def transformation_for(b)
        o, xa, ya, za, w, d, h = b
        sx = @bb.width > 1e-6 ? w / @bb.width : 1.0
        sy = @bb.height > 1e-6 ? d / @bb.height : 1.0
        sz = @bb.depth > 1e-6 ? h / @bb.depth : 1.0
        move = Geom::Transformation.translation(ORIGIN - @bb.min)
        Geom::Transformation.axes(o, xa, ya, za) * Geom::Transformation.scaling(sx, sy, sz) * move
      end

      def create(_view)
        b = box(@pts)
        return UI.beep unless b
        model = Sketchup.active_model
        model.start_operation(I18n.t(:op_place), true)
        inst = model.active_entities.add_instance(@defn, transformation_for(b))
        model.commit_operation
        model.selection.clear
        model.selection.add(inst)
      end

      def preview_points
        return [] unless @cur
        @pts + [@cur]
      end

      def draw(view)
        @ip.draw(view) if @ip && @ip.display?
        pts = preview_points
        return if pts.empty?
        view.line_width = 2
        view.drawing_color = 'DodgerBlue'
        view.draw(GL_LINE_STRIP, pts) if pts.length > 1
        b = box(pts)
        return unless b
        tr = transformation_for(b)
        draw_box(view, bounds_corners(@bb, tr), 'DodgerBlue', 2)
      end

      def getExtents
        bb = Sketchup.active_model.bounds
        preview_points.each { |p| bb.add(p) }
        b = box(preview_points)
        bounds_corners(@bb, transformation_for(b)).each { |p| bb.add(p) } if b
        bb
      end

      def getMenu(menu)
        menu.add_item(I18n.t(:edit_depth)) do
          res = UI.inputbox([I18n.t(:depth)], [(@depth || original_depth).to_l], I18n.t(:edit_depth))
          @depth = res[0].to_l if res && res[0].to_l > 0
          status
        end
        menu.add_item(I18n.t(:switch_mode)) do
          onKeyDown(9, false, 0, Sketchup.active_model.active_view)
        end
      end
    end
  end
end
