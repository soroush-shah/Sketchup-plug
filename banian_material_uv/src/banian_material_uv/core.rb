# encoding: UTF-8
#
# Banian Material UV - geometry / UV core.
#
# This file is pure Ruby (no SketchUp API). It works on a small abstract mesh
# so every algorithm can be unit tested outside SketchUp. Written for
# Ruby 2.0+ (SketchUp 2014) up to Ruby 3.x (SketchUp 2024-2027).
#
module BanianStudio
  module MaterialUV
    module Core

      EPS = 1.0e-9
      TWO_PI = Math::PI * 2.0

      # ------------------------------------------------------------------
      # Vector helpers (arrays [x, y, z])
      # ------------------------------------------------------------------
      module V
        module_function

        def sub(a, b) [a[0] - b[0], a[1] - b[1], a[2] - b[2]] end
        def add(a, b) [a[0] + b[0], a[1] + b[1], a[2] + b[2]] end
        def mul(a, s) [a[0] * s, a[1] * s, a[2] * s] end
        def dot(a, b) a[0] * b[0] + a[1] * b[1] + a[2] * b[2] end

        def cross(a, b)
          [a[1] * b[2] - a[2] * b[1],
           a[2] * b[0] - a[0] * b[2],
           a[0] * b[1] - a[1] * b[0]]
        end

        def len(a) Math.sqrt(dot(a, a)) end

        def norm(a)
          l = len(a)
          l < EPS ? [0.0, 0.0, 0.0] : [a[0] / l, a[1] / l, a[2] / l]
        end

        def dist(a, b) len(sub(a, b)) end
      end

      # ------------------------------------------------------------------
      # Small linear algebra
      # ------------------------------------------------------------------
      module LA
        module_function

        # Solve A x = b (A: n x n). Returns nil if singular.
        def solve(a, b)
          n = b.size
          m = Array.new(n) { |i| a[i].map { |x| x.to_f } + [b[i].to_f] }
          n.times do |col|
            piv = col
            (col + 1...n).each { |r| piv = r if m[r][col].abs > m[piv][col].abs }
            return nil if m[piv][col].abs < 1.0e-14
            m[col], m[piv] = m[piv], m[col]
            (col + 1...n).each do |r|
              f = m[r][col] / m[col][col]
              next if f == 0.0
              (col..n).each { |c| m[r][c] -= f * m[col][c] }
            end
          end
          x = Array.new(n, 0.0)
          (n - 1).downto(0) do |r|
            s = m[r][n]
            (r + 1...n).each { |c| s -= m[r][c] * x[c] }
            x[r] = s / m[r][r]
          end
          x
        end

        # Least squares: rows * x = rhs
        def least_squares(rows, rhs)
          k = rows[0].size
          ata = Array.new(k) { Array.new(k, 0.0) }
          atb = Array.new(k, 0.0)
          rows.each_with_index do |row, idx|
            k.times do |i|
              atb[i] += row[i] * rhs[idx]
              k.times { |j| ata[i][j] += row[i] * row[j] }
            end
          end
          solve(ata, atb)
        end

        # Jacobi eigen decomposition of a symmetric 3x3 matrix.
        # Returns [[value, vector], ...] sorted ascending by value.
        def eigen_sym3(mat)
          a = mat.map { |r| r.map { |x| x.to_f } }
          v = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
          60.times do
            p, q, mx = 0, 1, a[0][1].abs
            if a[0][2].abs > mx then p, q, mx = 0, 2, a[0][2].abs end
            if a[1][2].abs > mx then p, q, mx = 1, 2, a[1][2].abs end
            break if mx < 1.0e-13
            theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
            t = (theta >= 0 ? 1.0 : -1.0) / (theta.abs + Math.sqrt(theta * theta + 1.0))
            c = 1.0 / Math.sqrt(t * t + 1.0)
            s = t * c
            3.times do |k|
              akp = a[k][p]; akq = a[k][q]
              a[k][p] = c * akp - s * akq
              a[k][q] = s * akp + c * akq
            end
            3.times do |k|
              apk = a[p][k]; aqk = a[q][k]
              a[p][k] = c * apk - s * aqk
              a[q][k] = s * apk + c * aqk
            end
            3.times do |k|
              vkp = v[k][p]; vkq = v[k][q]
              v[k][p] = c * vkp - s * vkq
              v[k][q] = s * vkp + c * vkq
            end
          end
          res = (0..2).map { |i| [a[i][i], V.norm([v[0][i], v[1][i], v[2][i]])] }
          res.sort_by { |e| e[0] }
        end
      end

      # ------------------------------------------------------------------
      # Abstract mesh
      # ------------------------------------------------------------------
      class FaceRec
        attr_accessor :id, :verts, :normal, :area, :center, :ref
        def initialize(id, verts, normal, area, center, ref)
          @id = id; @verts = verts; @normal = normal
          @area = area; @center = center; @ref = ref
        end
      end

      class EdgeRec
        attr_accessor :key, :faces, :soft
        def initialize(key)
          @key = key; @faces = []; @soft = false
        end
      end

      class Mesh
        attr_reader :pos, :faces, :edges

        def initialize
          @pos = {}      # vid => [x,y,z] (world)
          @faces = []    # FaceRec
          @edges = {}    # [v1,v2] (sorted) => EdgeRec
        end

        def self.key(a, b) a < b ? [a, b] : [b, a] end

        def add_vertex(vid, pt)
          @pos[vid] = [pt[0].to_f, pt[1].to_f, pt[2].to_f]
        end

        # vids: outer loop order (counter clockwise around the front normal)
        # flip: true when the owning instance is mirrored
        def add_face(vids, ref = nil, flip = false)
          pts = vids.map { |v| @pos[v] }
          n = [0.0, 0.0, 0.0]
          c = [0.0, 0.0, 0.0]
          pts.each_with_index do |p, i|
            q = pts[(i + 1) % pts.size]
            n[0] += (p[1] - q[1]) * (p[2] + q[2])
            n[1] += (p[2] - q[2]) * (p[0] + q[0])
            n[2] += (p[0] - q[0]) * (p[1] + q[1])
            c = V.add(c, p)
          end
          area = V.len(n) * 0.5
          nn = V.norm(n)
          nn = V.mul(nn, -1.0) if flip
          c = V.mul(c, 1.0 / pts.size)
          f = FaceRec.new(@faces.size, vids, nn, area, c, ref)
          @faces << f
          vids.each_with_index do |v, i|
            w = vids[(i + 1) % vids.size]
            next if v == w
            k = Mesh.key(v, w)
            e = (@edges[k] ||= EdgeRec.new(k))
            e.faces << f.id unless e.faces.include?(f.id)
          end
          f
        end

        def set_soft(a, b, soft)
          e = @edges[Mesh.key(a, b)]
          e.soft = soft if e
        end

        def face_edge_keys(fi)
          vs = @faces[fi].verts
          keys = []
          vs.each_with_index do |v, i|
            w = vs[(i + 1) % vs.size]
            keys << [v, w] unless v == w
          end
          keys
        end

        # +1 if a->b is the loop direction of face fi, -1 if b->a, 0 otherwise
        def edge_dir(fi, a, b)
          vs = @faces[fi].verts
          n = vs.size
          n.times do |i|
            return 1 if vs[i] == a && vs[(i + 1) % n] == b
            return -1 if vs[i] == b && vs[(i + 1) % n] == a
          end
          0
        end

        # Connected groups (by shared edges) restricted to fset (hash fi=>true)
        def islands(fset)
          seen = {}
          out = []
          fset.keys.sort.each do |start|
            next if seen[start]
            group = []
            stack = [start]
            seen[start] = true
            until stack.empty?
              f = stack.pop
              group << f
              face_edge_keys(f).each do |a, b|
                e = @edges[Mesh.key(a, b)]
                next unless e
                e.faces.each do |g|
                  next if seen[g] || !fset[g]
                  seen[g] = true
                  stack << g
                end
              end
            end
            out << group
          end
          out
        end

        def verts_of(face_ids)
          h = {}
          face_ids.each { |fi| @faces[fi].verts.each { |v| h[v] = true } }
          h.keys
        end
      end

      # ------------------------------------------------------------------
      # Fitting / analysis
      # ------------------------------------------------------------------
      module_function

      def bbox_center(points)
        mn = points[0].dup; mx = points[0].dup
        points.each do |p|
          3.times { |i| mn[i] = p[i] if p[i] < mn[i]; mx[i] = p[i] if p[i] > mx[i] }
        end
        [(mn[0] + mx[0]) / 2.0, (mn[1] + mx[1]) / 2.0, (mn[2] + mx[2]) / 2.0]
      end

      def bbox_diag(points)
        mn = points[0].dup; mx = points[0].dup
        points.each do |p|
          3.times { |i| mn[i] = p[i] if p[i] < mn[i]; mx[i] = p[i] if p[i] > mx[i] }
        end
        V.dist(mn, mx)
      end

      # returns [center, radius, relative_error] or nil
      def fit_sphere(points)
        return nil if points.size < 4
        ref = bbox_center(points)
        rows = []; rhs = []
        points.each do |p|
          d = V.sub(p, ref)
          rows << [2.0 * d[0], 2.0 * d[1], 2.0 * d[2], 1.0]
          rhs << V.dot(d, d)
        end
        x = LA.least_squares(rows, rhs)
        return nil unless x
        c = [x[0], x[1], x[2]]
        r2 = x[3] + V.dot(c, c)
        return nil if r2 <= EPS
        r = Math.sqrt(r2)
        center = V.add(ref, c)
        err = rms(points.map { |p| V.dist(p, center) - r }) / r
        [center, r, err]
      end

      # Orthonormal frame [e1, e2] perpendicular to axis
      def perp_frame(axis)
        a = V.norm(axis)
        ref = a[2].abs < 0.9 ? [0.0, 0.0, 1.0] : [1.0, 0.0, 0.0]
        e1 = if a[2].abs < 0.9
               V.norm(V.cross(a, ref))
             else
               V.norm(V.sub(ref, V.mul(a, V.dot(ref, a))))
             end
        e2 = V.cross(a, e1)
        [e1, e2]
      end

      # Circle fit of points projected on plane perpendicular to axis.
      # returns [origin(3d, on axis), radius, relative_error] or nil
      def fit_cylinder(points, axis)
        return nil if points.size < 3
        e1, e2 = perp_frame(axis)
        ref = bbox_center(points)
        rows = []; rhs = []
        pts2 = points.map do |p|
          d = V.sub(p, ref)
          [V.dot(d, e1), V.dot(d, e2)]
        end
        pts2.each do |x, y|
          rows << [2.0 * x, 2.0 * y, 1.0]
          rhs << x * x + y * y
        end
        s = LA.least_squares(rows, rhs)
        return nil unless s
        r2 = s[2] + s[0] * s[0] + s[1] * s[1]
        return nil if r2 <= EPS
        r = Math.sqrt(r2)
        diag = bbox_diag(points)
        return nil if r > diag * 50.0
        err = rms(pts2.map { |x, y| Math.sqrt((x - s[0])**2 + (y - s[1])**2) - r }) / r
        origin = V.add(ref, V.add(V.mul(e1, s[0]), V.mul(e2, s[1])))
        [origin, r, err]
      end

      def rms(vals)
        return 0.0 if vals.empty?
        s = 0.0
        vals.each { |v| s += v * v }
        Math.sqrt(s / vals.size)
      end

      def normal_eigen(mesh, face_ids)
        m = [[0.0] * 3, [0.0] * 3, [0.0] * 3]
        face_ids.each do |fi|
          n = mesh.faces[fi].normal
          3.times { |i| 3.times { |j| m[i][j] += n[i] * n[j] } }
        end
        LA.eigen_sym3(m)
      end

      def has_soft_edge?(mesh, fi)
        mesh.face_edge_keys(fi).any? do |a, b|
          e = mesh.edges[Mesh.key(a, b)]
          e && e.soft && e.faces.size > 1
        end
      end

      def average_normal(mesh, face_ids)
        s = [0.0, 0.0, 0.0]
        face_ids.each { |fi| f = mesh.faces[fi]; s = V.add(s, V.mul(f.normal, f.area)) }
        n = V.norm(s)
        V.len(n) < 0.5 ? [0.0, 0.0, 1.0] : n
      end

      # Max absolute angle defect on interior vertices (0 for developable).
      def max_angle_defect(mesh, face_ids)
        fset = {}
        face_ids.each { |f| fset[f] = true }
        sum = Hash.new(0.0)
        face_ids.each do |fi|
          vs = mesh.faces[fi].verts
          n = vs.size
          vs.each_with_index do |v, i|
            a = V.norm(V.sub(mesh.pos[vs[(i - 1) % n]], mesh.pos[v]))
            b = V.norm(V.sub(mesh.pos[vs[(i + 1) % n]], mesh.pos[v]))
            d = V.dot(a, b)
            d = 1.0 if d > 1.0
            d = -1.0 if d < -1.0
            sum[v] += Math.acos(d)
          end
        end
        # interior vertices: every incident edge has 2 faces from the set
        boundary = {}
        mesh.edges.each_value do |e|
          cnt = 0
          e.faces.each { |f| cnt += 1 if fset[f] }
          next if cnt == 0
          if cnt < 2
            boundary[e.key[0]] = true
            boundary[e.key[1]] = true
          end
        end
        mx = 0.0
        interior = 0
        sum.each do |v, ang|
          next if boundary[v]
          interior += 1
          d = (TWO_PI - ang).abs
          mx = d if d > mx
        end
        [mx, interior]
      end

      # Analyse an island and suggest a mapping mode.
      # returns hash {:mode, :axis, :origin, :radius, :center, :normal, :reason}
      def analyze(mesh, face_ids)
        info = {}
        verts = mesh.verts_of(face_ids)
        pts = verts.map { |v| mesh.pos[v] }
        avg_n = average_normal(mesh, face_ids)
        info[:normal] = avg_n

        min_dot = 1.0
        face_ids.each { |fi| d = V.dot(mesh.faces[fi].normal, avg_n); min_dot = d if d < min_dot }
        if min_dot > 0.9995
          info[:mode] = 'planar'; info[:reason] = 'flat'
          return info
        end

        eig = normal_eigen(mesh, face_ids)
        total = eig[0][0] + eig[1][0] + eig[2][0]
        total = 1.0 if total < EPS

        if face_ids.size >= 12
          sph = fit_sphere(pts)
          if sph && sph[2] < 0.03 && eig[0][0] / total > 0.12
            info[:mode] = 'spherical'; info[:center] = sph[0]; info[:radius] = sph[1]
            info[:axis] = [0.0, 0.0, 1.0]; info[:reason] = 'sphere'
            return info
          end
        end

        if face_ids.size >= 4
          curved = face_ids.select { |fi| has_soft_edge?(mesh, fi) }
          curved = face_ids if curved.size < 4
          ceig = normal_eigen(mesh, curved)
          axis = orient_axis(ceig[0][1])
          ctotal = ceig[0][0] + ceig[1][0] + ceig[2][0]
          ctotal = 1.0 if ctotal < EPS
          if ceig[0][0] / ctotal < 0.02
            side = curved.select { |fi| V.dot(mesh.faces[fi].normal, axis).abs < 0.5 }
            spts = mesh.verts_of(side).map { |v| mesh.pos[v] }
            cyl = fit_cylinder(spts, axis)
            if cyl && cyl[2] < 0.03 && side.size >= 3
              info[:mode] = 'cylindrical'; info[:axis] = axis
              info[:origin] = cyl[0]; info[:radius] = cyl[1]; info[:reason] = 'cylinder'
              return info
            end
          end
        end

        defect, interior = max_angle_defect(mesh, face_ids)
        if interior > 0 && defect < 0.02
          info[:mode] = 'natural'; info[:reason] = 'developable'
          return info
        end

        cells = build_cells(mesh, face_ids)
        covered = 0
        cells[:cells].each { |c| covered += c[:faces].size }
        if face_ids.size >= 8 && covered >= face_ids.size * 0.6
          info[:mode] = 'quad'; info[:reason] = 'quad mesh'
          return info
        end

        if min_dot > 0.5
          info[:mode] = 'planar'; info[:reason] = 'height field'
          return info
        end

        info[:mode] = 'box'; info[:reason] = 'organic'
        info
      end

      def orient_axis(a)
        a = V.norm(a)
        big = 0
        3.times { |i| big = i if a[i].abs > a[big].abs }
        a[big] < 0 ? V.mul(a, -1.0) : a
      end

      # ------------------------------------------------------------------
      # Mapping modes. All return {fi => {vid => [u, v]}} in model inches
      # (real world size) plus optional :period info for fit mode.
      # ------------------------------------------------------------------

      # U,V frame for a planar projection seen from direction d (towards viewer)
      def planar_frame(d)
        d = V.norm(d)
        if d[2].abs < 0.999
          u = V.norm(V.cross([0.0, 0.0, 1.0], d))
        else
          u = [1.0, 0.0, 0.0]
        end
        v = V.cross(d, u)
        [u, v]
      end

      def map_planar(mesh, face_ids, u_axis, v_axis)
        out = {}
        face_ids.each do |fi|
          m = {}
          mesh.faces[fi].verts.each do |v|
            p = mesh.pos[v]
            m[v] = [V.dot(p, u_axis), V.dot(p, v_axis)]
          end
          out[fi] = m
        end
        out
      end

      def box_frame(n)
        ax, ay, az = n[0].abs, n[1].abs, n[2].abs
        if az >= ax && az >= ay
          n[2] >= 0 ? [[1.0, 0, 0], [0, 1.0, 0]] : [[-1.0, 0, 0], [0, 1.0, 0]]
        elsif ax >= ay
          n[0] >= 0 ? [[0, 1.0, 0], [0, 0, 1.0]] : [[0, -1.0, 0], [0, 0, 1.0]]
        else
          n[1] >= 0 ? [[-1.0, 0, 0], [0, 0, 1.0]] : [[1.0, 0, 0], [0, 0, 1.0]]
        end
      end

      def map_box(mesh, face_ids)
        out = {}
        face_ids.each do |fi|
          u, v = box_frame(mesh.faces[fi].normal)
          out.merge!(map_planar(mesh, [fi], u, v))
        end
        out
      end

      def wrap_near(ang, ref)
        return ref unless ang.finite? && ref.finite?
        ang -= TWO_PI while ang - ref > Math::PI
        ang += TWO_PI while ang - ref < -Math::PI
        ang
      end

      def rotate_about(vec, axis, ang)
        # Rodrigues
        c = Math.cos(ang); s = Math.sin(ang)
        V.add(V.add(V.mul(vec, c), V.mul(V.cross(axis, vec), s)),
              V.mul(axis, V.dot(axis, vec) * (1.0 - c)))
      end

      # opts: :axis, :origin, :radius, :seam (radians), :caps (true)
      def map_cylindrical(mesh, face_ids, opts)
        axis = V.norm(opts[:axis])
        origin = opts[:origin]
        radius = opts[:radius]
        e1, _e2 = perp_frame(axis)
        e1 = rotate_about(e1, axis, opts[:seam] || 0.0)
        e2 = V.cross(axis, e1)
        out = {}
        min_a = nil; max_a = nil
        face_ids.each do |fi|
          f = mesh.faces[fi]
          m = {}
          nd = V.dot(f.normal, axis)
          if opts[:caps] != false && nd.abs > 0.7
            capn = nd > 0 ? axis : V.mul(axis, -1.0)
            cu = e1
            cv = V.cross(capn, cu)
            f.verts.each do |v|
              d = V.sub(mesh.pos[v], origin)
              m[v] = [V.dot(d, cu), V.dot(d, cv)]
            end
            out[fi] = m
            next
          end
          dc = V.sub(f.center, origin)
          ref = Math.atan2(V.dot(dc, e2), V.dot(dc, e1))
          f.verts.each do |v|
            d = V.sub(mesh.pos[v], origin)
            x = V.dot(d, e1); y = V.dot(d, e2)
            ang = (x * x + y * y) < (radius * 1.0e-6)**2 ? ref : wrap_near(Math.atan2(y, x), ref)
            min_a = ang if min_a.nil? || ang < min_a
            max_a = ang if max_a.nil? || ang > max_a
            m[v] = [ang * radius, V.dot(d, axis)]
          end
          out[fi] = m
        end
        meta = {}
        meta[:u_period] = TWO_PI * radius if min_a && (max_a - min_a) > TWO_PI * 0.93
        [out, meta]
      end

      # opts: :axis, :center, :radius, :seam
      def map_spherical(mesh, face_ids, opts)
        axis = V.norm(opts[:axis])
        center = opts[:center]
        radius = opts[:radius]
        e1, _e2 = perp_frame(axis)
        e1 = rotate_about(e1, axis, opts[:seam] || 0.0)
        e2 = V.cross(axis, e1)
        out = {}
        min_a = nil; max_a = nil
        face_ids.each do |fi|
          f = mesh.faces[fi]
          dc = V.sub(f.center, center)
          ref = Math.atan2(V.dot(dc, e2), V.dot(dc, e1))
          m = {}
          f.verts.each do |v|
            d = V.sub(mesh.pos[v], center)
            r = V.len(d)
            r = radius if r < EPS
            h = V.dot(d, axis)
            s = h / r
            s = 1.0 if s > 1.0
            s = -1.0 if s < -1.0
            lat = Math.asin(s)
            x = V.dot(d, e1); y = V.dot(d, e2)
            lon = (x * x + y * y) < (r * 1.0e-4)**2 ? ref : wrap_near(Math.atan2(y, x), ref)
            min_a = lon if min_a.nil? || lon < min_a
            max_a = lon if max_a.nil? || lon > max_a
            m[v] = [lon * radius, lat * radius]
          end
          out[fi] = m
        end
        meta = {}
        meta[:u_period] = TWO_PI * radius if min_a && (max_a - min_a) > TWO_PI * 0.93
        [out, meta]
      end

      # Orientation of the uv map relative to the face normal (+1 / -1)
      def handedness(mesh, fi, m)
        f = mesh.faces[fi]
        vs = f.verts
        n = vs.size
        best = 0.0; sign = 1
        n.times do |i|
          a = vs[0]; b = vs[(i + 1) % n]; c = vs[(i + 2) % n]
          next if b == a || c == a || b == c
          s3 = V.dot(V.cross(V.sub(mesh.pos[b], mesh.pos[a]), V.sub(mesh.pos[c], mesh.pos[a])), f.normal)
          ua = m[a]; ub = m[b]; uc = m[c]
          next unless ua && ub && uc
          s2 = (ub[0] - ua[0]) * (uc[1] - ua[1]) - (ub[1] - ua[1]) * (uc[0] - ua[0])
          if (s3 * s2).abs > best
            best = (s3 * s2).abs
            sign = (s3 * s2) >= 0 ? 1 : -1
          end
        end
        sign
      end

      # Start map for natural mode: planar in the face's own plane, world aligned.
      def natural_start(mesh, fi)
        u, v = planar_frame(mesh.faces[fi].normal)
        map_planar(mesh, [fi], u, v)[fi]
      end

      # Unfold face g across edge (a,b) from already mapped face f.
      def unfold(mesh, f, fm, fh, g, a, b)
        p1 = mesh.pos[a]; p2 = mesh.pos[b]
        l = V.dist(p1, p2)
        return nil if l < EPS
        e = V.mul(V.sub(p2, p1), 1.0 / l)
        n2 = mesh.faces[g].normal
        w = V.cross(n2, e)
        ua = fm[a]; ub = fm[b]
        return nil unless ua && ub
        ex = [(ub[0] - ua[0]) / l, (ub[1] - ua[1]) / l]
        consistent = mesh.edge_dir(f, a, b) != mesh.edge_dir(g, a, b)
        h = consistent ? fh : -fh
        rx = [-ex[1] * h, ex[0] * h]
        m = {}
        mesh.faces[g].verts.each do |v|
          d = V.sub(mesh.pos[v], p1)
          s = V.dot(d, e); t = V.dot(d, w)
          m[v] = [ua[0] + s * ex[0] + t * rx[0], ua[1] + s * ex[1] + t * rx[1]]
        end
        [m, h]
      end

      # Natural (unfold) propagation.
      # seeds: {fi => map} already mapped faces (can be empty)
      # start: preferred start face id (or nil)
      def map_natural(mesh, face_ids, seeds = {}, start = nil, cross_hard = true)
        fset = {}
        face_ids.each { |f| fset[f] = true }
        out = {}
        hand = {}
        queue = []
        seeds.each do |fi, m|
          out[fi] = m
          hand[fi] = handedness(mesh, fi, m)
          queue << fi
        end
        remaining = lambda { face_ids.reject { |f| out[f] } }
        if queue.empty?
          s = (start && fset[start]) ? start : face_ids.max_by { |f| mesh.faces[f].area }
          if s
            out[s] = natural_start(mesh, s); hand[s] = 1; queue << s
          end
        end
        loop do
          head = 0
          while head < queue.size
            f = queue[head]; head += 1
            mesh.face_edge_keys(f).each do |a, b|
              e = mesh.edges[Mesh.key(a, b)]
              next unless e
              next if !e.soft && !cross_hard
              e.faces.each do |g|
                next if g == f || out[g] || !fset[g]
                r = unfold(mesh, f, out[f], hand[f], g, a, b)
                next unless r
                out[g] = r[0]; hand[g] = r[1]
                queue << g
              end
            end
          end
          rest = remaining.call
          break if rest.empty?
          s = rest.max_by { |f| mesh.faces[f].area }
          out[s] = natural_start(mesh, s); hand[s] = 1
          queue = [s]
        end
        out
      end

      # ---------------- Quad grid -------------------------------------

      def longest_edge_key(mesh, fi)
        best = nil; bl = -1.0
        mesh.face_edge_keys(fi).each do |a, b|
          l = V.dist(mesh.pos[a], mesh.pos[b])
          if l > bl then bl = l; best = Mesh.key(a, b) end
        end
        best
      end

      # Build quad cells from quad faces and pairs of triangles (diagonals).
      def build_cells(mesh, face_ids)
        fset = {}
        face_ids.each { |f| fset[f] = true }
        cells = []
        face_cell = {}
        tris = []
        face_ids.each do |fi|
          n = mesh.faces[fi].verts.size
          if n == 4
            face_cell[fi] = cells.size
            cells << { :corners => mesh.faces[fi].verts.dup, :faces => [fi] }
          elsif n == 3
            tris << fi
          end
        end
        tri = {}
        tris.each { |t| tri[t] = true }
        cands = []
        tris.each do |t|
          mesh.face_edge_keys(t).each do |a, b|
            k = Mesh.key(a, b)
            e = mesh.edges[k]
            next unless e && (e.soft || e.faces.size == 2)
            e.faces.each do |o|
              next if o <= t || !tri[o]
              next if V.dot(mesh.faces[t].normal, mesh.faces[o].normal) < 0.7
              lk = (longest_edge_key(mesh, t) == k ? 1 : 0) + (longest_edge_key(mesh, o) == k ? 1 : 0)
              next if lk == 0
              cands << [lk, (e.soft ? 1 : 0), V.dist(mesh.pos[a], mesh.pos[b]), t, o, k]
            end
          end
        end
        cands.sort! { |x, y| [y[0], y[1], y[2]] <=> [x[0], x[1], x[2]] }
        cands.each do |_lk, _s, _l, t, o, k|
          next if face_cell[t] || face_cell[o]
          vt = mesh.faces[t].verts
          vo = mesh.faces[o].verts
          x1 = (vt - k)[0]; x2 = (vo - k)[0]
          next unless x1 && x2
          i = vt.index(x1)
          r = [vt[i], vt[(i + 1) % 3], vt[(i + 2) % 3]]
          corners = [r[0], r[1], x2, r[2]]
          face_cell[t] = face_cell[o] = cells.size
          cells << { :corners => corners, :faces => [t, o] }
        end
        { :cells => cells, :face_cell => face_cell }
      end

      def map_quad(mesh, face_ids, start_face = nil)
        built = build_cells(mesh, face_ids)
        cells = built[:cells]
        face_cell = built[:face_cell]
        ij = {}
        order = []
        start_cell = start_face ? face_cell[start_face] : nil
        pending = (0...cells.size).to_a
        pending.sort_by! { |c| -cells[c][:faces].inject(0.0) { |s, f| s + mesh.faces[f].area } }
        pending.unshift(start_cell) if start_cell
        islands = []
        pending.each do |sc|
          next if ij[sc]
          c = cells[sc][:corners]
          ij[sc] = { c[0] => [0, 0], c[1] => [1, 0], c[2] => [1, 1], c[3] => [0, 1] }
          isl = [sc]
          queue = [sc]
          head = 0
          while head < queue.size
            ci = queue[head]; head += 1
            cc = cells[ci][:corners]
            4.times do |k|
              a = cc[k]; b = cc[(k + 1) % 4]; ap = cc[(k - 1) % 4]
              e = mesh.edges[Mesh.key(a, b)]
              next unless e
              e.faces.each do |g|
                ni = face_cell[g]
                next if ni.nil? || ni == ci || ij[ni]
                nc = cells[ni][:corners]
                ia = nc.index(a); ib = nc.index(b)
                next unless ia && ib
                next unless (ia - ib).abs == 1 || (ia - ib).abs == 3
                na = nc[(ia + 1) % 4] == b ? nc[(ia - 1) % 4] : nc[(ia + 1) % 4]
                nb = nc[(ib + 1) % 4] == a ? nc[(ib - 1) % 4] : nc[(ib + 1) % 4]
                ija = ij[ci][a]; ijb = ij[ci][b]; ijp = ij[ci][ap]
                dl = [ija[0] - ijp[0], ija[1] - ijp[1]]
                ij[ni] = { a => ija, b => ijb,
                           na => [ija[0] + dl[0], ija[1] + dl[1]],
                           nb => [ijb[0] + dl[0], ijb[1] + dl[1]] }
                isl << ni
                queue << ni
              end
            end
          end
          islands << isl
        end

        out = {}
        islands.each do |isl|
          col = Hash.new { |h, k| h[k] = [] }
          row = Hash.new { |h, k| h[k] = [] }
          isl.each do |ci|
            cc = cells[ci][:corners]
            4.times do |k|
              p = cc[k]; q = cc[(k + 1) % 4]
              a = ij[ci][p]; b = ij[ci][q]
              l = V.dist(mesh.pos[p], mesh.pos[q])
              if a[1] == b[1] && (a[0] - b[0]).abs == 1
                col[[a[0], b[0]].min] << l
              elsif a[0] == b[0] && (a[1] - b[1]).abs == 1
                row[[a[1], b[1]].min] << l
              end
            end
          end
          is = []; js = []
          isl.each { |ci| ij[ci].each_value { |x| is << x[0]; js << x[1] } }
          uu = cumulative(col, is.min, is.max)
          vv = cumulative(row, js.min, js.max)
          isl.each do |ci|
            cells[ci][:faces].each do |fi|
              m = {}
              mesh.faces[fi].verts.each do |v|
                g = ij[ci][v]
                m[v] = [uu[g[0]], vv[g[1]]]
              end
              out[fi] = m
            end
          end
        end
        out
      end

      def cumulative(lens, lo, hi)
        all = []
        lens.each_value { |a| all.concat(a) }
        avg_all = all.empty? ? 1.0 : all.inject(0.0) { |s, x| s + x } / all.size
        pos = { lo => 0.0 }
        acc = 0.0
        (lo...hi).each do |i|
          a = lens[i]
          w = (a.nil? || a.empty?) ? avg_all : a.inject(0.0) { |s, x| s + x } / a.size
          acc += w
          pos[i + 1] = acc
        end
        pos
      end

      # ------------------------------------------------------------------
      # Post processing
      # ------------------------------------------------------------------

      # Fit mode: normalise to [0, repeat] over the island.
      def fit_normalize(maps, meta, rep_u, rep_v)
        us = []; vs = []
        maps.each_value { |m| m.each_value { |uv| us << uv[0]; vs << uv[1] } }
        return maps if us.empty?
        umin = us.min; vmin = vs.min
        ur = meta[:u_period] || (us.max - umin)
        vr = meta[:v_period] || (vs.max - vmin)
        ur = 1.0 if ur.abs < EPS
        vr = 1.0 if vr.abs < EPS
        out = {}
        maps.each do |fi, m|
          nm = {}
          m.each { |v, uv| nm[v] = [(uv[0] - umin) / ur * rep_u, (uv[1] - vmin) / vr * rep_v] }
          out[fi] = nm
        end
        out
      end

      # t: {:scale_u, :scale_v (factors), :rot (radians), :off_u, :off_v, :flip_u, :flip_v}
      def transform_uv(uv, t)
        u = uv[0] / t[:scale_u]
        v = uv[1] / t[:scale_v]
        if t[:rot] != 0.0
          c = Math.cos(t[:rot]); s = Math.sin(t[:rot])
          u, v = u * c - v * s, u * s + v * c
        end
        u = -u if t[:flip_u]
        v = -v if t[:flip_v]
        [u + t[:off_u], v + t[:off_v]]
      end

      # Choose up to 4 (vid, uv) pairs to feed Face#position_material.
      # Returns [[vid, [u,v]], ...]. uv values are shifted by an integer
      # (does not change the look) to keep numbers small.
      def face_pairs(mesh, fi, m, allow4 = true)
        vs = mesh.faces[fi].verts.select { |v| m[v] }
        return nil if vs.size < 3
        shift_u = m[vs[0]][0].floor
        shift_v = m[vs[0]][1].floor
        uvs = {}
        vs.each { |v| uvs[v] = [m[v][0] - shift_u, m[v][1] - shift_v] }
        f = mesh.faces[fi]
        # local 2D frame
        o = mesh.pos[vs[0]]
        e1 = nil
        vs.each { |v| d = V.sub(mesh.pos[v], o); if V.len(d) > EPS * 100 then e1 = V.norm(d); break end }
        return nil unless e1
        e2 = V.cross(f.normal, e1)
        loc = {}
        vs.each { |v| d = V.sub(mesh.pos[v], o); loc[v] = [V.dot(d, e1), V.dot(d, e2)] }
        tri = best_triangle(vs, loc)
        return nil unless tri
        if vs.size == 3
          return vs.map { |v| [v, uvs[v]] }
        end
        aff = affine_fit(tri, loc, uvs)
        if vs.size == 4 && aff
          other = (vs - tri)[0]
          pred = apply_affine(aff, loc[other])
          err = Math.sqrt((pred[0] - uvs[other][0])**2 + (pred[1] - uvs[other][1])**2)
          if err < 1.0e-4
            return tri.map { |v| [v, uvs[v]] }
          elsif allow4
            return vs.map { |v| [v, uvs[v]] }
          end
        end
        aff = affine_fit(vs, loc, uvs) || aff
        return nil unless aff
        tri.map { |v| [v, apply_affine(aff, loc[v])] }
      end

      def best_triangle(vs, loc)
        a = vs[0]
        b = vs.max_by { |v| (loc[v][0] - loc[a][0])**2 + (loc[v][1] - loc[a][1])**2 }
        return nil if b == a
        c = vs.max_by do |v|
          ((loc[b][0] - loc[a][0]) * (loc[v][1] - loc[a][1]) -
           (loc[b][1] - loc[a][1]) * (loc[v][0] - loc[a][0])).abs
        end
        area = ((loc[b][0] - loc[a][0]) * (loc[c][1] - loc[a][1]) -
                (loc[b][1] - loc[a][1]) * (loc[c][0] - loc[a][0])).abs
        return nil if area < 1.0e-12
        [a, b, c]
      end

      def affine_fit(vs, loc, uvs)
        rows = vs.map { |v| [loc[v][0], loc[v][1], 1.0] }
        cu = LA.least_squares(rows, vs.map { |v| uvs[v][0] })
        cv = LA.least_squares(rows, vs.map { |v| uvs[v][1] })
        return nil unless cu && cv
        [cu, cv]
      end

      def apply_affine(aff, p)
        cu, cv = aff
        [cu[0] * p[0] + cu[1] * p[1] + cu[2], cv[0] * p[0] + cv[1] * p[1] + cv[2]]
      end

      # ------------------------------------------------------------------
      # Main entry: compute uv maps for a set of faces.
      # settings (symbol keys): :mode, :axis (nil or vector), :planar_u/:planar_v,
      #   :size_mode ('real'|'fit'), :repeat_u, :repeat_v, :seam (radians),
      #   :cross_hard, :start_face
      # Returns {:maps => {fi => {vid=>[u,v]}}, :islands => [info...]}
      # uv in inches for 'real' (divide by tile size later) or in tiles for 'fit'.
      # ------------------------------------------------------------------
      def compute(mesh, face_ids, s)
        fset = {}
        face_ids.each { |f| fset[f] = true }
        result = {}
        infos = []
        mesh.islands(fset).each do |isl|
          info = analyze_for(mesh, isl, s)
          infos << info
          maps, meta = run_mode(mesh, isl, info, s)
          # faces a mode could not reach get a natural fill
          missing = isl.reject { |f| maps[f] }
          unless missing.empty?
            maps = map_natural(mesh, isl, maps, nil, true)
          end
          if s[:size_mode] == 'fit'
            maps = fit_normalize(maps, meta || {}, s[:repeat_u] || 1.0, s[:repeat_v] || 1.0)
          end
          result.merge!(maps)
        end
        { :maps => result, :islands => infos }
      end

      def analyze_for(mesh, isl, s)
        mode = s[:mode] || 'auto'
        info = mode == 'auto' ? analyze(mesh, isl) : { :mode => mode }
        verts = mesh.verts_of(isl)
        pts = verts.map { |v| mesh.pos[v] }
        case info[:mode]
        when 'cylindrical'
          axis = s[:axis] ? V.norm(s[:axis]) : info[:axis]
          unless axis
            curved = isl.select { |fi| has_soft_edge?(mesh, fi) }
            curved = isl if curved.size < 3
            axis = orient_axis(normal_eigen(mesh, curved)[0][1])
          end
          info[:axis] = axis
          if info[:origin].nil? || s[:axis]
            side = isl.select { |fi| V.dot(mesh.faces[fi].normal, axis).abs < 0.7 }
            side = isl if side.size < 2
            cyl = fit_cylinder(mesh.verts_of(side).map { |v| mesh.pos[v] }, axis)
            if cyl
              info[:origin] = cyl[0]; info[:radius] = cyl[1]
            else
              c = bbox_center(pts)
              info[:origin] = c
              e1, e2 = perp_frame(axis)
              rs = pts.map { |p| d = V.sub(p, c); Math.sqrt(V.dot(d, e1)**2 + V.dot(d, e2)**2) }
              info[:radius] = [rs.inject(0.0) { |a, b| a + b } / rs.size, 1.0].max
            end
          end
        when 'spherical'
          info[:axis] = s[:axis] ? V.norm(s[:axis]) : (info[:axis] || [0.0, 0.0, 1.0])
          unless info[:center]
            sph = fit_sphere(pts)
            if sph && sph[2] < 0.25
              info[:center] = sph[0]; info[:radius] = sph[1]
            else
              c = bbox_center(pts)
              info[:center] = c
              rs = pts.map { |p| V.dist(p, c) }
              info[:radius] = [rs.inject(0.0) { |a, b| a + b } / rs.size, 1.0].max
            end
          end
        when 'planar'
          info[:normal] ||= average_normal(mesh, isl)
        end
        info
      end

      def run_mode(mesh, isl, info, s)
        start = s[:start_face]
        start = nil unless start && isl.include?(start)
        case info[:mode]
        when 'planar'
          if s[:planar_u] && s[:planar_v]
            [map_planar(mesh, isl, s[:planar_u], s[:planar_v]), {}]
          else
            d = s[:planar_dir] || info[:normal] || average_normal(mesh, isl)
            u, v = planar_frame(d)
            [map_planar(mesh, isl, u, v), {}]
          end
        when 'box'
          [map_box(mesh, isl), {}]
        when 'cylindrical'
          map_cylindrical(mesh, isl, :axis => info[:axis], :origin => info[:origin],
                                     :radius => info[:radius], :seam => s[:seam] || 0.0)
        when 'spherical'
          map_spherical(mesh, isl, :axis => info[:axis], :center => info[:center],
                                   :radius => info[:radius], :seam => s[:seam] || 0.0)
        when 'quad'
          [map_quad(mesh, isl, start), {}]
        else
          [map_natural(mesh, isl, {}, start, s[:cross_hard] != false), {}]
        end
      end

    end
  end
end
