# frozen_string_literal: true

module Banian
  module Stretch
    # Stretch by Face Bounds:
    #   1. hover a face (at any depth) - a box around it is previewed; type a
    #      value to change the Bound Height (how far the box reaches beyond
    #      the face in every direction),
    #   2. click the face to select everything inside that box,
    #   3. click the start and end points of the stretch.
    class FaceTool < BaseTool
      def reset
        super
        @state = :pick
        @face_hit = nil
        @hover_hit = nil
        @hover_region = nil
        @region = nil
        @hover = nil
      end

      def onMouseMove(_flags, x, y, view)
        case @state
        when :move then move_mouse(view, x, y)
        when :pick
          @hover_hit = pick_entity(view, x, y, faces_only: true, respect_filters: false)
          @hover_region = @hover_hit ? face_region(@hover_hit) : nil
        when :selected then @hover = pick_entity(view, x, y)
        end
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        case @state
        when :pick
          hit = pick_entity(view, x, y, faces_only: true, respect_filters: false)
          return UI.beep unless hit

          @face_hit = hit
          select_from_face
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

      # Typing a length (before or after picking the face) sets the Bound
      # Height; after picking, the selection is rebuilt with the new value.
      def selection_text(text, view)
        height = parse_length(text)
        return unless height

        Settings['bound_height'] = height.abs.to_f
        if @state == :selected && @face_hit
          select_from_face
        elsif @hover_hit
          @hover_region = face_region(@hover_hit)
        end
        view.invalidate
      end

      def selection_status
        if @state == :pick
          'Face Bounds: click a face to select everything within the Bound Height around it. ' \
            'Type a length to change the Bound Height.'
        elsif @plan.empty?
          'Face Bounds: nothing selected. Type a larger Bound Height or press Esc to pick another face.'
        else
          "Click the stretch start point. #{ADD_KEY}/Shift-click adds/removes edges and faces. " \
            'Type a length to change the Bound Height. Esc = pick another face.'
        end
      end

      def selection_vcb
        ['Bound Height', Sketchup.format_length(Settings.bound_height)]
      end

      def draw_overlay(view)
        case @state
        when :pick
          draw_face(view, @hover_hit)
          draw_region(view, @hover_region, '-')
        when :selected, :move
          draw_face(view, @face_hit) if @face_hit&.dig(1)&.valid?
          draw_region(view, @region, '-')
          draw_hover(view, @hover) if @state == :selected
        end
      end

      def extra_points
        region = @region || @hover_region
        region ? region.corners : []
      end

      private

      def select_from_face
        @region = face_region(@face_hit)
        return UI.beep unless @region

        @plan = new_plan.apply_region(@region, Settings.filters, :add)
        plan_changed
        @state = :selected
      end

      # Oriented box around a face: in-plane extents grown by the Bound
      # Height on every side, and the same distance in front and behind.
      def face_region(hit)
        _path, face, tr = hit
        return nil unless face&.valid?

        pts = face.outer_loop.vertices.map { |v| tr * v.position }
        return nil if pts.size < 3

        normal = Geometry.polygon_normal(pts)
        return nil unless normal

        a, b = longest_side(pts)
        u = b - a
        return nil unless u.valid?

        u = u.normalize
        v = (normal * u).normalize
        origin = pts.first
        us = pts.map { |p| (p - origin) % u }
        vs = pts.map { |p| (p - origin) % v }
        h = Settings.bound_height
        BoxRegion.new(origin, u, v, normal, [us.min - h, vs.min - h, -h], [us.max + h, vs.max + h, h])
      end

      def longest_side(pts)
        best = [pts[0], pts[1]]
        best_len = -1.0
        pts.each_with_index do |a, i|
          b = pts[(i + 1) % pts.size]
          len = a.distance(b)
          next unless len > best_len

          best_len = len
          best = [a, b]
        end
        best
      end

      def draw_face(view, hit)
        return unless hit

        _path, face, tr = hit
        return unless face.valid?

        view.drawing_color = Colors::HOVER
        view.line_width = 2
        view.line_stipple = ''
        view.draw(GL_LINE_LOOP, face.outer_loop.vertices.map { |v| tr * v.position })
        view.line_width = 1
      end

      def draw_region(view, region, stipple)
        return unless region

        view.drawing_color = Colors::REGION
        view.line_width = 1
        view.line_stipple = stipple
        view.draw(GL_LINES, Geometry.box_segments(region.corners))
        view.line_stipple = ''
      end
    end
  end
end
