# encoding: UTF-8
# Banian Profile Builder - Edit Path tool.
# Edit the path directly on the object - no need to open groups:
#  * drag a square handle (or click it, move, click) to move a point
#  * click a round "+" handle in the middle of a segment to add a point
#  * hover a point and press Delete to remove it
#  * type a distance while moving for an exact move
#  * arrow keys lock the move to an axis, Esc cancels the move
# The object rebuilds instantly with a live wireframe while moving.

module BanianStudio
  module ProfileBuilder
    class PathEditTool
      HANDLE_PX = 12
      VK_DEL = 46
      COLOR = Sketchup::Color.new(220, 60, 40)
      PREVIEW = Sketchup::Color.new(40, 110, 200)

      def initialize
        @ip = Sketchup::InputPoint.new
        @target = nil
        @hover = nil
        @drag = nil
        @lock = nil
        @preview = []
      end

      def activate
        g = Controller.selected_pb.first
        load_target(g) if g
        status
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        status
        view.invalidate
      end

      def enableVCB?
        true
      end

      def status
        Sketchup.status_text = if @target.nil?
                                 'Banian Edit Path: click a Banian profile or assembly.'
                               elsif @drag
                                 'Move and click (or release), or type a distance. Arrow keys lock an axis. Esc = cancel.'
                               else
                                 'Drag a square to move a point, click a + to add one, hover a point and press Delete to remove it.'
                               end
        Sketchup.vcb_label = 'Distance'
      end

      def load_target(g)
        info = Builder.read(g)
        return unless info
        @target = g
        @closed = info['closed']
        @path = info['path']
        @tr = Sketchup.active_model.edit_transform * g.transformation
        @world = @path.map { |p| @tr * Geom::Point3d.new(*p) }
        @spec = info['spec']
        @kind = info['kind']
      end

      def mids
        n = @world.size
        segs = @closed ? n : n - 1
        (0...segs).map { |i| Geom.linear_combination(0.5, @world[i], 0.5, @world[(i + 1) % n]) }
      end

      def find_hover(view, x, y)
        return nil unless @target
        best = nil
        @world.each_with_index do |p, i|
          s = view.screen_coords(p)
          d = Math.hypot(s.x - x, s.y - y)
          best = [:vertex, i, d] if d < HANDLE_PX && (best.nil? || d < best[2])
        end
        return best if best
        mids.each_with_index do |p, i|
          s = view.screen_coords(p)
          d = Math.hypot(s.x - x, s.y - y)
          best = [:mid, i, d] if d < HANDLE_PX && (best.nil? || d < best[2])
        end
        best
      end

      def onMouseMove(_flags, x, y, view)
        if @drag
          @ip.pick(view, x, y)
          pt = @ip.position
          if @lock
            ax = (Sketchup.active_model.edit_transform * Geom::Vector3d.new(*{ x: [1, 0, 0], y: [0, 1, 0], z: [0, 0, 1] }[@lock])).normalize
            pt = pt.project_to_line([@drag[:start], ax])
          end
          @drag[:pt] = pt
          @drag[:moved] ||= Math.hypot(x - @drag[:sx], y - @drag[:sy]) > 4
          Sketchup.vcb_value = @drag[:start].distance(pt).to_l.to_s
          update_preview
        else
          @hover = find_hover(view, x, y)
        end
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        if @drag
          commit(view)
          return
        end
        h = find_hover(view, x, y)
        unless h
          ph = view.pick_helper
          ph.do_pick(x, y)
          e = ph.best_picked
          if Builder.pb?(e)
            load_target(e)
            Sketchup.active_model.selection.clear
            Sketchup.active_model.selection.add(e)
          end
          status
          view.invalidate
          return
        end
        type, i, = h
        if type == :mid
          @world.insert(i + 1, mids[i])
          i += 1
        end
        @drag = { index: i, start: @world[i].clone, pt: @world[i].clone, sx: x, sy: y, moved: false }
        status
        update_preview
        view.invalidate
      end

      def onLButtonUp(_flags, _x, _y, view)
        commit(view) if @drag && @drag[:moved]
      end

      def onUserText(text, view)
        return unless @drag
        len = begin
          text.to_l
        rescue ArgumentError
          UI.beep
          return
        end
        dir = @drag[:start].vector_to(@drag[:pt])
        return UI.beep unless dir.valid?
        dir.length = len
        @drag[:pt] = @drag[:start].offset(dir)
        commit(view)
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when VK_RIGHT then @lock = @lock == :x ? nil : :x
        when VK_LEFT then @lock = @lock == :y ? nil : :y
        when VK_UP then @lock = @lock == :z ? nil : :z
        when VK_DOWN then @lock = nil
        when VK_DEL, 8
          if !@drag && @hover && @hover[0] == :vertex
            min = @closed ? 3 : 2
            if @world.size > min
              @world.delete_at(@hover[1])
              @hover = nil
              apply(view)
            else
              UI.beep
            end
          end
        else
          return false
        end
        view.invalidate
        true
      end

      def onCancel(_r, view)
        if @drag
          @world.delete_at(@drag[:index]) if @world.size > @path.size
          @world = @path.map { |p| @tr * Geom::Point3d.new(*p) }
          @drag = nil
          @preview = []
        end
        status
        view.invalidate
      end

      def current_world
        pts = @world.map(&:clone)
        pts[@drag[:index]] = @drag[:pt] if @drag
        pts
      end

      def update_preview
        inv = @tr.inverse
        local = current_world.map { |p| (inv * p).to_a }
        info = Builder.read(@target)
        prep = Sweep.prepare(local, @closed, info ? info['up'] : nil)
        loop_sets = if @kind == 'assembly'
                      flip = @spec['flip'] ? true : false
                      (@spec['rows'] || []).select { |r| r['type'] == 'layer' && r['visible'] != false }.map do |r|
                        Profiles.to_inches(Profiles.placed_loops(Assembly.row_profile_spec(Assembly.apply_global_flip(r, flip))))
                      end
                    else
                      [Profiles.to_inches(Profiles.placed_loops(@spec))]
                    end
        @preview = []
        loop_sets.each do |loops|
          next if loops.empty?
          Sweep.preview_lines(prep, loops, 150).each { |q| @preview << @tr * Geom::Point3d.new(*q) }
        end
      rescue StandardError
        @preview = []
      end

      def commit(view)
        @world = current_world
        @drag = nil
        apply(view)
      end

      def apply(view)
        model = Sketchup.active_model
        inv = @tr.inverse
        local = @world.map { |p| (inv * p).to_a }
        model.start_operation('Banian Edit Path', true)
        Builder.rebuild(@target, nil, local)
        model.commit_operation
        load_target(@target)
        @preview = []
        Controller.push_selection if Controller.visible?
        status
        view.invalidate
      rescue StandardError => e
        model.abort_operation
        Controller.report_error(e)
      end

      def draw(view)
        return unless @target && @target.valid?
        pts = current_world
        view.line_width = 2
        view.line_stipple = '-'
        view.drawing_color = COLOR
        view.draw(@closed ? GL_LINE_LOOP : GL_LINE_STRIP, pts)
        view.line_stipple = ''
        unless @preview.empty?
          view.line_width = 1
          view.drawing_color = PREVIEW
          view.draw(GL_LINES, @preview)
        end
        view.draw_points(pts, 10, 2, COLOR)
        view.draw_points(mids, 10, 3, 'green') unless @drag
        if @hover && !@drag
          p = @hover[0] == :vertex ? @world[@hover[1]] : mids[@hover[1]]
          view.draw_points([p], 16, 1, 'orange') if p
        end
        @ip.draw(view) if @drag && @ip.display?
      end

      def getExtents
        bb = Geom::BoundingBox.new
        (@world || []).each { |p| bb.add(p) }
        bb.add(@drag[:pt]) if @drag
        @preview.each { |q| bb.add(q) }
        bb
      end
    end
  end
end
