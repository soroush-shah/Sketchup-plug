# frozen_string_literal: true

module Banian
  module Stretch
    # Stretch by Box Bounds:
    #   1. click the first corner of a rectangle (on a face, or the ground),
    #   2. click the opposite corner (Tab toggles a rotated rectangle,
    #      which takes one more click),
    #   3. pull or type the Bound Height (the box reaches that far in front
    #      of and behind the rectangle),
    #   4. click the start and end points of the stretch.
    class BoxTool < BaseTool
      def initialize
        super
        @rotated = false
      end

      def reset
        super
        @state = :corner1
        @p1 = nil
        @live = nil
        @n = nil
        @u = nil
        @v = nil
        @width = 0.0
        @rect = nil # [umin, vmin, umax, vmax] relative to @p1 along @u/@v
        @height = 0.0
        @region = nil
        @hover = nil
      end

      def onMouseMove(_flags, x, y, view)
        case @state
        when :move then move_mouse(view, x, y)
        when :corner1 then @ip.pick(view, x, y)
        when :corner2 then update_corner2(plane_point(view, x, y))
        when :corner3 then update_corner3(plane_point(view, x, y))
        when :height
          @height = mouse_height(view, x, y)
          update_ui
        when :selected then @hover = pick_entity(view, x, y)
        end
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        case @state
        when :corner1 then set_corner1(view, x, y)
        when :corner2 then confirm_corner2(view, x, y)
        when :corner3 then confirm_corner3(view, x, y)
        when :height
          @height = mouse_height(view, x, y)
          build_region
        when :selected
          mode = selection_mode(flags)
          mode == :replace ? start_move(view, x, y) : toggle_pick(view, x, y, mode)
        when :move
          move_mouse(view, x, y)
          finish_move(view)
        end
        update_ui
        view.invalidate
      end

      def step_back
        case @state
        when :corner3 then @state = :corner2
        when :height then @state = @rotated ? :corner3 : :corner2
        else reset
        end
      end

      def selection_key_down(key, _repeat, _flags, view)
        return unless key == TAB_KEY && %i[corner1 corner2 corner3].include?(@state)

        @rotated = !@rotated
        if @p1
          @state = :corner2
          init_axes
          @rect = nil
        end
        update_ui
        view.invalidate
      end

      def selection_text(text, view)
        case @state
        when :corner2
          values = split_values(text)
          if @rotated
            length = parse_length(values.first)
            return unless length && !length.zero?

            @width = length.abs
            @rect = [0.0, 0.0, @width, 0.0]
            @state = :corner3
          else
            return UI.beep unless values.size == 2

            du = parse_length(values[0])
            dv = parse_length(values[1])
            return unless du && dv && !du.zero? && !dv.zero?

            du = -du.abs if @rect && @rect[0].negative?
            dv = -dv.abs if @rect && @rect[1].negative?
            @rect = [[0.0, du].min, [0.0, dv].min, [0.0, du].max, [0.0, dv].max]
            @state = :height
          end
        when :corner3
          dv = parse_length(text)
          return unless dv && !dv.zero?

          dv = -dv.abs if @rect && @rect[1].negative?
          @rect = [0.0, [0.0, dv].min, @width, [0.0, dv].max]
          @state = :height
        when :height
          h = parse_length(text)
          return unless h

          @height = h.abs
          build_region
        else
          UI.beep
        end
        view.invalidate
      end

      def selection_status
        shape = @rotated ? 'rotated rectangle' : 'rectangle'
        case @state
        when :corner1
          "Box Bounds: click the first corner of the #{shape}. Tab = rotated / axis-aligned rectangle."
        when :corner2
          if @rotated
            'Box Bounds: click to set the direction and length of the first side. Tab = axis-aligned.'
          else
            'Box Bounds: click the opposite corner, or type width,depth. Tab = rotated rectangle.'
          end
        when :corner3
          'Box Bounds: click to set the width of the rectangle, or type it.'
        when :height
          'Box Bounds: move to set the Bound Height (in front of and behind the rectangle) and click, or type it.'
        else
          if @plan.empty?
            'Box Bounds: nothing inside the box. Esc to draw a new box.'
          else
            "Click the stretch start point. #{ADD_KEY}/Shift-click adds/removes edges and faces. Esc = new box."
          end
        end
      end

      def selection_vcb
        case @state
        when :corner2
          if @rotated
            ['Length', '']
          else
            value = @rect ? "#{fmt(@rect[2] - @rect[0])}#{list_separator}#{fmt(@rect[3] - @rect[1])}" : ''
            ['Dimensions', value]
          end
        when :corner3 then ['Width', @rect ? fmt(@rect[3] - @rect[1]) : '']
        when :height then ['Bound Height', fmt(@height)]
        else ['Distance', '']
        end
      end

      def draw_overlay(view)
        case @state
        when :corner1
          @ip.draw(view) if @ip.display?
        when :corner2, :corner3
          draw_rectangle(view)
          @ip.draw(view) if @ip.display?
        when :height
          draw_box(view, current_region, '')
        when :selected, :move
          draw_box(view, @region, '-') if @region
          draw_hover(view, @hover) if @state == :selected
        end
      end

      def extra_points
        region = @region || (@state == :height ? current_region : nil)
        pts = region ? region.corners : []
        pts += rectangle_points if @rect
        pts
      end

      private

      def fmt(length)
        Sketchup.format_length(length.abs)
      end

      def list_separator
        Sketchup::RegionalSettings.list_separator
      rescue StandardError
        ','
      end

      def split_values(text)
        text.to_s.split(list_separator).map(&:strip).reject(&:empty?)
      end

      def set_corner1(view, x, y)
        @ip.pick(view, x, y)
        return UI.beep unless @ip.valid?

        @p1 = @ip.position
        face = @ip.face
        normal = face ? (@ip.transformation * face.normal) : @model.axes.zaxis
        normal = @model.axes.zaxis unless normal.valid?
        @n = normal.normalize
        init_axes
        @rect = nil
        @state = :corner2
      end

      def init_axes
        return unless @n

        axes = @model.axes
        if @n.parallel?(axes.zaxis)
          @u = axes.xaxis.clone
        else
          @u = (axes.zaxis * @n).normalize
        end
        @v = (@n * @u).normalize
      end

      def plane_point(view, x, y)
        @ip.pick(view, x, y)
        plane = [@p1, @n]
        if @ip.valid? && @ip.degrees_of_freedom.zero?
          @ip.position.project_to_plane(plane)
        else
          Geom.intersect_line_plane(view.pickray(x, y), plane) ||
            (@ip.valid? ? @ip.position.project_to_plane(plane) : nil)
        end
      end

      def update_corner2(point)
        return unless point

        @live = point
        d = point - @p1
        if @rotated
          @rect = nil
          return
        end
        du = d % @u
        dv = d % @v
        @rect = [[0.0, du].min, [0.0, dv].min, [0.0, du].max, [0.0, dv].max]
        update_ui
      end

      def confirm_corner2(view, x, y)
        point = plane_point(view, x, y)
        return UI.beep unless point

        if @rotated
          dir = point - @p1
          return UI.beep if !dir.valid? || dir.length < BoxRegion::EPSILON

          @u = dir.normalize
          @v = (@n * @u).normalize
          @width = dir.length
          @rect = [0.0, 0.0, @width, 0.0]
          @state = :corner3
        else
          update_corner2(point)
          return UI.beep if degenerate_rect?

          @state = :height
          @height = 0.0
        end
      end

      def update_corner3(point)
        return unless point

        dv = (point - @p1) % @v
        @rect = [0.0, [0.0, dv].min, @width, [0.0, dv].max]
        update_ui
      end

      def confirm_corner3(view, x, y)
        update_corner3(plane_point(view, x, y))
        return UI.beep if degenerate_rect?

        @state = :height
        @height = 0.0
      end

      def degenerate_rect?
        @rect.nil? || (@rect[2] - @rect[0]) < BoxRegion::EPSILON || (@rect[3] - @rect[1]) < BoxRegion::EPSILON
      end

      def rect_center
        cu = (@rect[0] + @rect[2]) / 2.0
        cv = (@rect[1] + @rect[3]) / 2.0
        BoxRegion.new(@p1, @u, @v, @n, [0, 0, 0], [0, 0, 0]).world(cu, cv, 0.0)
      end

      def mouse_height(view, x, y)
        center = rect_center
        line = [center, @n]
        @ip.pick(view, x, y)
        point =
          if @ip.valid? && @ip.degrees_of_freedom.zero?
            @ip.position
          else
            Geom.closest_points(line, view.pickray(x, y)).first
          end
        ((point - center) % @n).abs
      end

      def current_region
        return nil unless @rect && @u && @v && @n

        BoxRegion.new(@p1, @u, @v, @n, [@rect[0], @rect[1], -@height], [@rect[2], @rect[3], @height])
      end

      def build_region
        @region = current_region
        return UI.beep unless @region

        @plan = new_plan.apply_region(@region, Settings.filters, :add)
        plan_changed
        @state = :selected
      end

      def rectangle_points
        return [] unless @rect && @u && @v

        r = BoxRegion.new(@p1, @u, @v, @n, [0, 0, 0], [0, 0, 0])
        [[@rect[0], @rect[1]], [@rect[2], @rect[1]], [@rect[2], @rect[3]], [@rect[0], @rect[3]]].map do |a, b|
          r.world(a, b, 0.0)
        end
      end

      def draw_rectangle(view)
        view.drawing_color = Colors::REGION
        view.line_width = 2
        view.line_stipple = ''
        if @rotated && @state == :corner2 && @live
          draw_on_top(view, GL_LINES, [@p1, @live])
        elsif @rect
          draw_on_top(view, GL_LINE_LOOP, rectangle_points)
        end
        view.line_width = 1
      end

      def draw_box(view, region, stipple)
        return unless region

        view.drawing_color = Colors::REGION
        view.line_width = 1
        view.line_stipple = stipple
        draw_on_top(view, GL_LINES, Geometry.box_segments(region.corners))
        view.line_stipple = ''
      end
    end

    ErrorReporter.guard(BoxTool, BaseTool::CALLBACKS)
  end
end
