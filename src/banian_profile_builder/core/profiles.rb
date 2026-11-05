# encoding: UTF-8
# Banian Profile Builder - parametric profile catalog (pure Ruby).
#
# A profile is a list of loops in millimetres: the first loop is the outer
# boundary, the following loops are holes. Every generator returns raw loops;
# Profiles.place normalises orientation, rotation, flip and anchor.

module BanianStudio
  module ProfileBuilder
    module Profiles
      Entry = Struct.new(:id, :name_en, :name_fa, :category, :params, :generator)

      CATALOG = []
      INDEX = {}

      ANCHORS = %w[tl tc tr ml mc mr bl bc br].freeze

      def self.define(id, name_en, name_fa, category, params, &gen)
        e = Entry.new(id, name_en, name_fa, category, params, gen)
        CATALOG << e
        INDEX[id] = e
        e
      end

      # ---------- helpers --------------------------------------------------

      def self.arc(cx, cy, rx, ry, a0, a1, segs)
        pts = []
        segs = 1 if segs < 1
        (0..segs).each do |i|
          a = (a0 + (a1 - a0) * i.to_f / segs) * Math::PI / 180.0
          pts << [cx + rx * Math.cos(a), cy + ry * Math.sin(a)]
        end
        pts
      end

      def self.circle(cx, cy, r, segs)
        pts = arc(cx, cy, r, r, 0.0, 360.0, segs)
        pts.pop # last == first
        pts
      end

      def self.segs_for(d)
        d = d.to_f
        return 16 if d <= 30
        return 24 if d <= 150
        32
      end

      def self.pos(v, min = 0.1)
        v = v.to_f
        v < min ? min : v
      end

      # ---------- catalog --------------------------------------------------

      P = lambda do |key, en, fa, default|
        { 'key' => key, 'en' => en, 'fa' => fa, 'default' => default }
      end

      define('rect', 'Rectangle / Lumber', 'مستطیل / چوب', 'basic',
             [P.call('w', 'Width', 'عرض', 89), P.call('h', 'Height', 'ارتفاع', 38)]) do |p|
        w = pos(p['w']); h = pos(p['h'])
        [[[0, 0], [w, 0], [w, h], [0, h]]]
      end

      define('round_bar', 'Round Bar', 'میله گرد', 'basic',
             [P.call('d', 'Diameter', 'قطر', 50)]) do |p|
        d = pos(p['d']); r = d / 2.0
        [circle(r, r, r, segs_for(d))]
      end

      define('half_round', 'Half Round', 'نیم‌گرد', 'basic',
             [P.call('d', 'Diameter', 'قطر', 60)]) do |p|
        d = pos(p['d']); r = d / 2.0
        pts = arc(r, 0, r, r, 0.0, 180.0, segs_for(d) / 2)
        [pts]
      end

      define('square_tube', 'Box Tube', 'قوطی', 'steel',
             [P.call('w', 'Width', 'عرض', 40), P.call('h', 'Height', 'ارتفاع', 40),
              P.call('t', 'Thickness', 'ضخامت', 2)]) do |p|
        w = pos(p['w']); h = pos(p['h'])
        t = [pos(p['t'], 0.05), [w, h].min / 2.0 - 0.05].min
        [[[0, 0], [w, 0], [w, h], [0, h]],
         [[t, t], [t, h - t], [w - t, h - t], [w - t, t]]]
      end

      define('round_tube', 'Pipe', 'لوله', 'steel',
             [P.call('d', 'Diameter', 'قطر', 48), P.call('t', 'Thickness', 'ضخامت', 3)]) do |p|
        d = pos(p['d']); r = d / 2.0
        t = [pos(p['t'], 0.05), r - 0.05].min
        n = segs_for(d)
        [circle(r, r, r, n), circle(r, r, r - t, n).reverse]
      end

      define('angle', 'Angle (L)', 'نبشی', 'steel',
             [P.call('w', 'Width', 'عرض', 50), P.call('h', 'Height', 'ارتفاع', 50),
              P.call('t', 'Thickness', 'ضخامت', 5)]) do |p|
        w = pos(p['w']); h = pos(p['h'])
        t = [pos(p['t'], 0.05), [w, h].min - 0.05].min
        [[[0, 0], [w, 0], [w, t], [t, t], [t, h], [0, h]]]
      end

      define('channel', 'Channel (U)', 'ناودانی', 'steel',
             [P.call('w', 'Flange', 'بال', 50), P.call('h', 'Depth', 'ارتفاع', 100),
              P.call('t', 'Thickness', 'ضخامت', 6)]) do |p|
        w = pos(p['w']); h = pos(p['h'])
        t = [pos(p['t'], 0.05), [w - 0.05, h / 2.0 - 0.05].min].min
        [[[0, 0], [w, 0], [w, t], [t, t], [t, h - t], [w, h - t], [w, h], [0, h]]]
      end

      define('i_beam', 'I-Beam (IPE)', 'تیرآهن', 'steel',
             [P.call('w', 'Flange', 'بال', 100), P.call('h', 'Depth', 'ارتفاع', 200),
              P.call('tw', 'Web', 'جان', 6), P.call('tf', 'Flange thk.', 'ضخامت بال', 9)]) do |p|
        w = pos(p['w']); h = pos(p['h'])
        tw = [pos(p['tw'], 0.05), w - 0.1].min
        tf = [pos(p['tf'], 0.05), h / 2.0 - 0.05].min
        a = (w - tw) / 2.0; b = (w + tw) / 2.0
        [[[0, 0], [w, 0], [w, tf], [b, tf], [b, h - tf], [w, h - tf], [w, h],
          [0, h], [0, h - tf], [a, h - tf], [a, tf], [0, tf]]]
      end

      define('t_bar', 'T-Bar', 'سپری', 'steel',
             [P.call('w', 'Width', 'عرض', 50), P.call('h', 'Height', 'ارتفاع', 50),
              P.call('t', 'Thickness', 'ضخامت', 5)]) do |p|
        w = pos(p['w']); h = pos(p['h'])
        t = [pos(p['t'], 0.05), [w, h].min - 0.05].min
        a = (w - t) / 2.0; b = (w + t) / 2.0
        [[[a, 0], [b, 0], [b, h - t], [w, h - t], [w, h], [0, h], [0, h - t], [a, h - t]]]
      end

      define('z_section', 'Z-Purlin', 'پروفیل Z', 'steel',
             [P.call('w', 'Flange', 'بال', 60), P.call('h', 'Depth', 'ارتفاع', 150),
              P.call('t', 'Thickness', 'ضخامت', 3)]) do |p|
        w = pos(p['w']); h = pos(p['h'])
        t = [pos(p['t'], 0.05), [w - 0.05, h / 2.0 - 0.05].min].min
        [[[-w + t, 0], [t, 0], [t, h - t], [w, h - t], [w, h], [0, h], [0, t], [-w + t, t]]]
      end

      define('baseboard', 'Baseboard', 'قرنیز پایین', 'trim',
             [P.call('h', 'Height', 'ارتفاع', 100), P.call('t', 'Thickness', 'ضخامت', 16)]) do |p|
        h = pos(p['h']); t = pos(p['t'])
        r = [t * 0.6, h].min
        pts = [[0, 0], [t, 0]]
        pts.concat(arc(t - r, h - r, r, r, 0.0, 90.0, 6))
        pts << [0, h]
        [pts]
      end

      define('crown', 'Crown Molding', 'ابزار سقفی', 'trim',
             [P.call('w', 'Projection', 'پیش‌آمدگی', 90), P.call('h', 'Height', 'ارتفاع', 90),
              P.call('t', 'Thickness', 'ضخامت', 14)]) do |p|
        w = pos(p['w']); h = pos(p['h'])
        t = [pos(p['t'], 0.05), [w, h].min - 0.05].min
        pts = [[0, 0]]
        pts.concat(arc(w, 0, w - t, h - t, 180.0, 90.0, 10))
        pts << [w, h]
        pts << [0, h]
        [pts]
      end

      define('chair_rail', 'Chair Rail', 'ابزار میانی', 'trim',
             [P.call('h', 'Height', 'ارتفاع', 60), P.call('t', 'Thickness', 'ضخامت', 22)]) do |p|
        h = pos(p['h']); t = pos(p['t'])
        r = [h / 2.0, t].min
        pts = [[0, 0], [t - r, 0]]
        pts.concat(arc(t - r, h / 2.0, r, h / 2.0, -90.0, 90.0, 10)[1..-2])
        pts << [t - r, h]
        pts << [0, h]
        [pts]
      end

      define('gutter', 'Gutter', 'ناودان', 'trim',
             [P.call('d', 'Diameter', 'قطر', 125), P.call('t', 'Thickness', 'ضخامت', 2)]) do |p|
        d = pos(p['d']); r = d / 2.0
        t = [pos(p['t'], 0.05), r - 0.05].min
        n = segs_for(d) / 2
        outer = arc(r, r, r, r, 180.0, 360.0, n)
        inner = arc(r, r, r - t, r - t, 360.0, 180.0, n)
        [outer + inner]
      end

      # ---------- resolve / place -----------------------------------------

      def self.entry(id)
        INDEX[id]
      end

      def self.defaults(id)
        e = INDEX[id]
        return {} unless e
        h = {}
        e.params.each { |pp| h[pp['key']] = pp['default'] }
        h
      end

      # Raw loops (mm) for a spec hash: {'profile'=>id, 'params'=>{}, 'custom_loops'=>[...]}
      def self.raw_loops(spec)
        id = spec['profile'].to_s
        params = spec['params'] || {}
        if id.start_with?('custom') && spec['custom_loops'].is_a?(Array) && !spec['custom_loops'].empty?
          return scale_custom(spec['custom_loops'], params)
        end
        e = INDEX[id] || INDEX['rect']
        merged = defaults(e.id).merge(params)
        e.generator.call(merged)
      end

      # Custom profiles are stored at native size; 'w'/'h' scale them.
      def self.scale_custom(loops, params)
        bb = bbox(loops)
        nw = bb[2] - bb[0]; nh = bb[3] - bb[1]
        nw = 1.0 if nw <= 0; nh = 1.0 if nh <= 0
        sx = params['w'] ? pos(params['w']) / nw : 1.0
        sy = params['h'] ? pos(params['h']) / nh : 1.0
        loops.map { |l| l.map { |q| [(q[0] - bb[0]) * sx, (q[1] - bb[1]) * sy] } }
      end

      def self.bbox(loops)
        xs = []; ys = []
        loops.each { |l| l.each { |q| xs << q[0].to_f; ys << q[1].to_f } }
        return [0, 0, 0, 0] if xs.empty?
        [xs.min, ys.min, xs.max, ys.max]
      end

      def self.signed_area(loop)
        a = 0.0
        n = loop.size
        n.times do |i|
          p = loop[i]; q = loop[(i + 1) % n]
          a += p[0] * q[1] - q[0] * p[1]
        end
        a / 2.0
      end

      # Net area (outer minus holes) in mm^2.
      def self.area(loops)
        return 0.0 if loops.empty?
        total = signed_area(loops[0]).abs
        loops[1..-1].each { |l| total -= signed_area(l).abs }
        total
      end

      # Removes duplicated / collinear points so we never create useless edges.
      def self.clean_loop(loop)
        pts = []
        loop.each do |q|
          q = [q[0].to_f, q[1].to_f]
          next if !pts.empty? && (pts[-1][0] - q[0]).abs < 1e-6 && (pts[-1][1] - q[1]).abs < 1e-6
          pts << q
        end
        pts.pop while pts.size > 1 && (pts[0][0] - pts[-1][0]).abs < 1e-6 && (pts[0][1] - pts[-1][1]).abs < 1e-6
        changed = true
        while changed && pts.size > 3
          changed = false
          n = pts.size
          n.times do |i|
            a = pts[(i - 1) % n]; b = pts[i]; c = pts[(i + 1) % n]
            cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
            l1 = Math.hypot(b[0] - a[0], b[1] - a[1]); l2 = Math.hypot(c[0] - b[0], c[1] - b[1])
            next if l1 < 1e-9 || l2 < 1e-9
            dot = (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1])
            if (cr / (l1 * l2)).abs < 1e-9 && dot > 0
              pts.delete_at(i)
              changed = true
              break
            end
          end
        end
        pts
      end

      # Rotation / flip / anchor / offset. Returns loops in mm with the path
      # passing through (0,0). Outer loop CCW, holes CW.
      def self.place(loops, anchor = 'mc', rotation = 0, flip = false, off_u = 0, off_v = 0)
        a = rotation.to_f * Math::PI / 180.0
        ca = Math.cos(a); sa = Math.sin(a)
        ca = ca.round(12); sa = sa.round(12)
        out = loops.map do |l|
          l.map do |q|
            x = q[0].to_f * ca - q[1].to_f * sa
            y = q[0].to_f * sa + q[1].to_f * ca
            x = -x if flip
            [x, y]
          end
        end
        bb = bbox(out)
        anchor = 'mc' unless ANCHORS.include?(anchor.to_s)
        ax = case anchor.to_s[1]
             when 'l' then bb[0]
             when 'r' then bb[2]
             else (bb[0] + bb[2]) / 2.0
             end
        ay = case anchor.to_s[0]
             when 'b' then bb[1]
             when 't' then bb[3]
             else (bb[1] + bb[3]) / 2.0
             end
        du = off_u.to_f - ax; dv = off_v.to_f - ay
        out = out.map { |l| clean_loop(l.map { |q| [q[0] + du, q[1] + dv] }) }
        out = out.reject { |l| l.size < 3 }
        out.each_with_index.map do |l, i|
          ar = signed_area(l)
          if i == 0
            ar < 0 ? l.reverse : l
          else
            ar > 0 ? l.reverse : l
          end
        end
      end

      # Full pipeline for a member spec, result in mm.
      def self.placed_loops(spec)
        place(raw_loops(spec), spec['anchor'] || 'mc', spec['rotation'] || 0,
              spec['flip'] ? true : false, spec['offset_u'] || 0, spec['offset_v'] || 0)
      end

      def self.to_inches(loops)
        k = 1.0 / 25.4
        loops.map { |l| l.map { |q| [q[0] * k, q[1] * k] } }
      end

      def self.size_label(spec)
        params = spec['params'] || {}
        id = spec['profile'].to_s
        keys = if INDEX[id]
                 INDEX[id].params.map { |pp| pp['key'] }
               else
                 params.keys.sort
               end
        merged = (INDEX[id] ? defaults(id) : {}).merge(params)
        keys.map { |k| fmt(merged[k]) }.join("×")
      end

      def self.fmt(v)
        f = v.to_f
        (f - f.round).abs < 1e-6 ? f.round.to_s : format('%.1f', f)
      end

      # Data for the dialog (names, params and a thumbnail outline).
      def self.catalog_json
        CATALOG.map do |e|
          {
            'id' => e.id, 'en' => e.name_en, 'fa' => e.name_fa, 'category' => e.category,
            'params' => e.params,
            'thumb' => place(e.generator.call(defaults(e.id)), 'mc', 0, false, 0, 0)
          }
        end
      end
    end
  end
end
