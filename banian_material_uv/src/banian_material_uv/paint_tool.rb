# encoding: UTF-8
module BanianStudio
  module MaterialUV
    # Interactive tool: hover shows what will be painted, click maps the
    # texture. Shift = single face, Ctrl = whole object, Alt = pick material.
    class PaintTool
      CURSOR_PATH = File.join(PLUGIN_DIR, 'icons', 'cursor.png')

      def initialize
        @hover = nil      # [face, tr, inst]
        @preview = []     # array of arrays of world points (edge loops)
        @shift = false
        @ctrl = false
        @cursor = nil
      end

      def activate
        @cursor = UI.create_cursor(CURSOR_PATH, 3, 3) if File.exist?(CURSOR_PATH)
        Sketchup.status_text = T.t('tool')
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        Sketchup.status_text = T.t('tool')
        view.invalidate
      end

      def onSetCursor
        UI.set_cursor(@cursor) if @cursor
      end

      def scope
        return 'face' if @shift
        return 'object' if @ctrl
        Settings.get['tool_scope'] || 'surface'
      end

      def onKeyDown(key, _repeat, _flags, view)
        @shift = true if key == VK_SHIFT
        @ctrl = true if key == VK_CONTROL || (defined?(VK_COMMAND) && key == VK_COMMAND)
        refresh_preview(view)
        false
      end

      def onKeyUp(key, _repeat, _flags, view)
        @shift = false if key == VK_SHIFT
        @ctrl = false if key == VK_CONTROL || (defined?(VK_COMMAND) && key == VK_COMMAND)
        refresh_preview(view)
        false
      end

      def pick(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y)
        ph.count.times do |i|
          leaf = ph.leaf_at(i)
          next unless leaf.is_a?(Sketchup::Face)
          path = ph.path_at(i) || []
          inst = path.reverse.find { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          return [leaf, ph.transformation_at(i), inst]
        end
        nil
      end

      def onMouseMove(_flags, x, y, view)
        h = pick(view, x, y)
        if h.nil? || @hover.nil? || h[0] != @hover[0]
          @hover = h
          refresh_preview(view)
        end
      end

      def refresh_preview(view)
        @preview = []
        if @hover
          targets = Mapper.targets_for_face(@hover[0], @hover[1], @hover[2], scope)
          targets.first(3000).each do |t|
            t.face.edges.each do |e|
              next if (e.soft? || e.smooth?) && targets.size > 1 && scope != 'face'
              @preview << [t.tr * e.start.position, t.tr * e.end.position]
            end
          end
          if @preview.empty?
            targets.first(3000).each do |t|
              pts = t.face.outer_loop.vertices.map { |v| t.tr * v.position }
              pts.each_with_index { |p, i| @preview << [p, pts[(i + 1) % pts.size]] }
            end
          end
        end
        view.invalidate
      end

      def draw(view)
        return if @preview.empty?
        view.drawing_color = Sketchup::Color.new(255, 140, 0)
        view.line_width = 3
        pts = []
        @preview.each { |a, b| pts << a; pts << b }
        view.draw(GL_LINES, pts)
      end

      def onLButtonDown(flags, x, y, view)
        h = pick(view, x, y)
        return unless h
        face, tr, inst = h
        alt = (flags & ALT_MODIFIER_MASK) != 0 rescue false
        if alt
          m = face.material || (inst && inst.material)
          if m
            Settings.update('material' => m.name, 'mat_source' => 'chosen')
            Sketchup.active_model.materials.current = m rescue nil
            Dialog.notify_material_picked
          end
          return
        end
        sc = if (flags & CONSTRAIN_MODIFIER_MASK) != 0 then 'face'
             elsif (flags & COPY_MODIFIER_MASK) != 0 then 'object'
             else scope
             end
        targets = Mapper.targets_for_face(face, tr, inst, sc)
        start = targets.find { |t| t.face == face }
        MaterialUV.run(targets, {}, start)
        @hover = nil
        refresh_preview(view)
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @preview.each { |a, b| bb.add(a); bb.add(b) }
        bb
      end
    end
  end
end
