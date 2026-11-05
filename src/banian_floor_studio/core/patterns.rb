# Pattern generators (pure Ruby). All lengths in inches, angles in radians.
module BanianStudio
  module FloorStudio
    class TooManyTiles < StandardError; end

    class Tile
      attr_accessor :shape, :key, :cx, :cy, :ang, :tag, :tilt,
                    :poly, :state, :mat, :variant, :index
      def initialize(shape, key, cx, cy, ang, tag = 0, tilt = 0.0)
        @shape = shape
        @key = key
        @cx = cx
        @cy = cy
        @ang = ang
        @tag = tag
        @tilt = tilt
        @variant = 0
        @mat = 0
      end
    end

    module Patterns
      MAX_TILES = 60_000
      LIST = %w[grid brick wood herringbone chevron basket hexagon hopscotch voronoi siding].freeze

      module_function

      def rect(l, w)
        hl = l * 0.5
        hw = w * 0.5
        [[-hl, -hw], [hl, -hw], [hl, hw], [-hl, hw]]
      end

      def rkey(l, w)
        format('R%.4fx%.4f', l, w)
      end

      def num(p, k, d)
        v = p[k]
        v.nil? ? d : v.to_f
      end

      # Normalised, validated parameters (inches / radians).
      def norm(p)
        q = p.dup
        q[:length] = [num(p, :length, 23.62), 0.04].max
        q[:width] = [num(p, :width, 23.62), 0.04].max
        q[:gap] = [num(p, :gap, 0.0), 0.0].max
        q[:offset] = num(p, :offset, 0.5) % 1.0
        q[:wood_min] = [num(p, :wood_min, q[:length] * 0.5), 0.2].max
        q[:wood_max] = [num(p, :wood_max, q[:length]), q[:wood_min]].max
        q[:length_step] = [num(p, :length_step, 0.0), 0.0].max
        q[:stagger] = [num(p, :stagger, 7.87), 0.0].max
        q[:chevron_angle] = num(p, :chevron_angle, Math::PI / 4)
        q[:chevron_angle] = [[q[:chevron_angle], 0.17].max, 1.4].min
        q[:basket_n] = [[num(p, :basket_n, 3).round, 1].max, 12].min
        q[:small] = [num(p, :small, q[:length] * 0.5), 0.04].max
        q[:small] = q[:length] * 0.95 if q[:small] >= q[:length]
        q[:jitter] = [[num(p, :jitter, 0.8), 0.0].max, 1.0].min
        q[:tilt] = num(p, :tilt, 0.0)
        q[:angle] = num(p, :angle, 0.0)
        q[:offset_x] = num(p, :offset_x, 0.0)
        q[:offset_y] = num(p, :offset_y, 0.0)
        q[:seed] = num(p, :seed, 1).to_i
        q[:anchor_center] = p[:anchor_center] == true || p[:anchor_center].to_s == 'true'
        q[:pattern] = LIST.include?(p[:pattern].to_s) ? p[:pattern].to_s : 'grid'
        q[:gap] = [q[:gap], 0.02].max if q[:pattern] == 'voronoi'
        q
      end

      # Approximate tile area for count estimation.
      def tile_area(p)
        case p[:pattern]
        when 'wood' then ((p[:wood_min] + p[:wood_max]) * 0.5 + p[:gap]) * (p[:width] + p[:gap])
        when 'hexagon' then 0.866 * (p[:length] + p[:gap])**2
        when 'hopscotch' then (p[:length] + p[:gap])**2 + (p[:small] + p[:gap])**2
        when 'basket' then ((p[:length] + p[:gap])**2) / p[:basket_n]
        when 'voronoi' then p[:length]**2
        else (p[:length] + p[:gap]) * (p[:width] + p[:gap])
        end
      end

      def max_dim(p)
        [p[:length], p[:width], p[:wood_max], p[:small]].max * 2.0 + p[:gap] * 2
      end

      # Reference tile center (pattern frame) used for "center" anchoring.
      def ref_center(p)
        case p[:pattern]
        when 'hexagon', 'voronoi' then [0.0, 0.0]
        when 'hopscotch' then [p[:length] * 0.5, p[:length] * 0.5]
        when 'herringbone' then Geom2D.rotate([p[:length] * 0.5, p[:width] * 0.5], -Math::PI / 4)
        when 'basket' then [p[:length] * 0.5, p[:length] * 0.5]
        when 'chevron'
          a = p[:chevron_angle]
          cw = p[:length] * Math.cos(a)
          [cw + p[:gap] * 0.5, p[:width] / Math.cos(a) * 0.5 + Math.tan(a) * cw]
        else [p[:length] * 0.5, p[:width] * 0.5]
        end
      end

      # Period for seamless textures (pattern frame): [px, py] or nil.
      def period(p)
        g = p[:gap]
        case p[:pattern]
        when 'grid' then [p[:length] + g, p[:width] + g]
        when 'brick', 'siding'
          r = p[:offset].rationalize(Rational(1, 200))
          q = r.denominator
          q = 1 if p[:offset] < 1.0e-6
          return nil if q > 16
          [p[:length] + g, (p[:width] + g) * q]
        when 'herringbone'
          s = Math.sqrt(2.0)
          [(p[:width] + g) * s, (p[:length] + g) * s]
        when 'chevron'
          a = p[:chevron_angle]
          cw = p[:length] * Math.cos(a)
          [2 * (cw + g), p[:width] / Math.cos(a) + g / Math.cos(a)]
        when 'basket' then [2 * (p[:length] + g), 2 * (p[:length] + g)]
        when 'hexagon'
          fp = p[:length] + g
          [3 * fp / Math.sqrt(3.0), fp]
        end
      end

      # ---- generators: yield tiles in pattern frame within bbox ------------
      def generate(p, bb, &blk)
        send("gen_#{p[:pattern]}", p, bb, &blk)
      end

      def gen_grid(p, bb)
        l = p[:length]
        w = p[:width]
        px = l + p[:gap]
        py = w + p[:gap]
        sh = rect(l, w)
        k = rkey(l, w)
        ((bb[1] / py).floor - 1..(bb[3] / py).ceil).each do |j|
          ((bb[0] / px).floor - 1..(bb[2] / px).ceil).each do |i|
            yield Tile.new(sh, k, i * px + l * 0.5, j * py + w * 0.5, 0.0, (i + j) % 2)
          end
        end
      end

      def gen_brick(p, bb, tilt = 0.0)
        l = p[:length]
        w = p[:width]
        px = l + p[:gap]
        py = w + p[:gap]
        sh = rect(l, w)
        k = rkey(l, w)
        ((bb[1] / py).floor - 1..(bb[3] / py).ceil).each do |j|
          sx = ((j * p[:offset]) % 1.0) * px
          ((bb[0] - sx) / px).floor.-(1).upto(((bb[2] - sx) / px).ceil) do |i|
            yield Tile.new(sh, k, sx + i * px + l * 0.5, j * py + w * 0.5, 0.0, j % 2, tilt)
          end
        end
      end

      def gen_siding(p, bb, &blk)
        gen_brick(p, bb, p[:tilt], &blk)
      end

      def row_rng(p, j)
        Random.new((p[:seed] * 1_000_003 + j + 50_000_000).abs)
      end

      def rand_len(p, rng)
        lmin = p[:wood_min]
        lmax = p[:wood_max]
        v = lmin + rng.rand * (lmax - lmin)
        st = p[:length_step]
        v = lmin + ((v - lmin) / st).round * st if st > 0.01
        [[v, lmin].max, lmax].min
      end

      def gen_wood(p, bb)
        w = p[:width]
        g = p[:gap]
        py = w + g
        prev = []
        j0 = (bb[1] / py).floor - 1
        j1 = (bb[3] / py).ceil
        (j0..j1).each do |j|
          rng = row_rng(p, j)
          x = bb[0] - p[:wood_max] - rng.rand * p[:wood_max]
          joints = []
          while x < bb[2] + g
            len = nil
            6.times do
              len = rand_len(p, rng)
              jx = x + len + g * 0.5
              ok = prev.all? { |px| (px - jx).abs >= p[:stagger] }
              break if ok
            end
            yield Tile.new(rect(len, w), rkey(len, w), x + len * 0.5, j * py + w * 0.5, 0.0, j % 2)
            x += len + g
            joints << x - g * 0.5
          end
          prev = joints
        end
      end

      # Generic lattice enumerator for patterns defined by two vectors.
      def lattice(bb, t1, t2, margin)
        det = t1[0] * t2[1] - t1[1] * t2[0]
        corners = [[bb[0] - margin, bb[1] - margin], [bb[2] + margin, bb[1] - margin],
                   [bb[2] + margin, bb[3] + margin], [bb[0] - margin, bb[3] + margin]]
        as = []
        bs = []
        corners.each do |c|
          as << (c[0] * t2[1] - c[1] * t2[0]) / det
          bs << (t1[0] * c[1] - t1[1] * c[0]) / det
        end
        (as.min.floor - 1..as.max.ceil + 1).each do |a|
          (bs.min.floor - 1..bs.max.ceil + 1).each do |b|
            yield a, b, [a * t1[0] + b * t2[0], a * t1[1] + b * t2[1]]
          end
        end
      end

      def gen_herringbone(p, bb)
        l = p[:length]
        w = p[:width]
        g = p[:gap]
        lp = l + g
        wp = w + g
        base = -Math::PI / 4
        # bbox in internal (unrotated) frame
        pts = [[bb[0], bb[1]], [bb[2], bb[1]], [bb[2], bb[3]], [bb[0], bb[3]]].map { |c| Geom2D.rotate(c, -base) }
        ib = Geom2D.bbox(pts)
        sh = rect(l, w)
        k = rkey(l, w)
        lattice(ib, [wp, wp], [lp, -lp], lp) do |_a, _b, o|
          h = [o[0] + l * 0.5, o[1] + w * 0.5]
          v = [o[0] + lp + w * 0.5, o[1] + wp - lp + l * 0.5]
          hc = Geom2D.rotate(h, base)
          vc = Geom2D.rotate(v, base)
          yield Tile.new(sh, k, hc[0], hc[1], base, 0)
          yield Tile.new(sh, k, vc[0], vc[1], base + Math::PI / 2, 1)
        end
      end

      def gen_chevron(p, bb)
        a = p[:chevron_angle]
        g = p[:gap]
        cw = p[:length] * Math.cos(a)
        t = Math.tan(a)
        h = p[:width] / Math.cos(a)
        hp = h + g / Math.cos(a)
        cwp = cw + g
        rise = t * cw
        shapes = [1, -1].map do |s|
          tt = t * s
          [[-cw * 0.5, -h * 0.5 - tt * cw * 0.5], [cw * 0.5, -h * 0.5 + tt * cw * 0.5],
           [cw * 0.5, h * 0.5 + tt * cw * 0.5], [-cw * 0.5, h * 0.5 - tt * cw * 0.5]]
        end
        keys = [format('C%.4f/%.4f/%.4f+', cw, h, a), format('C%.4f/%.4f/%.4f-', cw, h, a)]
        ((bb[0] / cwp).floor - 1..(bb[2] / cwp).ceil).each do |c|
          par = c % 2
          j0 = ((bb[1] - rise) / hp).floor - 1
          j1 = ((bb[3] + rise) / hp).ceil + 1
          (j0..j1).each do |j|
            y0 = j * hp + (par == 1 ? rise : 0.0)
            cy = y0 + h * 0.5 + (par == 0 ? rise * 0.5 : -rise * 0.5)
            yield Tile.new(shapes[par], keys[par], c * cwp + cw * 0.5, cy, 0.0, par)
          end
        end
      end

      def gen_basket(p, bb)
        l = p[:length]
        n = p[:basket_n]
        g = p[:gap]
        w = (l - (n - 1) * g) / n
        bp = l + g
        sh = rect(l, w)
        k = rkey(l, w)
        ((bb[1] / bp).floor - 1..(bb[3] / bp).ceil).each do |j|
          ((bb[0] / bp).floor - 1..(bb[2] / bp).ceil).each do |i|
            ox = i * bp
            oy = j * bp
            hor = (i + j).even?
            n.times do |s|
              off = s * (w + g) + w * 0.5
              if hor
                yield Tile.new(sh, k, ox + l * 0.5, oy + off, 0.0, 0)
              else
                yield Tile.new(sh, k, ox + off, oy + l * 0.5, Math::PI / 2, 1)
              end
            end
          end
        end
      end

      def gen_hexagon(p, bb)
        f = p[:length]
        g = p[:gap]
        r = f / Math.sqrt(3.0)
        fp = f + g
        rp = fp / Math.sqrt(3.0)
        sh = (0...6).map { |i| [r * Math.cos(i * Math::PI / 3), r * Math.sin(i * Math::PI / 3)] }
        k = format('H%.4f', f)
        dx = 1.5 * rp
        ((bb[0] / dx).floor - 1..(bb[2] / dx).ceil + 1).each do |c|
          off = c.odd? ? fp * 0.5 : 0.0
          ((bb[1] / fp).floor - 1..(bb[3] / fp).ceil + 1).each do |j|
            yield Tile.new(sh, k, c * dx, j * fp + off, 0.0, c % 2)
          end
        end
      end

      def gen_hopscotch(p, bb)
        a = p[:length]
        b = p[:small]
        g = p[:gap]
        ap = a + g
        bp = b + g
        sa = rect(a, a)
        sb = rect(b, b)
        ka = rkey(a, a)
        kb = rkey(b, b)
        lattice(bb, [ap, bp], [-bp, ap], ap) do |_i, _j, o|
          yield Tile.new(sa, ka, o[0] + a * 0.5, o[1] + a * 0.5, 0.0, 0)
          yield Tile.new(sb, kb, o[0] + ap + b * 0.5, o[1] + b * 0.5, 0.0, 1)
        end
      end

      def hash01(seed, i, j, k)
        h = (seed * 374_761_393 + i * 668_265_263 + j * 2_246_822_519 + k * 3_266_489_917) & 0xFFFFFFFF
        h = ((h ^ (h >> 13)) * 1_274_126_177) & 0xFFFFFFFF
        h ^= (h >> 16)
        h.to_f / 4_294_967_296.0
      end

      def vpoint(p, i, j)
        s = p[:length]
        jt = p[:jitter]
        [(i + 0.5 + (hash01(p[:seed], i, j, 1) - 0.5) * jt) * s,
         (j + 0.5 + (hash01(p[:seed], i, j, 2) - 0.5) * jt) * s]
      end

      def gen_voronoi(p, bb)
        s = p[:length]
        hg = p[:gap] * 0.5
        ((bb[1] / s).floor - 1..(bb[3] / s).ceil).each do |j|
          ((bb[0] / s).floor - 1..(bb[2] / s).ceil).each do |i|
            c = vpoint(p, i, j)
            poly = [[c[0] - 2 * s, c[1] - 2 * s], [c[0] + 2 * s, c[1] - 2 * s],
                    [c[0] + 2 * s, c[1] + 2 * s], [c[0] - 2 * s, c[1] + 2 * s]]
            (-2..2).each do |di|
              (-2..2).each do |dj|
                next if di == 0 && dj == 0
                q = vpoint(p, i + di, j + dj)
                nx = q[0] - c[0]
                ny = q[1] - c[1]
                len = Math.hypot(nx, ny)
                next if len < 1.0e-9
                nx /= len
                ny /= len
                mid = (c[0] + q[0]) * 0.5 * nx + (c[1] + q[1]) * 0.5 * ny
                poly = Geom2D.clip_half_plane(poly, nx, ny, mid - hg)
                break if poly.empty?
              end
            end
            next if poly.length < 3 || Geom2D.area(poly) < 1.0e-4
            ctr = Geom2D.centroid(poly)
            shape = Geom2D.ccw(poly.map { |pt| [pt[0] - ctr[0], pt[1] - ctr[1]] })
            yield Tile.new(shape, nil, ctr[0], ctr[1], 0.0, (i + j) % 2)
          end
        end
      end

      # ---- layout driver ----------------------------------------------------
      # region: {:outer, :holes} in local coords. opts[:world_origin] local pt.
      # Returns {:tiles => [Tile(state :inside/:boundary)], :origin, :theta}
      # Pattern origin (local) + the visible start-point marker.
      # anchor: corner | center | world | custom (opts[:custom] local pt).
      # p[:anchor_center]: put a tile centre (instead of a joint) on the point.
      def origin_for(region, p, opts = {})
        rb = Geom2D.bbox(region[:outer])
        theta = p[:angle]
        anchor = p[:anchor].to_s
        anchor = 'corner' if anchor == 'custom' && opts[:custom].nil?
        pt =
          case anchor
          when 'center' then [(rb[0] + rb[2]) * 0.5, (rb[1] + rb[3]) * 0.5]
          when 'world' then opts[:world_origin] || [0.0, 0.0]
          when 'custom' then opts[:custom]
          else [rb[0], rb[1]]
          end
        pt = [pt[0] + p[:offset_x], pt[1] + p[:offset_y]]
        centered = anchor == 'center' || (anchor == 'custom' && p[:anchor_center])
        origin = pt
        if centered
          rc = Geom2D.rotate(ref_center(p), theta)
          origin = [pt[0] - rc[0], pt[1] - rc[1]]
        end
        [origin, pt]
      end

      def layout(region, praw, opts = {})
        p = norm(praw)
        rb = Geom2D.bbox(region[:outer])
        theta = p[:angle]
        origin, marker = origin_for(region, p, opts)

        est = (rb[2] - rb[0] + max_dim(p)) * (rb[3] - rb[1] + max_dim(p)) / tile_area(p)
        limit = opts[:max_tiles] || MAX_TILES
        raise TooManyTiles, est.round.to_s if est > limit * 1.6

        corners = [[rb[0], rb[1]], [rb[2], rb[1]], [rb[2], rb[3]], [rb[0], rb[3]]]
        pc = corners.map { |c| Geom2D.rotate([c[0] - origin[0], c[1] - origin[1]], -theta) }
        pb = Geom2D.bbox(pc)
        m = max_dim(p)
        pb = [pb[0] - m, pb[1] - m, pb[2] + m, pb[3] + m]

        segs = Geom2D.region_segments(region)
        cell = [Math.sqrt(tile_area(p)), (rb[2] - rb[0] + rb[3] - rb[1]) / 200.0].max
        index = Geom2D::SegmentIndex.new(segs, cell)
        cos_t = Math.cos(theta)
        sin_t = Math.sin(theta)
        tiles = []
        generate(p, pb) do |t|
          x = t.cx * cos_t - t.cy * sin_t + origin[0]
          y = t.cx * sin_t + t.cy * cos_t + origin[1]
          t.cx = x
          t.cy = y
          t.ang += theta
          ca = Math.cos(t.ang)
          sa = Math.sin(t.ang)
          t.poly = t.shape.map { |s| [s[0] * ca - s[1] * sa + x, s[0] * sa + s[1] * ca + y] }
          tb = Geom2D.bbox(t.poly)
          next unless Geom2D.bbox_overlap?(tb, rb)
          st = Geom2D.classify(t.poly, region, index)
          next if st == :outside
          t.state = st
          t.index = tiles.length
          tiles << t
          raise TooManyTiles, tiles.length.to_s if tiles.length > limit
        end
        { :tiles => tiles, :origin => origin, :marker => marker, :theta => theta, :params => p, :index => index }
      end

      # Tiles covering one texture period (pattern frame, unrotated) for
      # texture export. Returns [w, h, tiles, seamless].
      def texture_tiles(praw)
        p = norm(praw)
        per = period(p)
        seamless = !per.nil?
        per ||= [[p[:length], p[:wood_max]].max * 4 + p[:gap] * 4, [p[:width], p[:length]].max * 4]
        m = max_dim(p)
        list = []
        generate(p, [-m, -m, per[0] + m, per[1] + m]) do |t|
          ca = Math.cos(t.ang)
          sa = Math.sin(t.ang)
          t.poly = t.shape.map { |s| [s[0] * ca - s[1] * sa + t.cx, s[0] * sa + s[1] * ca + t.cy] }
          tb = Geom2D.bbox(t.poly)
          next unless Geom2D.bbox_overlap?(tb, [0, 0, per[0], per[1]])
          t.index = list.length
          list << t
          raise TooManyTiles, list.length.to_s if list.length > 20_000
        end
        [per[0], per[1], list, seamless, p]
      end
    end
  end
end
