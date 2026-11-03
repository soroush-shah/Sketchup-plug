module BanianStudio
  module BanianBrowser
    # Paint bucket for the current material.
    #   click        -> paints the clicked group / component / face (active context)
    #   Shift+click  -> paints only the face under the cursor (even inside groups)
    #   Alt/Cmd      -> sample a material (eyedropper) without leaving the tool
    class MaterialBucketTool
      include ToolBase

      def activate
        @shift = false
        @alt = false
        @target = nil
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
        mat = MaterialOps.current
        name = mat ? Util.utf8(mat.display_name) : '-'
        Sketchup.status_text = "#{I18n.t(:bucket_status)}   [#{name}]"
      end

      def onSetCursor
        c = if @alt
              ToolBase.cursor('dropper', 3, 21)
            elsif @shift
              ToolBase.cursor('bucket_face', 4, 20)
            else
              ToolBase.cursor('bucket', 4, 20)
            end
        UI.set_cursor(c) if c && c > 0
      end

      def onKeyDown(key, _repeat, _flags, view)
        @shift = true if key == CONSTRAIN_MODIFIER_KEY
        @alt = true if key == ToolBase::ALT_KEY
        onSetCursor
        view.invalidate
        false
      end

      def onKeyUp(key, _repeat, _flags, view)
        @shift = false if key == CONSTRAIN_MODIFIER_KEY
        @alt = false if key == ToolBase::ALT_KEY
        onSetCursor
        view.invalidate
        false
      end

      def onMouseMove(flags, x, y, view)
        @shift = (flags & CONSTRAIN_MODIFIER_MASK) != 0
        @alt = (flags & ToolBase::ALT_MASK) != 0
        @target = find_target(view, x, y)
        view.invalidate
      end

      def find_target(view, x, y)
        if @shift
          hit = pick_face(view, x, y)
          return nil unless hit
          face, tr, _path = hit
          { :face => face, :tr => tr, :front => front_facing?(face, tr, view) }
        else
          ph = view.pick_helper
          ph.do_pick(x, y)
          e = ph.best_picked
          return nil unless e && e.respond_to?(:material=) && !e.is_a?(Sketchup::Edge)
          if e.is_a?(Sketchup::Face)
            { :face => e, :tr => Geom::Transformation.new, :front => front_facing?(e, Geom::Transformation.new, view) }
          else
            { :entity => e }
          end
        end
      end

      def onLButtonDown(flags, x, y, view)
        if (flags & ToolBase::ALT_MASK) != 0
          m = material_under(view, x, y)
          MaterialOps.current = m if m
          status
          return
        end
        mat = MaterialOps.current
        unless mat
          UI.messagebox(I18n.t(:pick_first))
          return
        end
        t = find_target(view, x, y)
        return UI.beep unless t
        model = Sketchup.active_model
        model.start_operation(I18n.t(:op_paint), true)
        if t[:face]
          if t[:front]
            t[:face].material = mat
          else
            t[:face].back_material = mat
          end
        else
          t[:entity].material = mat
        end
        model.commit_operation
        view.invalidate
      end

      def draw(view)
        return unless @target
        if @target[:face]
          f = @target[:face]
          return unless f.valid?
          pts = f.outer_loop.vertices.map { |v| v.position.transform(@target[:tr]) }
          view.line_width = 3
          view.drawing_color = 'Orange'
          view.draw(GL_LINE_LOOP, pts)
        elsif @target[:entity].valid?
          e = @target[:entity]
          draw_box(view, bounds_corners(Util.definition_of(e).bounds, e.transformation), 'Orange', 2)
        end
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
