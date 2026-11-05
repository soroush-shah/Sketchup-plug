# Pure-Ruby 2D geometry helpers (no SketchUp API) - Ruby 2.2+ compatible.
# Points are [x, y] arrays. Polygons are arrays of points (no repeated last point).
module BanianStudio
  module FloorStudio
    module Geom2D
      EPS = 1.0e-7

      module_function

      def signed_area(poly)
        a = 0.0
        n = poly.length
        n.times do |i|
          p = poly[i]
          q = poly[(i + 1) % n]
          a += p[0] * q[1] - q[0] * p[1]
        end
        a * 0.5
      end

      def area(poly)
        signed_area(poly).abs
      end

      def ccw(poly)
        signed_area(poly) < 0 ? poly.reverse : poly
      end

      def centroid(poly)
        a = signed_area(poly)
        return average(poly) if a.abs < EPS
        cx = 0.0
        cy = 0.0
        n = poly.length
        n.times do |i|
          p = poly[i]
          q = poly[(i + 1) % n]
          f = p[0] * q[1] - q[0] * p[1]
          cx += (p[0] + q[0]) * f
          cy += (p[1] + q[1]) * f
        end
        [cx / (6.0 * a), cy / (6.0 * a)]
      end

      def average(poly)
        sx = 0.0
        sy = 0.0
        poly.each { |p| sx += p[0]; sy += p[1] }
        [sx / poly.length, sy / poly.length]
      end

      def bbox(poly)
        minx = miny = Float::INFINITY
        maxx = maxy = -Float::INFINITY
        poly.each do |p|
          minx = p[0] if p[0] < minx
          maxx = p[0] if p[0] > maxx
          miny = p[1] if p[1] < miny
          maxy = p[1] if p[1] > maxy
        end
        [minx, miny, maxx, maxy]
      end

      def bbox_overlap?(a, b)
        a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3]
      end

      def rotate(pt, ang)
        c = Math.cos(ang)
        s = Math.sin(ang)
        [pt[0] * c - pt[1] * s, pt[0] * s + pt[1] * c]
      end

      # Even-odd ray casting.
      def point_in_poly?(pt, poly)
        x = pt[0]
        y = pt[1]
        inside = false
        j = poly.length - 1
        poly.each_with_index do |pi, i|
          pj = poly[j]
          if (pi[1] > y) != (pj[1] > y)
            xi = pi[0] + (y - pi[1]) * (pj[0] - pi[0]) / (pj[1] - pi[1])
            inside = !inside if x < xi
          end
          j = i
        end
        inside
      end

      # Region = { :outer => poly, :holes => [poly, ...] }
      def point_in_region?(pt, region)
        return false unless point_in_poly?(pt, region[:outer])
        region[:holes].each { |h| return false if point_in_poly?(pt, h) }
        true
      end

      # Convex CCW polygon: strictly inside test with tolerance.
      def point_in_convex?(pt, poly, tol = EPS)
        n = poly.length
        n.times do |i|
          a = poly[i]
          b = poly[(i + 1) % n]
          cross = (b[0] - a[0]) * (pt[1] - a[1]) - (b[1] - a[1]) * (pt[0] - a[0])
          len = Math.hypot(b[0] - a[0], b[1] - a[1])
          return false if cross <= tol * (len > 0 ? len : 1.0)
        end
        true
      end

      def convex?(poly)
        n = poly.length
        return false if n < 3
        sign = 0
        n.times do |i|
          a = poly[i]
          b = poly[(i + 1) % n]
          c = poly[(i + 2) % n]
          cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
          next if cr.abs < EPS
          s = cr > 0 ? 1 : -1
          return false if sign != 0 && s != sign
          sign = s
        end
        true
      end

      # Cyrus-Beck: clip segment a-b to convex CCW polygon. Returns [t0, t1] or nil.
      def clip_segment_convex(a, b, poly)
        t0 = 0.0
        t1 = 1.0
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        n = poly.length
        n.times do |i|
          p = poly[i]
          q = poly[(i + 1) % n]
          # inward normal of CCW edge p->q is (-(qy-py), qx-px)
          nx = -(q[1] - p[1])
          ny = q[0] - p[0]
          num = nx * (a[0] - p[0]) + ny * (a[1] - p[1])
          den = nx * dx + ny * dy
          if den.abs < 1.0e-14
            return nil if num < 0
          else
            t = -num / den
            if den > 0
              t0 = t if t > t0
            else
              t1 = t if t < t1
            end
            return nil if t0 > t1
          end
        end
        [t0, t1]
      end

      def seg_intersect_param(a, b, c, d)
        # returns t on a-b where it crosses c-d (proper or touching), or nil
        rx = b[0] - a[0]
        ry = b[1] - a[1]
        sx = d[0] - c[0]
        sy = d[1] - c[1]
        den = rx * sy - ry * sx
        return nil if den.abs < 1.0e-14
        qpx = c[0] - a[0]
        qpy = c[1] - a[1]
        t = (qpx * sy - qpy * sx) / den
        u = (qpx * ry - qpy * rx) / den
        return nil if t < -EPS || t > 1 + EPS || u < -EPS || u > 1 + EPS
        t
      end

      def lerp(a, b, t)
        [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
      end

      # Offset convex CCW polygon inward. dists: Float or per-edge Array
      # (edge i = poly[i] -> poly[i+1]). Returns nil if it collapses.
      def offset_convex(poly, dists)
        n = poly.length
        ds = dists.is_a?(Array) ? dists : Array.new(n, dists)
        lines = []
        n.times do |i|
          p = poly[i]
          q = poly[(i + 1) % n]
          dx = q[0] - p[0]
          dy = q[1] - p[1]
          len = Math.hypot(dx, dy)
          return nil if len < EPS
          nx = -dy / len
          ny = dx / len
          d = ds[i]
          lines << [[p[0] + nx * d, p[1] + ny * d], [dx / len, dy / len]]
        end
        out = []
        n.times do |i|
          l1 = lines[(i - 1) % n]
          l2 = lines[i]
          pt = line_intersection(l1[0], l1[1], l2[0], l2[1])
          pt ||= l2[0]
          out << pt
        end
        a0 = signed_area(poly)
        a1 = signed_area(out)
        return nil if a1 <= EPS || a1 > a0 + EPS
        # all edges must keep direction
        n.times do |i|
          p = out[i]
          q = out[(i + 1) % n]
          op = poly[i]
          oq = poly[(i + 1) % n]
          return nil if (q[0] - p[0]) * (oq[0] - op[0]) + (q[1] - p[1]) * (oq[1] - op[1]) <= 0
        end
        out
      end

      def line_intersection(p, d, q, e)
        den = d[0] * e[1] - d[1] * e[0]
        return nil if den.abs < 1.0e-12
        t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / den
        [p[0] + d[0] * t, p[1] + d[1] * t]
      end

      # Sutherland-Hodgman clip by half-plane: keep points where
      # (pt - o) . n <= c
      def clip_half_plane(poly, nx, ny, c)
        out = []
        n = poly.length
        return out if n == 0
        n.times do |i|
          cur = poly[i]
          prv = poly[(i - 1) % n]
          dc = cur[0] * nx + cur[1] * ny - c
          dp = prv[0] * nx + prv[1] * ny - c
          if dc <= 0
            if dp > 0
              t = dp / (dp - dc)
              out << lerp(prv, cur, t)
            end
            out << cur
          elsif dp <= 0
            t = dp / (dp - dc)
            out << lerp(prv, cur, t)
          end
        end
        out
      end

      def dist_point_line(pt, a, b)
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        len = Math.hypot(dx, dy)
        return Math.hypot(pt[0] - a[0], pt[1] - a[1]) if len < EPS
        ((pt[0] - a[0]) * dy - (pt[1] - a[1]) * dx).abs / len
      end

      # Uniform grid index over segments for fast queries.
      class SegmentIndex
        attr_reader :segments

        def initialize(segments, cell)
          @segments = segments
          @cell = cell > 0 ? cell : 1.0
          @grid = {}
          segments.each_with_index do |s, idx|
            bb = Geom2D.bbox(s)
            each_cell(bb) { |k| (@grid[k] ||= []) << idx }
          end
        end

        def each_cell(bb)
          i0 = (bb[0] / @cell).floor
          i1 = (bb[2] / @cell).floor
          j0 = (bb[1] / @cell).floor
          j1 = (bb[3] / @cell).floor
          # guard against huge loops
          if (i1 - i0 + 1) * (j1 - j0 + 1) > 40_000
            yield :all
            return
          end
          (i0..i1).each { |i| (j0..j1).each { |j| yield [i, j] } }
        end

        def query(bb)
          found = {}
          each_cell(bb) do |k|
            if k == :all
              @segments.each_index { |i| found[i] = true }
            else
              list = @grid[k]
              list.each { |i| found[i] = true } if list
            end
          end
          all = @grid[:all]
          all.each { |i| found[i] = true } if all
          found.keys.map { |i| @segments[i] }
        end
      end

      def region_segments(region)
        segs = []
        ([region[:outer]] + region[:holes]).each do |loop|
          n = loop.length
          n.times { |i| segs << [loop[i], loop[(i + 1) % n]] }
        end
        segs
      end

      # Classify convex CCW tile vs region: :inside, :outside, :boundary
      def classify(tile_poly, region, index)
        bb = bbox(tile_poly)
        index.query(bb).each do |s|
          next unless bbox_overlap?(bbox(s), bb)
          r = clip_segment_convex(s[0], s[1], tile_poly)
          next unless r
          len = Math.hypot(s[1][0] - s[0][0], s[1][1] - s[0][1]) * (r[1] - r[0])
          next if len < 1.0e-5
          mid = lerp(s[0], s[1], (r[0] + r[1]) * 0.5)
          return :boundary if point_in_convex?(mid, tile_poly, 1.0e-6)
        end
        point_in_region?(centroid(tile_poly), region) ? :inside : :outside
      end

      # Clip segment a-b to region; returns list of [p, q] inside.
      def clip_segment_region(a, b, region, index)
        bb = bbox([a, b])
        ts = [0.0, 1.0]
        index.query(bb).each do |s|
          t = seg_intersect_param(a, b, s[0], s[1])
          ts << t if t && t > 0 && t < 1
        end
        ts.sort!
        out = []
        cur = nil
        (0...(ts.length - 1)).each do |i|
          t0 = ts[i]
          t1 = ts[i + 1]
          next if t1 - t0 < 1.0e-9
          mid = lerp(a, b, (t0 + t1) * 0.5)
          if point_in_region?(mid, region)
            if cur && (cur[1] - t0).abs < 1.0e-9
              cur[1] = t1
            else
              out << cur if cur
              cur = [t0, t1]
            end
          end
        end
        out << cur if cur
        out.map { |r| [lerp(a, b, r[0]), lerp(a, b, r[1])] }
      end
    end
  end
end
