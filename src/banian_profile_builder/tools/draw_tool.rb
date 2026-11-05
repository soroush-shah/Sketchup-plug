# encoding: UTF-8
# Banian Profile Builder - Draw tool.
# Click points like the Line tool; a live wireframe of the real profile
# follows the cursor. Finish with Enter, double-click or right-click.
# Click the first point to close the loop. Type a length for exact segments.
# Arrow keys lock axes (Right = red, Left = green, Up = blue, Down = off).
# Backspace removes the last point, Esc cancels.

module BanianStudio
  module ProfileBuilder
    class DrawTool
      COLOR_PATH = Sketchup::Color.new(220, 60, 40)
      COLOR_PREVIEW = Sketchup::Color.new(40, 110, 200)
      CLOSE_PX = 12
      VK_BACK = 8

      def self.locked?(view)
        view.respond_to?(:inference_locked?) ? view.inference_locked? : true
      end

      def initialize
        @ip = Sketchup::InputPoint.new
        @ip_prev = Sketchup::InputPoint.new
        @points = [] # world space
        @cursor = nil
        @lock = nil
        @preview = []
      end

      def activate
        @points = []
        @cursor = nil
        status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.lock_inference if DrawTool.locked?(view)
        view.invalidate
      end

      def resume(view)
        status
        view.invalidate
      end

      def onCancel(_reason, view)
        @points = []
        @preview = []
        status
        view.invalidate
      end

      def enableVCB?
        true
      end

      def status
        Sketchup.status_text = if @points.empty?
                                 "Banian Draw (#{Controller.mode}): click to start the path. Arrow keys lock axes."
                               else
                                 'Click next point, type a length, click first point to close. Enter / double-click / right-click = finish, Backspace = undo point, Esc = cancel.'
                               end
        Sketchup.vcb_label = 'Length'
      end

      def edit_tr
        Sketchup.active_model.edit_transform
      end

      def axis_vector
        v = { x: [1, 0, 0], y: [0, 1, 0], z: [0, 0, 1] }[@lock]
        return nil unless v
        (edit_tr * Geom::Vector3d.new(*v)).normalize
      end

      def onMouseMove(_flags, x, y, view)
        if @points.empty?
          @ip.pick(view, x, y)
        else
          @ip.pick(view, x, y, @ip_prev)
        end
        pt = @ip.position
        if !@points.empty? && (ax = axis_vector)
          line = [@points[-1], ax]
          pt = pt.project_to_line(line)
        end
        @cursor = pt
        view.tooltip = @ip.tooltip if @ip.valid?
        Sketchup.vcb_value = @points[-1].distance(pt).to_l.to_s unless @points.empty?
        update_preview
        view.invalidate
      end

      def near_first?(view, pt)
        return false if @points.size < 3
        a = view.screen_coords(@points[0])
        b = view.screen_coords(pt)
        Math.hypot(a.x - b.x, a.y - b.y) < CLOSE_PX
      end

      def onLButtonDown(_flags, _x, _y, view)
        return unless @cursor
        if near_first?(view, @cursor)
          finish(view, true)
          return
        end
        add_point(@cursor, view)
      end

      def add_point(pt, view)
        return if !@points.empty? && @points[-1].distance(pt) < 0.001
        @points << pt.clone
        @ip_prev.copy!(@ip)
        status
        update_preview
        view.invalidate
      end

      def onLButtonDoubleClick(_flags, _x, _y, view)
        finish(view, false)
      end

      def onRButtonDown(_flags, _x, _y, view)
        finish(view, false)
        true
      end

      def onReturn(view)
        finish(view, false)
      end

      def onUserText(text, view)
        return if @points.empty? || !@cursor
        len = begin
          text.to_l
        rescue ArgumentError
          UI.beep
          return
        end
        dir = @points[-1].vector_to(@cursor)
        return unless dir.valid?
        dir.length = len
        add_point(@points[-1].offset(dir), view)
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when VK_RIGHT then @lock = @lock == :x ? nil : :x
        when VK_LEFT then @lock = @lock == :y ? nil : :y
        when VK_UP then @lock = @lock == :z ? nil : :z
        when VK_DOWN then @lock = nil
        when VK_BACK
          @points.pop
          update_preview
        when CONSTRAIN_MODIFIER_KEY
          view.lock_inference(@ip, @ip_prev) if @ip.valid? && !@points.empty?
        else
          return false
        end
        view.invalidate
        true
      end

      def onKeyUp(key, _repeat, _flags, view)
        view.lock_inference if key == CONSTRAIN_MODIFIER_KEY && DrawTool.locked?(view)
        false
      end

      def local_points(pts)
        inv = edit_tr.inverse
        pts.map { |p| (inv * p).to_a }
      end

      # Live preview of the real profile (cheap: pure-Ruby rings + one
      # batched draw call).
      def update_preview
        pts = @points.dup
        pts << @cursor if @cursor && (pts.empty? || pts[-1].distance(@cursor) > 0.001)
        @preview = []
        return if pts.size < 2
        prep = Sweep.prepare(local_points(pts), false, nil)
        return if prep[:points].size < 2
        spec = Controller.spec_for(Controller.mode)
        loop_sets = if Controller.mode == 'assembly'
                      flip = spec['flip'] ? true : false
                      (spec['rows'] || []).select { |r| r['type'] != 'repeat' && r['visible'] != false }.map do |r|
                        Profiles.to_inches(Profiles.placed_loops(Assembly.row_profile_spec(Assembly.apply_global_flip(r, flip))))
                      end
                    else
                      [Profiles.to_inches(Profiles.placed_loops(spec))]
                    end
        tr = edit_tr
        loop_sets.each do |loops|
          next if loops.empty?
          Sweep.preview_lines(prep, loops, 150).each { |q| @preview << tr * Geom::Point3d.new(q[0], q[1], q[2]) }
        end
      rescue StandardError => e
        puts "Banian preview: #{e.message}"
        @preview = []
      end

      def finish(view, closed)
        if @points.size >= 2
          pts = local_points(@points)
          g = Controller.build_path(pts, closed && @points.size >= 3)
          Sketchup.active_model.selection.clear
          Sketchup.active_model.selection.add(g) if g
        end
        @points = []
        @preview = []
        @lock = nil
        status
        view.invalidate
      end

      def draw(view)
        unless @preview.empty?
          view.line_width = 1
          view.drawing_color = COLOR_PREVIEW
          view.draw(GL_LINES, @preview)
        end
        unless @points.empty?
          pts = @points.dup
          pts << @cursor if @cursor
          view.line_width = 2
          view.drawing_color = @lock ? { x: 'red', y: 'green', z: 'blue' }[@lock] : COLOR_PATH
          view.draw(GL_LINE_STRIP, pts)
          view.draw_points(@points, 7, 2, COLOR_PATH)
          if @cursor && near_first?(view, @cursor)
            view.draw_points([@points[0]], 14, 1, 'green')
          end
        end
        @ip.draw(view) if @ip.display?
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @points.each { |p| bb.add(p) }
        bb.add(@cursor) if @cursor
        @preview.each { |q| bb.add(q) }
        bb
      end
    end
  end
end
