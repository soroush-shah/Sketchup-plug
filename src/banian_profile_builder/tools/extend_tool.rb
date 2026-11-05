# encoding: UTF-8
# Banian Profile Builder - Extend tool (members and assemblies).
# Hover an end of a Banian object (selected or under the cursor), click,
# move and click again - or type a value:
#   500    extend by 500       -200   shorten by 200
#   3000s  set the total length to 3000

module BanianStudio
  module ProfileBuilder
    class ExtendTool
      PICK_PX = 18

      def initialize
        @ip = Sketchup::InputPoint.new
        @hover = nil
        @drag = nil
        @delta = 0.0
      end

      def activate
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
        Sketchup.status_text = if @drag
                                 'Move and click, or type a distance (e.g. 500, -200, or 3000s for total length). Esc = cancel.'
                               else
                                 'Banian Extend: hover an end of a profile or assembly and click.'
                               end
        Sketchup.vcb_label = @drag ? 'Distance' : 'Length'
      end

      def onCancel(_r, view)
        @drag = nil
        status
        view.invalidate
      end

      def world_tr(g)
        Sketchup.active_model.edit_transform * g.transformation
      end

      def candidates(view, x, y)
        model = Sketchup.active_model
        list = Controller.selected_pb
        ph = view.pick_helper
        ph.do_pick(x, y)
        e = ph.best_picked
        list += [e] if Builder.pb?(e) && !list.include?(e)
        ctx = model.active_entities.parent
        list.select { |g| g.valid? && g.parent == ctx }
      end

      def find_end(view, x, y)
        best = nil
        candidates(view, x, y).each do |g|
          info = Builder.read(g)
          next unless info && !info['closed'] && info['path'].size >= 2
          tr = world_tr(g)
          pw = info['path'].map { |p| tr * Geom::Point3d.new(*p) }
          [[true, pw[0], pw[1]], [false, pw[-1], pw[-2]]].each do |at_start, e, nxt|
            s = view.screen_coords(e)
            d = Math.hypot(s.x - x, s.y - y)
            next if d > PICK_PX || (best && best[:d] < d)
            dir = nxt.vector_to(e)
            next unless dir.valid?
            best = { d: d, group: g, at_start: at_start, end: e, dir: dir.normalize, path: pw, tr: tr }
          end
        end
        best
      end

      def onMouseMove(_flags, x, y, view)
        if @drag
          @ip.pick(view, x, y)
          v = @drag[:end].vector_to(@ip.position)
          @delta = v.dot(@drag[:dir])
          Sketchup.vcb_value = @delta.to_l.to_s
          view.tooltip = "#{@delta.to_l}"
        else
          @hover = find_end(view, x, y)
        end
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        if @drag
          apply(@delta)
        elsif @hover
          @drag = @hover
          @delta = 0.0
        end
        status
        view.invalidate
      end

      def onUserText(text, view)
        return unless @drag
        txt = text.strip
        total = txt =~ /s\z/i
        txt = txt.sub(/s\z/i, '') if total
        val = begin
          txt.to_l.to_f
        rescue ArgumentError
          UI.beep
          return
        end
        if total
          cur = 0.0
          @drag[:path].each_cons(2) { |a, b| cur += a.distance(b) }
          val -= cur
        end
        apply(val)
        view.invalidate
      end

      def apply(delta)
        d = @drag
        @drag = nil
        return if delta.abs < 1e-6
        model = Sketchup.active_model
        world = d[:path].map(&:to_a)
        new_world = PathOps.extend_end(world, d[:at_start], delta)
        inv = d[:tr].inverse
        local = new_world.map { |p| (inv * Geom::Point3d.new(*p)).to_a }
        model.start_operation('Banian Extend', true)
        Builder.rebuild(d[:group], nil, local)
        model.commit_operation
        Controller.push_selection if Controller.visible?
        status
      rescue StandardError => e
        model.abort_operation if model
        Controller.report_error(e)
      end

      def draw(view)
        if @drag
          e = @drag[:end]
          tgt = @delta.abs > 1e-6 ? e.offset(@drag[:dir], @delta) : e
          view.line_width = 3
          view.drawing_color = @delta >= 0 ? 'green' : 'red'
          view.draw(GL_LINES, [e, tgt])
          view.draw_points([e], 10, 1, 'blue')
          view.draw_points([tgt], 8, 2, 'blue')
          @ip.draw(view) if @ip.display?
        elsif @hover
          view.draw_points([@hover[:end]], 14, 1, 'orange')
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        if @drag
          bb.add(@drag[:end])
          bb.add(@drag[:end].offset(@drag[:dir], @delta)) if @delta.abs > 1e-6
        end
        bb
      end
    end
  end
end
