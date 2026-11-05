# encoding: UTF-8
# Banian Profile Builder - polyline helpers (pure Ruby, inches).

module BanianStudio
  module ProfileBuilder
    module PathOps
      V = Vec
      EPS = 1e-6

      module_function

      # Removes duplicate points and (optionally) collinear interior points.
      def clean(points, closed, drop_collinear = true)
        pts = []
        points.each do |p|
          p = [p[0].to_f, p[1].to_f, p[2].to_f]
          pts << p if pts.empty? || V.dist(pts[-1], p) > 1e-4
        end
        if closed
          pts.pop while pts.size > 1 && V.dist(pts[0], pts[-1]) <= 1e-4
        end
        return pts unless drop_collinear
        loop_again = true
        while loop_again && pts.size > (closed ? 3 : 2)
          loop_again = false
          n = pts.size
          range = closed ? (0...n) : (1...(n - 1))
          range.each do |i|
            a = pts[(i - 1) % n]; b = pts[i]; c = pts[(i + 1) % n]
            t1 = V.norm(V.sub(b, a)); t2 = V.norm(V.sub(c, b))
            next unless t1 && t2
            if V.dot(t1, t2) > 1.0 - 1e-9
              pts.delete_at(i)
              loop_again = true
              break
            end
          end
        end
        pts
      end

      def segments(points, closed)
        n = points.size
        return [] if n < 2
        segs = []
        (0...(n - 1)).each { |i| segs << [points[i], points[i + 1]] }
        segs << [points[-1], points[0]] if closed && n > 2
        segs
      end

      # Cumulative distance at each vertex (+ closing length for closed paths).
      def cumulative(points, closed)
        cum = [0.0]
        segments(points, closed).each { |a, b| cum << cum[-1] + V.dist(a, b) }
        cum
      end

      def length(points, closed)
        cumulative(points, closed)[-1]
      end

      # Point, segment index and direction at arc-length s.
      def point_at(points, closed, s, cum = nil)
        cum ||= cumulative(points, closed)
        segs = segments(points, closed)
        return [points[0], 0, [1.0, 0.0, 0.0]] if segs.empty?
        total = cum[-1]
        s = closed ? s % total : [[s, 0.0].max, total].min
        i = 0
        i += 1 while i < segs.size - 1 && cum[i + 1] < s
        a, b = segs[i]
        l = cum[i + 1] - cum[i]
        t = l > EPS ? (s - cum[i]) / l : 0.0
        dir = V.norm(V.sub(b, a)) || [1.0, 0.0, 0.0]
        [V.lerp(a, b, t), i, dir]
      end

      # Open sub-polyline between a and b (a < b). For closed paths b may go
      # past the total length (wraps around).
      def subpath(points, closed, a, b)
        return [] if b - a < 1e-4
        cum = cumulative(points, closed)
        if closed
          pts2 = points + points + [points[0]]
          cum2 = cumulative(pts2, false)
        else
          pts2 = points
          cum2 = cum
        end
        out = [interp(pts2, cum2, a)]
        pts2.each_with_index do |p, i|
          out << p if cum2[i] > a + 1e-6 && cum2[i] < b - 1e-6
        end
        out << interp(pts2, cum2, b)
        clean(out, false, false)
      end

      def interp(pts, cum, s)
        return pts[0] if s <= 0
        (0...(pts.size - 1)).each do |i|
          next unless s <= cum[i + 1] + 1e-9
          l = cum[i + 1] - cum[i]
          t = l > EPS ? (s - cum[i]) / l : 0.0
          return V.lerp(pts[i], pts[i + 1], t)
        end
        pts[-1]
      end

      # Merge cut ranges and return the kept ranges. nil => keep whole path.
      def kept_ranges(total, closed, cuts)
        cs = cuts.map { |a, b| [[a, 0.0].max, [b, total].min] }.select { |a, b| b - a > 1e-4 }
        return nil if cs.empty?
        cs.sort_by!(&:first)
        merged = []
        cs.each do |c|
          if merged.empty? || c[0] > merged[-1][1]
            merged << c.dup
          else
            merged[-1][1] = [merged[-1][1], c[1]].max
          end
        end
        kept = []
        if closed
          merged.each_with_index do |c, i|
            nxt = merged[(i + 1) % merged.size]
            a = c[1]
            b = i == merged.size - 1 ? nxt[0] + total : nxt[0]
            kept << [a, b] if b - a > 1e-4
          end
        else
          cur = 0.0
          merged.each do |c|
            kept << [cur, c[0]] if c[0] - cur > 1e-4
            cur = c[1]
          end
          kept << [cur, total] if total - cur > 1e-4
        end
        kept
      end

      # Change an open path at one end. delta > 0 extends along the end
      # direction, delta < 0 trims back along the polyline.
      def extend_end(points, at_start, delta)
        pts = points.map(&:dup)
        pts.reverse! if at_start
        if delta >= 0
          dir = V.norm(V.sub(pts[-1], pts[-2])) || [1.0, 0.0, 0.0]
          pts[-1] = V.add(pts[-1], V.mul(dir, delta))
        else
          total = length(pts, false)
          keep = total + delta
          keep = 0.01 if keep < 0.01
          pts = subpath(pts, false, 0.0, keep)
        end
        pts.reverse! if at_start
        pts
      end
    end
  end
end
