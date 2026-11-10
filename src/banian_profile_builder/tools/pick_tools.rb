# encoding: UTF-8
# Banian Profile Builder - picking tools.
#  PickFaceTool : click any face (even inside groups) to save it as profile.
#  MatchTool    : eyedropper - click a Banian object to reuse its settings,
#                 then draw the new path right away.

module BanianStudio
  module ProfileBuilder
    class PickFaceTool
      def activate
        @ip = Sketchup::InputPoint.new
        @face = nil
        Sketchup.status_text = 'Banian: click a face to save it as your own profile. Esc = cancel.'
      end

      def deactivate(view)
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @face = @ip.face
        @tr = @ip.transformation
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, _view)
        unless @face && @face.valid?
          UI.beep
          return
        end
        face = @face
        Sketchup.active_model.select_tool(nil)
        Controller.add_face_profile(face)
      end

      def onCancel(_r, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        return unless @face && @face.valid?
        view.line_width = 4
        view.drawing_color = Sketchup::Color.new(31, 111, 235)
        @face.loops.each do |lp|
          pts = lp.vertices.map { |v| @tr * v.position }
          view.draw(GL_LINE_LOOP, pts)
        end
      end
    end

    class MatchTool
      EDGES = [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]].freeze

      def activate
        @hover = nil
        Sketchup.status_text = 'Banian Eyedropper: click a Banian profile or assembly to reuse it, then draw the new path.'
      end

      def deactivate(view)
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        e = ph.best_picked
        @hover = Builder.pb?(e) ? e : nil
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, _view)
        unless @hover
          UI.beep
          return
        end
        kind = Controller.adopt(@hover)
        return unless kind
        Controller.show
        Controller.send_js('type' => 'tab', 'tab' => kind)
        Sketchup.active_model.select_tool(DrawTool.new)
      end

      def draw(view)
        return unless @hover && @hover.valid?
        bb = @hover.bounds
        tr = Sketchup.active_model.edit_transform
        pts = []
        EDGES.each { |a, b| pts << tr * bb.corner(a) << tr * bb.corner(b) }
        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(45, 164, 78)
        view.draw(GL_LINES, pts)
      end
    end
  end
end
