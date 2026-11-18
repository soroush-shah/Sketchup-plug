# frozen_string_literal: true

# Pure-Ruby vector math used by MEP Studio.
# Works on plain [x, y, z] Float arrays (inches, SketchUp internal unit) so it
# can be unit-tested without SketchUp and runs fast inside clash detection.
module MEPStudio
  module Geo
    EPS = 1.0e-9

    module_function

    def v(a)
      [a[0].to_f, a[1].to_f, a[2].to_f]
    end

    def add(a, b)
      [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
    end

    def sub(a, b)
      [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
    end

    def mul(a, s)
      [a[0] * s, a[1] * s, a[2] * s]
    end

    def dot(a, b)
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    end

    def cross(a, b)
      [a[1] * b[2] - a[2] * b[1],
       a[2] * b[0] - a[0] * b[2],
       a[0] * b[1] - a[1] * b[0]]
    end

    def len(a)
      Math.sqrt(dot(a, a))
    end

    def dist(a, b)
      len(sub(a, b))
    end

    def norm(a)
      l = len(a)
      return [0.0, 0.0, 0.0] if l < EPS
      [a[0] / l, a[1] / l, a[2] / l]
    end

    def lerp(a, b, t)
      add(a, mul(sub(b, a), t))
    end

    def mid(a, b)
      lerp(a, b, 0.5)
    end

    # Remove consecutive duplicates and collinear interior points.
    def clean_path(points, tol = 1.0e-3)
      pts = []
      points.each do |p|
        p = v(p)
        pts << p if pts.empty? || dist(pts.last, p) > tol
      end
      return pts if pts.size < 3
      out = [pts.first]
      (1...pts.size - 1).each do |i|
        d1 = norm(sub(pts[i], out.last))
        d2 = norm(sub(pts[i + 1], pts[i]))
        out << pts[i] if len(cross(d1, d2)) > 1.0e-6 || dot(d1, d2) < 0
      end
      out << pts.last
      out
    end

    # Replace every interior corner of a polyline by a circular arc of
    # radius r (centerline radius). Radius is clamped so arcs never overlap.
    def fillet_path(points, radius, segs_per_90 = 6)
      pts = clean_path(points)
      return pts if pts.size < 3 || radius <= EPS
      out = [pts.first]
      (1...pts.size - 1).each do |i|
        a = out.last
        b = pts[i]
        c = pts[i + 1]
        d1 = norm(sub(a, b))
        d2 = norm(sub(c, b))
        cosang = [[dot(d1, d2), -1.0].max, 1.0].min
        ang = Math.acos(cosang) # interior angle at corner
        if ang < 1.0e-4 || (Math::PI - ang) < 1.0e-4
          out << b
          next
        end
        tan_len = radius / Math.tan(ang / 2.0)
        max_a = dist(a, b) * (i == 1 ? 0.95 : 0.48)
        max_c = dist(c, b) * (i == pts.size - 2 ? 0.95 : 0.48)
        r = radius
        if tan_len > max_a || tan_len > max_c
          tan_len = [max_a, max_c].min
          r = tan_len * Math.tan(ang / 2.0)
        end
        t1 = add(b, mul(d1, tan_len))
        t2 = add(b, mul(d2, tan_len))
        bis = norm(add(d1, d2))
        center = add(b, mul(bis, r / Math.sin(ang / 2.0)))
        sweep = Math::PI - ang
        n = [(sweep / (Math::PI / 2.0) * segs_per_90).ceil, 2].max
        v1 = sub(t1, center)
        v2 = sub(t2, center)
        out << t1
        (1...n).each do |k|
          t = k.to_f / n
          out << add(center, slerp(v1, v2, t))
        end
        out << t2
      end
      out << pts.last
      clean_path(out, 2.0e-3) # > SketchUp 0.001" tolerance
    end

    def slerp(v1, v2, t)
      l1 = len(v1)
      a = norm(v1)
      b = norm(v2)
      om = Math.acos([[dot(a, b), -1.0].max, 1.0].min)
      return lerp(v1, v2, t) if om < EPS
      s = Math.sin(om)
      r = add(mul(a, Math.sin((1 - t) * om) / s), mul(b, Math.sin(t * om) / s))
      mul(r, l1)
    end

    def path_length(points)
      sum = 0.0
      (0...points.size - 1).each { |i| sum += dist(points[i], points[i + 1]) }
      sum
    end

    # Local frame for a duct/pipe segment direction d.
    # Returns [width_axis, height_axis] where height axis is as close to +Z
    # as possible (for vertical segments the width axis falls back to X).
    def section_axes(d, ref_width = nil)
      d = norm(d)
      z = [0.0, 0.0, 1.0]
      w = cross(d, z)
      if len(w) < 1.0e-6
        w = ref_width ? norm(sub(ref_width, mul(d, dot(ref_width, d)))) : [1.0, 0.0, 0.0]
        w = [1.0, 0.0, 0.0] if len(w) < 1.0e-6
      end
      w = norm(w)
      h = norm(cross(w, d))
      [w, h]
    end

    # ------------------------------------------------------------------
    # Oriented bounding boxes: {c: center, ax: [u,v,w] unit axes, e: [hx,hy,hz]}
    # ------------------------------------------------------------------
    def obb(center, axes, half)
      { c: v(center), ax: axes.map { |a| norm(v(a)) }, e: half.map(&:to_f) }
    end

    def obb_inflate(b, d)
      { c: b[:c], ax: b[:ax], e: b[:e].map { |x| [x + d, 0.0].max } }
    end

    def segment_obb(p0, p1, width, height, ref_width = nil)
      d = sub(p1, p0)
      l = len(d)
      w, h = section_axes(d, ref_width)
      obb(mid(p0, p1), [norm(d), w, h], [l / 2.0, width / 2.0, height / 2.0])
    end

    def obb_corners(b)
      res = []
      [-1, 1].each do |i|
        [-1, 1].each do |j|
          [-1, 1].each do |k|
            p = b[:c]
            p = add(p, mul(b[:ax][0], i * b[:e][0]))
            p = add(p, mul(b[:ax][1], j * b[:e][1]))
            p = add(p, mul(b[:ax][2], k * b[:e][2]))
            res << p
          end
        end
      end
      res
    end

    def obb_aabb(b)
      ext = (0..2).map do |i|
        b[:e][0] * b[:ax][0][i].abs + b[:e][1] * b[:ax][1][i].abs + b[:e][2] * b[:ax][2][i].abs
      end
      [sub(b[:c], ext), add(b[:c], ext)]
    end

    def aabb_overlap?(a, b)
      (0..2).all? { |i| a[0][i] <= b[1][i] && b[0][i] <= a[1][i] }
    end

    def aabb_union(a, b)
      [(0..2).map { |i| [a[0][i], b[0][i]].min }, (0..2).map { |i| [a[1][i], b[1][i]].max }]
    end

    def aabb_intersection_center(a, b)
      lo = (0..2).map { |i| [a[0][i], b[0][i]].max }
      hi = (0..2).map { |i| [a[1][i], b[1][i]].min }
      mid(lo, hi)
    end

    # Separating axis test between two OBBs.
    def obb_overlap?(a, b)
      axes = a[:ax] + b[:ax]
      a[:ax].each do |u|
        b[:ax].each do |w|
          c = cross(u, w)
          axes << norm(c) if len(c) > 1.0e-6
        end
      end
      t = sub(b[:c], a[:c])
      axes.each do |l|
        ra = (0..2).sum { |i| a[:e][i] * dot(a[:ax][i], l).abs }
        rb = (0..2).sum { |i| b[:e][i] * dot(b[:ax][i], l).abs }
        return false if dot(t, l).abs > ra + rb + EPS
      end
      true
    end

    # Separating axis test between a triangle and an OBB.
    def tri_obb_overlap?(tri, b)
      c = b[:c]
      # Express triangle in box frame.
      q = tri.map do |p|
        d = sub(p, c)
        [dot(d, b[:ax][0]), dot(d, b[:ax][1]), dot(d, b[:ax][2])]
      end
      e = b[:e]
      # Box face normals.
      3.times do |i|
        mn, mx = [q[0][i], q[1][i], q[2][i]].minmax
        return false if mn > e[i] + EPS || mx < -e[i] - EPS
      end
      f = [sub(q[1], q[0]), sub(q[2], q[1]), sub(q[0], q[2])]
      n = cross(f[0], f[1])
      if len(n) > EPS
        r = e[0] * n[0].abs + e[1] * n[1].abs + e[2] * n[2].abs
        return false if dot(n, q[0]).abs > r + EPS
      end
      units = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
      units.each do |u|
        f.each do |fe|
          a = cross(u, fe)
          next if len(a) < EPS
          p = q.map { |pt| dot(pt, a) }
          r = e[0] * a[0].abs + e[1] * a[1].abs + e[2] * a[2].abs
          return false if p.min > r + EPS || p.max < -r - EPS
        end
      end
      true
    end

    # Minimum distance between segments p1-q1 and p2-q2.
    def seg_seg_dist(p1, q1, p2, q2)
      p1 = v(p1)
      q1 = v(q1)
      p2 = v(p2)
      q2 = v(q2)
      d1 = sub(q1, p1)
      d2 = sub(q2, p2)
      r = sub(p1, p2)
      a = dot(d1, d1)
      e = dot(d2, d2)
      f = dot(d2, r)
      s = t = 0.0
      if a <= EPS && e <= EPS
        return dist(p1, p2)
      elsif a <= EPS
        t = clamp(f / e, 0.0, 1.0)
      else
        c = dot(d1, r)
        if e <= EPS
          s = clamp(-c / a, 0.0, 1.0)
        else
          b = dot(d1, d2)
          denom = a * e - b * b
          s = denom.abs > EPS ? clamp((b * f - c * e) / denom, 0.0, 1.0) : 0.0
          t = (b * s + f) / e
          if t < 0.0
            t = 0.0
            s = clamp(-c / a, 0.0, 1.0)
          elsif t > 1.0
            t = 1.0
            s = clamp((b - c) / a, 0.0, 1.0)
          end
        end
      end
      c1 = add(p1, mul(d1, s))
      c2 = add(p2, mul(d2, t))
      [dist(c1, c2), mid(c1, c2)]
    end

    def point_seg_dist(p, a, b)
      ab = sub(b, a)
      l2 = dot(ab, ab)
      return dist(p, a) if l2 < EPS
      t = clamp(dot(sub(p, a), ab) / l2, 0.0, 1.0)
      dist(p, add(a, mul(ab, t)))
    end

    def point_in_obb?(p, b, tol = 0.0)
      d = sub(p, b[:c])
      (0..2).all? { |i| dot(d, b[:ax][i]).abs <= b[:e][i] + tol }
    end

    def clamp(x, lo, hi)
      x < lo ? lo : (x > hi ? hi : x)
    end

    # ------------------------------------------------------------------
    # Grid layout (sprinklers, lights, diffusers) inside a rectangle.
    # Returns [nx, ny, dx, dy] where dx = length / nx etc.
    # ------------------------------------------------------------------
    def grid_counts(length, width, max_spacing, max_area = nil)
      length = length.to_f
      width = width.to_f
      max_spacing = max_spacing.to_f
      nx = [(length / max_spacing).ceil, 1].max
      ny = [(width / max_spacing).ceil, 1].max
      if max_area && max_area > 0
        guard = 0
        while (length / nx) * (width / ny) > max_area + 1.0e-9 && guard < 1000
          if length / nx >= width / ny
            nx += 1
          else
            ny += 1
          end
          guard += 1
        end
      end
      [nx, ny, length / nx, width / ny]
    end
  end
end
