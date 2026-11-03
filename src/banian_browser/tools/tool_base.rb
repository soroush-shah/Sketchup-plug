module BanianStudio
  module BanianBrowser
    # Shared helpers for the interactive tools.
    module ToolBase
      CURSORS = {}
      ALT_KEY = defined?(ALT_MODIFIER_KEY) ? ALT_MODIFIER_KEY : 18
      ALT_MASK = defined?(ALT_MODIFIER_MASK) ? ALT_MODIFIER_MASK : 32

      def self.cursor(name, x = 2, y = 22)
        return CURSORS[name] if CURSORS.key?(name)
        file = File.join(PLUGIN_DIR, 'icons', "cursor_#{name}.png")
        CURSORS[name] = File.exist?(file) ? UI.create_cursor(file, x, y) : 0
      end

      # Picks the face under the cursor together with its full transformation.
      # Returns [face, transformation, path] or nil.
      def pick_face(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y)
        face = ph.picked_face
        return nil unless face
        path = nil
        (0...ph.count).each do |i|
          if ph.leaf_at(i) == face
            path = ph.path_at(i)
            break
          end
        end
        [face, transformation_of(path), path || [face]]
      end

      def transformation_of(path)
        tr = Geom::Transformation.new
        return tr unless path
        path.each { |e| tr *= e.transformation if e.respond_to?(:transformation) }
        tr
      end

      def front_facing?(face, tr, view)
        n = face.normal.transform(tr)
        cam = view.camera
        if cam.perspective?
          pt = face.vertices.first.position.transform(tr)
          (n % (cam.eye - pt)) >= 0
        else
          (n % cam.direction) <= 0
        end
      end

      # Material visible under the cursor (face side, or inherited from groups).
      def material_under(view, x, y)
        hit = pick_face(view, x, y)
        if hit
          face, tr, path = hit
          m = front_facing?(face, tr, view) ? face.material : face.back_material
          return m if m
          path.reverse_each do |e|
            return e.material if (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.material
          end
          return nil
        end
        ph = view.pick_helper
        ph.do_pick(x, y)
        be = ph.best_picked
        be && be.respond_to?(:material) ? be.material : nil
      end

      def draw_box(view, corners, color = 'DodgerBlue', width = 2)
        view.line_width = width
        view.drawing_color = color
        idx = [0, 1, 1, 3, 3, 2, 2, 0, 4, 5, 5, 7, 7, 6, 6, 4, 0, 4, 1, 5, 2, 6, 3, 7]
        view.draw(GL_LINES, idx.map { |i| corners[i] })
      end

      def bounds_corners(bb, tr)
        (0..7).map { |i| bb.corner(i).transform(tr) }
      end
    end
  end
end
