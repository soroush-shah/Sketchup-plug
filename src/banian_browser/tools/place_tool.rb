module BanianStudio
  module BanianBrowser
    # Places a library model like SketchUp's own "place component", but the model can
    # be turned before clicking:
    #
    #   Up / Down arrows   rotate by the placing step (Settings: 90 deg by default)
    #   Left / Right       rotate by the same step the other way round
    #   type an angle      exact rotation (VCB), e.g. 45 + Enter
    #   Ctrl (Option)      keep placing copies after each click
    #   Esc                cancel
    #
    # The preview is drawn (edges of the model, or its box for very heavy models), so
    # nothing is added to the model until the click and undo stays clean.
    class PlaceTool
      include ToolBase

      MAX_SEGMENTS = 40_000

      class << self
        # The placing tool in use, so arrow keys pressed while the Banian window still
        # has keyboard focus can be forwarded to it.
        attr_accessor :current
      end

      def initialize(definition)
        @defn = definition
        @bb = definition.bounds
        @angle = 0.0
        @multi = false
      end

      def activate
        @ip = Sketchup::InputPoint.new
        @tr = nil
        @segments = collect_segments
        PlaceTool.current = self
        Dialog.emit('placing', true)
        status
      end

      def resume(view)
        status
        view.invalidate
      end

      def deactivate(view)
        PlaceTool.current = nil if PlaceTool.current == self
        Dialog.emit('placing', false)
        view.invalidate
      end

      # sign: +1 / -1 steps (forwarded arrow keys)
      def turn(sign)
        @angle = (@angle + step * (sign.to_i < 0 ? -1 : 1)) % 360
        status
        view = Sketchup.active_model.active_view
        update(view) if @ip && @ip.valid?
        view.invalidate
      end

      def step
        s = Settings['place_rotate'].to_f
        s > 0 ? s : 90.0
      end

      def status
        Sketchup.status_text = format(I18n.t(:place_status), step.round(1).to_s.sub(/\.0\z/, ''))
        Sketchup.vcb_label = I18n.t(:angle)
        Sketchup.vcb_value = format('%.1f', @angle)
      end

      def enableVCB?
        true
      end

      def onUserText(text, view)
        v = text.to_s.tr(',', '.').to_f
        @angle = v % 360
        status
        update(view)
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when VK_UP, VK_RIGHT then @angle = (@angle + step) % 360
        when VK_DOWN, VK_LEFT then @angle = (@angle - step) % 360
        when COPY_MODIFIER_KEY then @multi = !@multi
        else return false
        end
        status
        update(view)
        true
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        view.tooltip = @ip.tooltip if @ip.valid?
        update(view)
      end

      # Glue-to-face components (windows, doors, 2D) follow the face; others stay upright.
      def update(view)
        return unless @ip.valid?
        pt = @ip.position
        za = Z_AXIS.clone
        f = @ip.face
        if f && glues?
          za = f.normal.transform(@ip.transformation)
          za.normalize!
        end
        xa = za.parallel?(Z_AXIS) ? X_AXIS.clone : Z_AXIS.cross(za)
        xa.normalize!
        ya = za.cross(xa)
        ya.normalize!
        rot = Geom::Transformation.rotation(ORIGIN, Z_AXIS, @angle * Math::PI / 180.0)
        @tr = Geom::Transformation.axes(pt, xa, ya, za) * rot
        @draw_pts = nil
        view.invalidate
      end

      def glues?
        b = @defn.behavior
        b.respond_to?(:is2d?) && b.is2d?
      rescue StandardError
        false
      end

      def onLButtonDown(_flags, _x, _y, view)
        return unless @tr
        model = Sketchup.active_model
        model.start_operation(I18n.t(:op_place), true)
        inst = model.active_entities.add_instance(@defn, @tr)
        model.commit_operation
        return if @multi
        model.selection.clear
        model.selection.add(inst)
        model.select_tool(nil)
        view.invalidate
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      # ---- preview -------------------------------------------------------------------
      # Edge segments of the definition (nested components included) in its own space.
      def collect_segments
        pts = []
        walk(@defn.entities, Geom::Transformation.new, pts, 0)
        pts.length / 2 > MAX_SEGMENTS || pts.empty? ? nil : pts
      end

      def walk(ents, tr, pts, depth)
        return if depth > 12 || pts.length / 2 > MAX_SEGMENTS
        ents.each do |e|
          if e.is_a?(Sketchup::Edge)
            next if e.soft? || e.hidden?
            pts << e.start.position.transform(tr) << e.end.position.transform(tr)
          elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            next if e.hidden?
            walk(Util.definition_of(e).entities, tr * e.transformation, pts, depth + 1)
          end
          return if pts.length / 2 > MAX_SEGMENTS
        end
      end

      def draw(view)
        @ip.draw(view) if @ip.display?
        return unless @tr
        if @segments
          @draw_pts ||= @segments.map { |p| p.transform(@tr) }
          view.line_width = 1
          view.drawing_color = 'DodgerBlue'
          view.draw(GL_LINES, @draw_pts)
        else
          draw_box(view, bounds_corners(@bb, @tr), 'DodgerBlue', 2)
        end
        o = ORIGIN.transform(@tr)
        len = [@bb.diagonal * 0.2, 1.0].max
        view.line_width = 2
        view.drawing_color = 'Red'
        view.draw(GL_LINES, [o, o.offset(X_AXIS.transform(@tr), len)])
        view.drawing_color = 'Green'
        view.draw(GL_LINES, [o, o.offset(Y_AXIS.transform(@tr), len)])
      end

      def getExtents
        bb = Sketchup.active_model.bounds
        bounds_corners(@bb, @tr).each { |p| bb.add(p) } if @tr
        bb
      end
    end
  end
end
