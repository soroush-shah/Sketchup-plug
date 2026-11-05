# Converts a SketchUp face into a local 2D region + frame transformation.
module BanianStudio
  module FloorStudio
    module Region
      module_function

      # Returns { :region, :frame (local -> parent coords), :world_origin }
      def from_face(face, p)
        n = face.normal
        z = n.clone
        horizontal = n.z.abs > 0.985
        z.reverse! if horizontal && z.z < 0
        z.reverse! if p[:flip]

        x = nil
        if p[:align].to_s == 'world'
          if horizontal
            x = Geom::Vector3d.new(1, 0, 0)
          else
            x = Geom::Vector3d.new(0, 0, 1).cross(z)
            x = Geom::Vector3d.new(1, 0, 0) if x.length < 1.0e-6
          end
          # (re-orthogonalised below via cross products)
        else
          best = nil
          face.outer_loop.edges.each do |e|
            l = e.length
            best = e if best.nil? || l > best.length + 1.0e-6
          end
          x = best.line[1].clone
          # keep direction stable: prefer +X / +Z
          x.reverse! if x.x < -1.0e-6 || (x.x.abs < 1.0e-6 && (x.y < -1.0e-6 || x.z < -1.0e-6))
        end
        x.normalize!
        y = z.cross(x)
        y.normalize!
        x = y.cross(z)
        x.normalize!
        origin = face.outer_loop.vertices.first.position
        frame = Geom::Transformation.axes(origin, x, y, z)
        inv = frame.inverse
        outer = nil
        holes = []
        face.loops.each do |lp|
          pts = lp.vertices.map do |v|
            q = v.position.transform(inv)
            [q.x.to_f, q.y.to_f]
          end
          if lp.outer?
            outer = pts
          else
            holes << pts
          end
        end
        bb = Geom2D.bbox(outer)
        shift = Geom::Point3d.new(bb[0], bb[1], 0).transform(frame)
        frame = Geom::Transformation.axes(shift, x, y, z)
        mv = lambda { |pt| [pt[0] - bb[0], pt[1] - bb[1]] }
        region = {
          :outer => Geom2D.ccw(outer.map(&mv)),
          :holes => holes.map { |h| Geom2D.ccw(h.map(&mv)) }
        }
        wo = Geom::Point3d.new(0, 0, 0).transform(frame.inverse)
        { :region => region, :frame => frame, :world_origin => [wo.x.to_f, wo.y.to_f] }
      end

      def to_json_h(region)
        { 'outer' => region[:outer], 'holes' => region[:holes] }
      end

      def from_json_h(h)
        { :outer => h['outer'].map { |p| [p[0].to_f, p[1].to_f] },
          :holes => (h['holes'] || []).map { |l| l.map { |p| [p[0].to_f, p[1].to_f] } } }
      end

      # Sample region shown in preview when nothing is selected (4m x 3m).
      def sample
        mm = 1 / 25.4
        { :outer => [[0, 0], [4000 * mm, 0], [4000 * mm, 3000 * mm], [0, 3000 * mm]],
          :holes => [[[2600 * mm, 1700 * mm], [3000 * mm, 1700 * mm], [3000 * mm, 2100 * mm], [2600 * mm, 2100 * mm]]] }
      end
    end
  end
end
