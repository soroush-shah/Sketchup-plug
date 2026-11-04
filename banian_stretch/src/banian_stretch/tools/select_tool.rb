# frozen_string_literal: true

module Banian
  module Stretch
    # Stretch (Window / Click):
    #   * drag a window to select (Ctrl/Option adds, Shift removes),
    #   * or click an edge/face to select it and start stretching at once,
    #   * then click the start and end points (or type a distance).
    class SelectTool < BaseTool
      def reset
        super
        @state = :select
        @down = nil
        @down_flags = 0
        @drag = nil
        @hover = nil
      end

      def step_back
        reset unless @plan.empty?
        @down = nil
        @drag = nil
      end

      def onMouseMove(_flags, x, y, view)
        if @state == :move
          move_mouse(view, x, y)
        elsif @down
          @drag = [x, y] if @drag || drag_distance(@down, [x, y]) > CLICK_TOLERANCE
        else
          @hover = pick_entity(view, x, y)
        end
        view.invalidate
      end

      def onLButtonDown(flags, x, y, _view)
        return if @state == :move

        @down = [x, y]
        @down_flags = flags
        @drag = nil
      end

      def onLButtonUp(flags, x, y, view)
        if @state == :move
          move_mouse(view, x, y)
          finish_move(view)
        elsif @down
          mode = selection_mode(flags | @down_flags)
          if @drag
            select_window(view, @down, [x, y], mode)
          else
            click(view, x, y, mode)
          end
          @down = nil
          @drag = nil
          @hover = nil
        end
        view.invalidate
      end

      def selection_status
        if @plan.empty?
          'Drag a window to select geometry to stretch, or click an edge/face to stretch it. ' \
            "#{ADD_KEY} = add, Shift = remove."
        else
          'Click the stretch start point. Drag a new window to reselect ' \
            "(#{ADD_KEY} = add, Shift = remove), #{ADD_KEY}/Shift-click to fine-tune, Esc clears."
        end
      end

      def selection_vcb
        ['Distance', '']
      end

      def draw_overlay(view)
        if @drag && @down
          draw_window(view)
        elsif @state == :select
          draw_hover(view, @hover)
        end
      end

      private

      def drag_distance(a, b)
        Math.hypot(a[0] - b[0], a[1] - b[1])
      end

      def select_window(view, a, b, mode)
        region = ScreenRegion.new(view, a, b)
        @plan = new_plan if mode == :replace
        @plan.apply_region(region, Settings.filters, mode == :remove ? :remove : :add)
        plan_changed
      end

      def click(view, x, y, mode)
        if mode != :replace
          toggle_pick(view, x, y, mode)
        elsif @plan.empty?
          hit = pick_entity(view, x, y)
          return UI.beep unless hit

          @plan.apply_pick(hit[0], hit[1], :add)
          plan_changed
          start_move(view, x, y) unless @plan.empty?
        else
          start_move(view, x, y)
        end
      end

      def draw_window(view)
        x1, y1 = @down
        x2, y2 = @drag
        pts = [[x1, y1], [x2, y1], [x2, y2], [x1, y2]].map { |x, y| Geom::Point3d.new(x, y, 0) }
        view.drawing_color = Colors::REGION_FILL
        view.draw2d(GL_QUADS, pts)
        view.drawing_color = Colors::REGION
        view.line_width = 1
        view.line_stipple = ''
        view.draw2d(GL_LINE_LOOP, pts)
      end
    end
  end
end
