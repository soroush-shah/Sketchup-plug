# encoding: UTF-8
# Banian Profile Builder - sweep engine (pure Ruby, inches).
#
# Instead of SketchUp's Follow Me (slow, many intermediate operations) we
# compute the swept solid ourselves: one mitred ring of points per path
# vertex, quads between rings and caps at the ends. The result is turned
# into a single PolygonMesh and inserted in one call.

module BanianStudio
  module ProfileBuilder
    module Sweep
      V = Vec
      Z = [0.0, 0.0, 1.0].freeze
      SMOOTH_COS = Math.cos(25.0 * Math::PI / 180.0)

      module_function

      # Newell normal of the polyline (treated as closed polygon).
      def newell(points)
        n = [0.0, 0.0, 0.0]
        m = points.size
        m.times do |i|
          a = points[i]; b = points[(i + 1) % m]
          n[0] += (a[1] - b[1]) * (a[2] + b[2])
          n[1] += (a[2] - b[2]) * (a[0] + b[0])
          n[2] += (a[0] - b[0]) * (a[1] + b[1])
        end
        n
      end

      def planar_normal(points)
        return nil if points.size < 3
        n = V.norm(newell(points))
        return nil unless n
        p0 = points[0]
        span = 0.0
        points.each { |p| span = [span, V.dist(p, p0)].max }
        tol = [1e-3, span * 1e-5].max
        points.each { |p| return nil if V.dot(V.sub(p, p0), n).abs > tol }
        n
      end

      # Prepares a path: cleaning, plane detection, orientation.
      # Returns {points:, closed:, up:} where up is the plane normal used as
      # the profile "up" (nil => use world Z with no-roll frames).
      def prepare(points, closed, up_ref = nil)
        pts = PathOps.clean(points, closed)
        closed = false if pts.size < 3
        up = nil
        if up_ref
          up = V.norm(up_ref.map(&:to_f))
          up = V.mul(up, -1.0) if up && up[2] < -1e-6
        end
        up ||= orient_auto(planar_normal(pts))
        # A plane normal is only usable when the path really lies in it.
        if up && pts.size >= 2
          ok = PathOps.segments(pts, closed).all? do |a, b|
            t = V.norm(V.sub(b, a))
            t.nil? || V.dot(t, up).abs < 1e-3
          end
          up = nil unless ok
        end
        if closed && up
          nw = newell(pts)
          pts = pts.reverse if V.dot(nw, up) < 0
        end
        { points: pts, closed: closed, up: up }
      end

      def orient_auto(n)
        return nil unless n
        if n[2].abs > 1e-6
          n = V.mul(n, -1.0) if n[2] < 0
        elsif n[1].abs > 1e-6
          n = V.mul(n, -1.0) if n[1] > 0
        elsif n[0] > 0
          n = V.mul(n, -1.0)
        end
        n
      end

      # One frame [T, R, U] per segment. R = right of travel, U = up.
      def frames(points, closed, up)
        segs = PathOps.segments(points, closed)
        prev_r = nil
        segs.map do |a, b|
          t = V.norm(V.sub(b, a)) || [1.0, 0.0, 0.0]
          if up
            r = V.norm(V.cross(t, up)) || prev_r || [0.0, -1.0, 0.0]
          else
            r = V.dot(t, Z).abs < 0.999 ? V.norm(V.cross(t, Z)) : nil
            r ||= prev_r ? V.norm(V.sub(prev_r, V.mul(t, V.dot(prev_r, t)))) : nil
            r ||= V.norm(V.cross(t, [0.0, 1.0, 0.0])) || [1.0, 0.0, 0.0]
          end
          u = V.cross(r, t)
          prev_r = r
          [t, r, u]
        end
      end

      def turn_smooth(loop)
        n = loop.size
        (0...n).map do |j|
          a = loop[(j - 1) % n]; b = loop[j]; c = loop[(j + 1) % n]
          d1 = [b[0] - a[0], b[1] - a[1]]; d2 = [c[0] - b[0], c[1] - b[1]]
          l1 = Math.hypot(*d1); l2 = Math.hypot(*d2)
          if l1 < 1e-12 || l2 < 1e-12
            false
          else
            (d1[0] * d2[0] + d1[1] * d2[1]) / (l1 * l2) > SMOOTH_COS
          end
        end
      end

      # rings[k][l][j] = 3D point of loop l, vertex j at path vertex k.
      def rings(points, closed, loops, frs)
        n = points.size
        out = []
        n.times do |k|
          p = points[k]
          a_idx = closed ? (k - 1) % n : k - 1
          b_idx = k
          b_idx = nil if !closed && k == n - 1
          a_idx = nil if !closed && k == 0
          fa = a_idx ? frs[a_idx] : nil
          fb = b_idx ? frs[b_idx] : nil
          f = fa || fb
          miter = nil
          if fa && fb
            m = V.norm(V.add(fa[0], fb[0]))
            miter = m if m && V.dot(fa[0], fb[0]) > -0.999
          end
          out << loops.map do |l|
            l.map do |q|
              pt = V.frame_point(p, f[1], q[0], f[2], q[1])
              if miter
                off = V.sub(pt, p)
                d = V.dot(f[0], miter)
                pt = V.sub(pt, V.mul(f[0], V.dot(off, miter) / d)) if d.abs > 1e-9
              end
              pt
            end
          end
        end
        out
      end

      def joint_smooth(points, closed, frs)
        n = points.size
        (0...n).map do |k|
          if !closed && (k == 0 || k == n - 1)
            false
          else
            fa = frs[(k - 1) % frs.size]; fb = frs[k % frs.size]
            V.dot(fa[0], fb[0]) > SMOOTH_COS
          end
        end
      end

      # Mesh data for a swept solid.
      # Returns {vertices:, polygons:, caps:} (caps => [[loops], normal]).
      def mesh(prep, loops)
        pts = prep[:points]; closed = prep[:closed]
        return nil if pts.size < 2 || loops.empty?
        frs = frames(pts, closed, prep[:up])
        rg = rings(pts, closed, loops, frs)
        psm = loops.map { |l| turn_smooth(l) }
        jsm = joint_smooth(pts, closed, frs)
        build_mesh(rg, closed, psm, jsm, closed ? nil : [V.mul(frs[0][0], -1.0), frs[-1][0]])
      end

      # Straight prism along +Z (used for repeated components).
      def prism(loops, length)
        r0 = loops.map { |l| l.map { |q| [q[0], q[1], 0.0] } }
        r1 = loops.map { |l| l.map { |q| [q[0], q[1], length] } }
        psm = loops.map { |l| turn_smooth(l) }
        # Profile u -> +X, v -> +Y, extrusion -> +Z. Our quad winding assumes
        # (R, U, T) is left-handed, so mirror the winding by reversing loops.
        build_mesh([r0, r1], false, psm, [false, false], [[0.0, 0.0, -1.0], [0.0, 0.0, 1.0]], true)
      end

      def build_mesh(rg, closed, psm, jsm, cap_normals, mirrored = false)
        nk = rg.size
        vertices = []
        base = []
        rg.each do |ring|
          b = []
          ring.each do |l|
            b << vertices.size
            vertices.concat(l)
          end
          base << b
        end
        polygons = []
        segs = closed ? nk : nk - 1
        segs.times do |k|
          k2 = (k + 1) % nk
          rg[k].each_with_index do |l, li|
            m = l.size
            m.times do |j|
              j1 = (j + 1) % m
              a = base[k][li] + j + 1
              b = base[k][li] + j1 + 1
              c = base[k2][li] + j1 + 1
              d = base[k2][li] + j + 1
              poly = if mirrored
                       [[a, jsm[k]], [b, psm[li][j1]], [c, jsm[k2]], [d, psm[li][j]]]
                     else
                       [[a, psm[li][j]], [d, jsm[k2]], [c, psm[li][j1]], [b, jsm[k]]]
                     end
              polygons << poly.map { |idx, soft| soft ? -idx : idx }
            end
          end
        end
        caps = []
        if !closed && cap_normals
          caps << [rg[0], cap_normals[0]]
          caps << [rg[-1], cap_normals[1]]
        end
        { vertices: vertices, polygons: polygons, caps: caps }
      end

      # Lines for a fast wireframe preview (pairs of points).
      def preview_lines(prep, loops, max_rings = 400)
        pts = prep[:points]; closed = prep[:closed]
        return [] if pts.size < 2 || loops.empty?
        frs = frames(pts, closed, prep[:up])
        rg = rings(pts, closed, loops, frs)
        psm = loops.map { |l| turn_smooth(l) }
        jsm = joint_smooth(pts, closed, frs)
        lines = []
        step = rg.size > max_rings ? (rg.size / max_rings.to_f).ceil : 1
        rg.each_with_index do |ring, k|
          next unless k % step == 0 || k == rg.size - 1
          next if jsm[k] && k % 4 != 0
          ring.each do |l|
            l.each_with_index { |q, j| lines << q << l[(j + 1) % l.size] }
          end
        end
        segs = closed ? rg.size : rg.size - 1
        segs.times do |k|
          k2 = (k + 1) % rg.size
          rg[k].each_with_index do |l, li|
            l.each_index do |j|
              next if psm[li][j] && j % 4 != 0
              lines << l[j] << rg[k2][li][j]
            end
          end
        end
        lines
      end
    end
  end
end
