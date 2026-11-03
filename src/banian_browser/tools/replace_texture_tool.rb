module BanianStudio
  module BanianBrowser
    # Replace Textures (Skimp style).
    #   click        -> every face in the same group / component that uses the clicked
    #                   material gets the current material; the existing UV mapping is kept
    #   Shift+click  -> the same, but everywhere in the model (all groups and components)
    #   Alt          -> pick the current material from the model (eyedropper)
    class ReplaceTextureTool
      include ToolBase

      def activate
        @hover = nil
        @shift = false
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
        Sketchup.status_text = "#{I18n.t(:replace_tex_status)}   [#{mat ? Util.utf8(mat.display_name) : '-'}]"
      end

      def onSetCursor
        c = ToolBase.cursor(@shift ? 'bucket_face' : 'bucket', 4, 20)
        UI.set_cursor(c) if c && c > 0
      end

      def onKeyDown(key, _r, _f, view)
        @shift = true if key == CONSTRAIN_MODIFIER_KEY
        view.invalidate
        false
      end

      def onKeyUp(key, _r, _f, view)
        @shift = false if key == CONSTRAIN_MODIFIER_KEY
        view.invalidate
        false
      end

      # => { face:, tr:, front:, mat:, container: } of the face under the cursor
      def target(view, x, y)
        hit = pick_face(view, x, y)
        return nil unless hit
        face, tr, _path = hit
        front = front_facing?(face, tr, view)
        mat = front ? face.material : face.back_material
        return nil unless mat
        { :face => face, :tr => tr, :front => front, :mat => mat, :container => face.parent }
      end

      def onMouseMove(flags, x, y, view)
        @shift = (flags & CONSTRAIN_MODIFIER_MASK) != 0
        @hover = target(view, x, y)
        view.tooltip = @hover ? Util.utf8(@hover[:mat].display_name) : ''
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        if (flags & ToolBase::ALT_MASK) != 0
          m = material_under(view, x, y)
          MaterialOps.current = m if m
          status
          return
        end
        dst = MaterialOps.current
        return UI.messagebox(I18n.t(:pick_first)) unless dst
        t = target(view, x, y)
        return UI.beep unless t
        return if t[:mat] == dst
        model = Sketchup.active_model
        model.start_operation(I18n.t(:op_replace_mat), true)
        n = if (flags & CONSTRAIN_MODIFIER_MASK) != 0
              MaterialOps.swap_everywhere(t[:mat], dst)
            else
              MaterialOps.swap_in(t[:container].entities, t[:mat], dst)
            end
        model.commit_operation
        Sketchup.status_text = "#{I18n.t(:replaced_faces)}: #{n}"
        @hover = nil
        view.invalidate
      end

      def draw(view)
        return unless @hover && @hover[:face].valid?
        view.line_width = 2
        view.drawing_color = @shift ? 'Red' : 'Orange'
        @hover[:container].entities.each do |e|
          next unless e.is_a?(Sketchup::Face) && (e.material == @hover[:mat] || e.back_material == @hover[:mat])
          view.draw(GL_LINE_LOOP, e.outer_loop.vertices.map { |v| v.position.transform(@hover[:tr]) })
        end
      end

      def onCancel(_r, _v)
        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
