# Curved / multi-face surfaces: groups selected faces into surfaces (faces
# joined by soft, smooth or hidden edges, or coplanar neighbours), unrolls
# them isometrically into one 2D region and maps 2D points back onto the
# 3D surface. Tiles stay flat; they are placed tangent to the surface.
module BanianStudio
  module FloorStudio
    class Facet
      attr_accessor :face, :xf, :inv, :outer, :holes, :bb, :normal, :outer3, :holes3, :bb3

      def initialize(xf, outer3, holes3, normal, face = nil)
        @face = face
        @xf = xf
        @inv = xf.inverse
        @outer3 = outer3
        @holes3 = holes3
        @normal = normal
        @outer = Geom2D.ccw(outer3.map { |p| q = p.transform(xf); [q.x.to_f, q.y.to_f] })
        @holes = holes3.map { |h| h.map { |p| q = p.transform(xf); [q.x.to_f, q.y.to_f] } }
        @bb = Geom2D.bbox(@outer)
        xs = outer3.map(&:x)
        ys = outer3.map(&:y)
        zs = outer3.map(&:z)
        @bb3 = [xs.min, ys.min, zs.min, xs.max, ys.max, zs.max]
      end

      def contains?(pt)
        Geom2D.point_in_poly?(pt, @outer) && @holes.none? { |h| Geom2D.point_in_poly?(pt, h) }
      end

      def plane_dist(p)
        o = @outer3[0]
        ((p.x - o.x) * @normal.x + (p.y - o.y) * @normal.y + (p.z - o.z) * @normal.z).abs
      end
    end

    class Surface
      TOL = 1.0e-3
      attr_reader :facets, :region, :planar, :world_origin, :root, :overlap

      def initialize(facets, region, planar, world_origin, root = nil, overlap = false)
        @facets = facets
        @region = region
        @planar = planar
        @world_origin = world_origin
        @root = root
        @overlap = overlap
        build_index
      end

      # ------------------------------------------------------------------
      # Selection -> list of components (arrays of faces)
      def self.soft?(e)
        e.soft? || e.smooth? || e.hidden?
      end

      def self.vscale(v, s)
        Geom::Vector3d.new(v.x * s, v.y * s, v.z * s)
      end

      def self.coplanar?(f, g)
        n = f.normal
        m = g.normal
        return false if n.cross(m).length > 1.0e-6
        o = f.vertices.first.position
        g.vertices.all? do |v|
          p = v.position
          ((p.x - o.x) * n.x + (p.y - o.y) * n.y + (p.z - o.z) * n.z).abs < TOL
        end
      end

      def self.components(faces)
        sel = {}
        faces.each { |f| sel[f] = true }
        seen = {}
        comps = []
        faces.each do |f|
          next if seen[f]
          comp = []
          q = [f]
          seen[f] = true
          until q.empty?
            cur = q.shift
            comp << cur
            cur.edges.each do |e|
              e.faces.each do |g|
                next if g == cur || seen[g]
                next unless soft?(e) || (sel[g] && coplanar?(cur, g))
                seen[g] = true
                q << g
              end
            end
          end
          comps << comp
        end
        comps
      end

      # ------------------------------------------------------------------
      # Unroll a component of faces.
      def self.from_faces(faces, p)
        inset = {}
        faces.each { |f| inset[f] = true }
        root = faces.max_by(&:area)
        n0 = root.normal
        ori = n0.z < -0.985 ? -1 : 1
        ori = -ori if p[:flip]
        z = vscale(n0, ori)
        x = z.z.abs > 0.985 ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(0, 0, 1).cross(z)
        x.normalize!
        y = z.cross(x)
        y.normalize!
        x = y.cross(z)
        x.normalize!
        org = root.vertices.first.position
        xf = { root => Geom::Transformation.axes(org, x, y, z).inverse }
        oh = { root => ori }
        q = [root]
        until q.empty?
          f = q.shift
          nf = vscale(f.normal, oh[f])
          f.edges.each do |e|
            e.faces.each do |g|
              next if g == f || xf[g] || !inset[g]
              next unless soft?(e) || coplanar?(f, g)
              og = e.reversed_in?(f) == e.reversed_in?(g) ? -oh[f] : oh[f]
              ng = vscale(g.normal, og)
              a = e.start.position
              d = e.end.position - a
              d.normalize!
              ang = Math.atan2(ng.cross(nf).dot(d), ng.dot(nf))
              r = ang.abs < 1.0e-12 ? Geom::Transformation.new : Geom::Transformation.rotation(a, d, ang)
              xf[g] = xf[f] * r
              oh[g] = og
              q << g
            end
          end
        end
        faces = faces.select { |f| xf[f] }

        # shift to positive quadrant
        minx = miny = Float::INFINITY
        faces.each do |f|
          f.vertices.each do |v|
            w = v.position.transform(xf[f])
            minx = w.x if w.x < minx
            miny = w.y if w.y < miny
          end
        end
        sh = Geom::Transformation.new(Geom::Point3d.new(-minx, -miny, 0))
        faces.each { |f| xf[f] = sh * xf[f] }

        facets = faces.map do |f|
          outer3 = nil
          holes3 = []
          f.loops.each do |lp|
            pts = lp.vertices.map(&:position)
            if lp.outer?
              outer3 = pts
            else
              holes3 << pts
            end
          end
          Facet.new(xf[f], outer3, holes3, vscale(f.normal, oh[f]), f)
        end

        rz = vscale(n0, ori)
        o3 = root.vertices.first.position
        planar = faces.all? do |f|
          m = vscale(f.normal, oh[f])
          m.dot(rz) > 1 - 1.0e-9 && f.vertices.all? do |v|
            pp = v.position
            ((pp.x - o3.x) * rz.x + (pp.y - o3.y) * rz.y + (pp.z - o3.z) * rz.z).abs < TOL
          end
        end

        region = border_region(faces, inset, xf, oh)
        wo = Geom::Point3d.new(0, 0, 0).transform(xf[root])
        total = 0.0
        facets.each { |fc| total += Geom2D.area(fc.outer) - fc.holes.inject(0.0) { |s, h| s + Geom2D.area(h) } }
        rarea = Geom2D.area(region[:outer]) - region[:holes].inject(0.0) { |s, h| s + Geom2D.area(h) }
        overlap = rarea < total * 0.97
        new(facets, region, planar, [wo.x.to_f, wo.y.to_f], root, overlap)
      end

      def self.key(pt)
        [(pt[0] * 1000).round, (pt[1] * 1000).round]
      end

      def self.border_region(faces, inset, xf, oh)
        pos = lambda do |f, v|
          w = v.position.transform(xf[f])
          [w.x.to_f, w.y.to_f]
        end
        same = lambda { |a, b| (a[0] - b[0]).abs < TOL && (a[1] - b[1]).abs < TOL }
        segs = []
        faces.each do |f|
          f.loops.each do |lp|
            vs = lp.vertices
            n = vs.length
            n.times do |i|
              va = vs[i]
              vb = vs[(i + 1) % n]
              e = va.common_edge(vb)
              others = e ? e.faces.select { |g| g != f && inset[g] && xf[g] } : []
              internal = others.any? do |g|
                same.call(pos.call(f, va), pos.call(g, va)) && same.call(pos.call(f, vb), pos.call(g, vb))
              end
              next if internal
              pa = pos.call(f, va)
              pb = pos.call(f, vb)
              segs << (oh[f] > 0 ? [pa, pb] : [pb, pa])
            end
          end
        end
        loops = chain(segs)
        outers = loops.select { |l| Geom2D.signed_area(l) > 0 }.sort_by { |l| -Geom2D.area(l) }
        raise 'Could not unroll the selected surface' if outers.empty?
        holes = loops.select { |l| Geom2D.signed_area(l) < 0 }.map { |l| l.reverse }
        { :outer => outers.first, :holes => holes }
      end

      # Chain directed segments head-to-tail into closed loops.
      def self.chain(segs)
        starts = {}
        segs.each_with_index { |s, i| (starts[key(s[0])] ||= []) << i }
        used = {}
        loops = []
        find = lambda do |pt|
          k = key(pt)
          (-1..1).each do |dx|
            (-1..1).each do |dy|
              list = starts[[k[0] + dx, k[1] + dy]]
              next unless list
              list.each { |i| return i unless used[i] }
            end
          end
          nil
        end
        segs.each_index do |i|
          next if used[i]
          used[i] = true
          lp = [segs[i][0]]
          cur = segs[i][1]
          guard = 0
          while guard < segs.length + 2
            guard += 1
            break if (cur[0] - lp[0][0]).abs < TOL && (cur[1] - lp[0][1]).abs < TOL
            lp << cur
            j = find.call(cur)
            break unless j
            used[j] = true
            cur = segs[j][1]
          end
          loops << simplify(lp) if lp.length >= 3
        end
        loops.reject { |l| l.length < 3 }
      end

      # drop duplicate and collinear points
      def self.simplify(lp)
        out = []
        lp.each { |p| out << p if out.empty? || (out.last[0] - p[0]).abs > 1.0e-6 || (out.last[1] - p[1]).abs > 1.0e-6 }
        out.pop if out.length > 1 && (out.last[0] - out[0][0]).abs < 1.0e-6 && (out.last[1] - out[0][1]).abs < 1.0e-6
        res = []
        n = out.length
        n.times do |i|
          a = out[(i - 1) % n]
          b = out[i]
          c = out[(i + 1) % n]
          cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
          res << b unless cr.abs < 1.0e-9 && (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1]) > 0
        end
        res
      end

      # ------------------------------------------------------------------
      def build_index
        sz = 0.0
        @facets.each { |f| sz += (f.bb[2] - f.bb[0]) + (f.bb[3] - f.bb[1]) }
        @cell = [sz / [@facets.length * 2, 1].max, 1.0].max
        @grid = {}
        @facets.each do |f|
          ((f.bb[0] / @cell).floor..(f.bb[2] / @cell).floor).each do |i|
            ((f.bb[1] / @cell).floor..(f.bb[3] / @cell).floor).each do |j|
              (@grid[[i, j]] ||= []) << f
            end
          end
        end
      end

      def facet_at(pt)
        list = @grid[[(pt[0] / @cell).floor, (pt[1] / @cell).floor]]
        if list
          list.each { |f| return f if f.contains?(pt) }
        end
        best = nil
        bd = Float::INFINITY
        @facets.each do |f|
          d = dist_to_poly(pt, f.outer)
          if d < bd
            bd = d
            best = f
          end
        end
        best
      end

      def dist_to_poly(pt, poly)
        best = Float::INFINITY
        n = poly.length
        n.times do |i|
          a = poly[i]
          b = poly[(i + 1) % n]
          dx = b[0] - a[0]
          dy = b[1] - a[1]
          l2 = dx * dx + dy * dy
          t = l2 > 0 ? ((pt[0] - a[0]) * dx + (pt[1] - a[1]) * dy) / l2 : 0
          t = 0 if t < 0
          t = 1 if t > 1
          d = Math.hypot(pt[0] - a[0] - dx * t, pt[1] - a[1] - dy * t)
          best = d if d < best
        end
        best
      end

      def to3d(pt, facet = nil)
        f = facet || facet_at(pt)
        Geom::Point3d.new(pt[0], pt[1], 0).transform(f.inv)
      end

      def to2d(p3)
        cand = @facets.select do |f|
          b = f.bb3
          p3.x > b[0] - 0.5 && p3.x < b[3] + 0.5 && p3.y > b[1] - 0.5 && p3.y < b[4] + 0.5 &&
            p3.z > b[2] - 0.5 && p3.z < b[5] + 0.5
        end
        cand = @facets if cand.empty?
        f = cand.min_by { |c| c.plane_dist(p3) }
        q = p3.transform(f.xf)
        [q.x.to_f, q.y.to_f]
      end

      def facet_for_3d(p3)
        @facets.each do |f|
          b = f.bb3
          next unless p3.x > b[0] - TOL && p3.x < b[3] + TOL && p3.y > b[1] - TOL && p3.y < b[4] + TOL &&
                      p3.z > b[2] - TOL && p3.z < b[5] + TOL
          next if f.plane_dist(p3) > TOL
          q = p3.transform(f.xf)
          return f if f.contains?([q.x.to_f, q.y.to_f])
        end
        nil
      end

      # Flat tile frame on the curved surface (tile-local -> context coords).
      def tile_frame(t)
        c = [t.cx, t.cy]
        f0 = facet_at(c)
        p0 = to3d(c, f0)
        corners = t.poly.map { |q| to3d(q) }
        n = newell(corners)
        if n.nil?
          n = f0.normal.clone
        else
          n.reverse! if n.dot(f0.normal) < 0
        end
        samples = corners.dup
        m = t.poly.length
        m.times do |i|
          a = t.poly[i]
          b = t.poly[(i + 1) % m]
          samples << to3d([(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5])
        end
        d = 0.0
        samples.each do |s|
          v = (s.x - p0.x) * n.x + (s.y - p0.y) * n.y + (s.z - p0.z) * n.z
          d = v if v > d
        end
        origin = Geom::Point3d.new(p0.x + n.x * d, p0.y + n.y * d, p0.z + n.z * d)
        hl = 0.0
        t.shape.each { |q| hl = q[0].abs if q[0].abs > hl }
        hl = 1.0 if hl < 1.0e-6
        ca = Math.cos(t.ang)
        sa = Math.sin(t.ang)
        pa = to3d([c[0] - ca * hl, c[1] - sa * hl])
        pb = to3d([c[0] + ca * hl, c[1] + sa * hl])
        xv = pb - pa
        k = xv.dot(n)
        xv = Geom::Vector3d.new(xv.x - n.x * k, xv.y - n.y * k, xv.z - n.z * k)
        if xv.length < 1.0e-9
          q1 = to3d([c[0] + ca, c[1] + sa], f0)
          xv = q1 - p0
        end
        xv.normalize!
        yv = n.cross(xv)
        yv.normalize!
        Geom::Transformation.axes(origin, xv, yv, n)
      end

      def newell(pts)
        nx = ny = nz = 0.0
        k = pts.length
        k.times do |i|
          p = pts[i]
          q = pts[(i + 1) % k]
          nx += (p.y - q.y) * (p.z + q.z)
          ny += (p.z - q.z) * (p.x + q.x)
          nz += (p.x - q.x) * (p.y + q.y)
        end
        v = Geom::Vector3d.new(nx, ny, nz)
        return nil if v.length < 1.0e-9
        v.normalize!
        v
      end

      # Grout layer following the surface, offset by z along vertex normals.
      def grout(ents, z, mat)
        vn = {}
        kf = lambda { |p| [(p.x * 1.0e5).round, (p.y * 1.0e5).round, (p.z * 1.0e5).round] }
        @facets.each do |f|
          f.outer3.each do |p|
            k = kf.call(p)
            s = vn[k] ||= [0.0, 0.0, 0.0]
            s[0] += f.normal.x
            s[1] += f.normal.y
            s[2] += f.normal.z
          end
        end
        off = lambda do |p, f|
          s = vn[kf.call(p)]
          v = s ? Geom::Vector3d.new(s[0], s[1], s[2]) : f.normal.clone
          v = f.normal.clone if v.length < 1.0e-9
          v.normalize!
          Geom::Point3d.new(p.x + v.x * z, p.y + v.y * z, p.z + v.z * z)
        end
        mesh = Geom::PolygonMesh.new
        planar_list = []
        @facets.each do |f|
          if f.holes3.empty? && Geom2D.convex?(f.outer)
            pts = f.outer3
            pts = pts.reverse if Geom2D.signed_area(pts.map { |p| q = p.transform(f.xf); [q.x, q.y] }) < 0
            op = pts.map { |p| off.call(p, f) }
            (1...(op.length - 1)).each do |i|
              mesh.add_polygon(mesh.add_point(op[0]), mesh.add_point(op[i]), mesh.add_point(op[i + 1]))
            end
          else
            planar_list << f
          end
        end
        ents.add_faces_from_mesh(mesh, 0, mat, mat)
        planar_list.each do |f|
          mv = lambda { |p| Geom::Point3d.new(p.x + f.normal.x * z, p.y + f.normal.y * z, p.z + f.normal.z * z) }
          face = ents.add_face(f.outer3.map(&mv))
          next unless face
          f.holes3.each do |h|
            hf = ents.add_face(h.map(&mv))
            hf.erase! if hf && hf.valid? && hf != face
          end
          face.material = mat
          face.back_material = mat
        end
      end

      # ------------------------------------------------------------------
      def to_h
        {
          'planar' => @planar, 'world_origin' => @world_origin,
          'facets' => @facets.map do |f|
            { 'xf' => f.xf.to_a, 'n' => f.normal.to_a,
              'o' => f.outer3.map(&:to_a), 'h' => f.holes3.map { |h| h.map(&:to_a) } }
          end
        }
      end

      def self.from_h(h, region)
        facets = h['facets'].map do |d|
          pt = lambda { |a| Geom::Point3d.new(a[0].to_f, a[1].to_f, a[2].to_f) }
          Facet.new(Geom::Transformation.new(d['xf'].map(&:to_f)), d['o'].map(&pt),
                    d['h'].map { |l| l.map(&pt) }, Geom::Vector3d.new(*d['n'].map(&:to_f)))
        end
        new(facets, region, h['planar'], h['world_origin'])
      end
    end
  end
end
