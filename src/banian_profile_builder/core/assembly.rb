# encoding: UTF-8
# Banian Profile Builder - assemblies (pure Ruby).
#
# An assembly is a list of rows built along one path:
#   layer  : a profile swept along the path (plates, rails, trims, glass...)
#   repeat : a straight piece repeated along the path (studs, posts...)
# Openings cut layers and trim repeated pieces (doors, windows, gates).
# Lengths in the spec are millimetres; planning output is in inches.

module BanianStudio
  module ProfileBuilder
    module Assembly
      V = Vec
      MM = 1.0 / 25.4

      module_function

      def component?(row)
        row['type'] == 'component'
      end

      def repeated?(row)
        row['type'] == 'repeat' || row['type'] == 'component'
      end

      def bay?(row)
        row['type'] == 'bay'
      end

      def row_profile_spec(row)
        if component?(row)
          return {
            'profile' => 'rect',
            'params' => { 'w' => [row['comp_w'].to_f, 1.0].max, 'h' => [row['comp_d'].to_f, 1.0].max },
            'anchor' => 'mc', 'rotation' => row['rotation'] || 0, 'flip' => row['flip'] ? true : false,
            'offset_u' => row['offset_u'] || 0, 'offset_v' => 0
          }
        end
        {
          'profile' => row['profile'] || 'rect', 'params' => row['params'] || {},
          'custom_loops' => row['custom_loops'],
          'anchor' => row['anchor'] || (repeated?(row) ? 'mc' : 'bc'),
          'rotation' => row['rotation'] || 0, 'flip' => row['flip'] ? true : false,
          'offset_u' => row['offset_u'] || 0, 'offset_v' => repeated?(row) ? 0 : (row['offset_v'] || 0)
        }
      end

      def apply_global_flip(row, flip)
        return row unless flip
        r = row.dup
        r['offset_u'] = -(r['offset_u'] || 0).to_f
        r['flip'] = !r['flip']
        r
      end

      # Distances along the path for a repeat row.
      def positions(total, closed, row, corner_s)
        sp = [(row['spacing'] || 400).to_f * MM, 0.5].max
        s0 = (row['setback_start'] || 0).to_f * MM
        s1 = total - (row['setback_end'] || 0).to_f * MM
        list = []
        if closed
          n = [(total / sp).ceil, 1].max
          n.times { |i| list << total * i / n }
        elsif s1 <= s0
          list << total / 2.0
        elsif row['mode'] == 'fixed'
          s = s0
          while s < s1 - 1e-4
            list << s
            s += sp
          end
          list << s1
        else
          n = [((s1 - s0) / sp - 1e-9).ceil, 1].max
          (0..n).each { |i| list << s0 + (s1 - s0) * i / n }
        end
        if row['at_corners']
          corner_s.each { |c| list << c }
          list.sort!
        end
        dedupe(list, sp * 0.25)
      end

      def dedupe(list, tol)
        out = []
        list.sort.each { |s| out << s if out.empty? || s - out[-1] > tol }
        out
      end

      def subtract_range(pieces, a, b)
        out = []
        pieces.each do |p0, p1|
          if b <= p0 || a >= p1
            out << [p0, p1]
          else
            out << [p0, a] if a - p0 > 0.04
            out << [b, p1] if p1 - b > 0.04
          end
        end
        out
      end

      # prep = Sweep.prepare(...) result. Returns a plan (inches):
      #  layers:  [{row:, index:, loops:, paths: [[pts, closed]], length:}]
      #  repeats: [{row:, index:, loops:, items: [{origin:, frame:, v0:, len:}]}]
      def plan(prep, spec)
        pts = prep[:points]; closed = prep[:closed]
        frs = Sweep.frames(pts, closed, prep[:up])
        cum = PathOps.cumulative(pts, closed)
        total = cum[-1]
        corner_s = closed ? cum[0...-1] : cum
        openings = (spec['openings'] || []).map do |o|
          at = o['at'].to_f * MM
          w = [o['width'].to_f * MM, 0.0].max
          sill = o['sill'].to_f * MM
          head = o['head'].nil? ? 1e9 : o['head'].to_f * MM
          head = 1e9 if head <= sill
          { a: at, b: at + w, sill: sill, head: head, jambs: o['jambs'] ? true : false }
        end
        flip = spec['flip'] ? true : false
        result = { layers: [], repeats: [], bays: [], total: total }
        bay_rows = []
        (spec['rows'] || []).each_with_index do |row0, idx|
          row = apply_global_flip(row0, flip)
          if bay?(row)
            bay_rows << [row, idx]
            next
          end
          loops_mm = Profiles.placed_loops(row_profile_spec(row))
          next if loops_mm.empty?
          loops = Profiles.to_inches(loops_mm)
          if repeated?(row)
            result[:repeats] << plan_repeat(row, idx, loops, pts, closed, frs, cum, total, corner_s, openings)
          else
            bb = Profiles.bbox(loops)
            cuts = openings.select { |o| bb[1] < o[:head] - 1e-4 && bb[3] > o[:sill] + 1e-4 }.map { |o| [o[:a], o[:b]] }
            kept = PathOps.kept_ranges(total, closed, cuts)
            paths = if kept.nil?
                      [[pts, closed]]
                    else
                      kept.map { |a, b| [PathOps.subpath(pts, closed, a, b), false] }.select { |p, _| p.size >= 2 }
                    end
            length = paths.inject(0.0) { |s, (p, c)| s + PathOps.length(p, c) }
            result[:layers] << { row: row, index: idx, loops: loops, paths: paths, length: length,
                                 area_mm2: Profiles.area(loops_mm) }
          end
        end
        bay_rows.each do |row, idx|
          result[:bays] << plan_bay(row, idx, result[:repeats], pts, closed, frs, cum, total, corner_s, openings)
        end
        result
      end

      # Bays: the user's component fills every span between two posts
      # (the positions of another repeated row, or its own spacing), never
      # across a corner. fit 'stretch' = one copy stretched to the span,
      # 'tile' = whole copies at almost native width.
      def plan_bay(row, idx, repeats, pts, closed, frs, cum, total, corner_s, openings)
        ref = repeats.find { |r| r[:index] == row['bay_ref'].to_i && !row['bay_ref'].nil? && row['bay_ref'].to_s != '' }
        bounds = []
        if ref
          rb = Profiles.bbox(ref[:loops])
          half = (rb[3] - rb[1]) / 2.0
          ref[:items].map { |it| it[:s] }.uniq.each { |s| bounds << [s, half] }
        else
          own = row.merge('at_corners' => true)
          positions(total, closed, own, corner_s).each { |s| bounds << [s, 0.0] }
        end
        corner_s.each { |c| bounds << [c, 0.0] unless bounds.any? { |s, _| (s - c).abs < 1e-3 } }
        bounds << [total, 0.0] if closed
        bounds = bounds.sort_by(&:first)
        gap = (row['gap'] || 0).to_f * MM
        v0 = (row['v0'] || 0).to_f * MM
        h = row['scale'] ? (row['length'] || 1000).to_f * MM : row['comp_h'].to_f * MM
        h = 0.04 if h < 0.04
        w = [row['comp_w'].to_f * MM, 0.04].max
        items = []
        bounds.each_cons(2) do |(a, ha), (b, hb)|
          s0 = a + ha + gap
          s1 = b - hb - gap
          next if s1 - s0 < 0.1
          blocked = openings.any? { |o| s0 < o[:b] - 1e-6 && s1 > o[:a] + 1e-6 && v0 < o[:head] && v0 + h > o[:sill] }
          next if blocked
          n = row['fit'] == 'tile' ? [((s1 - s0) / w).round, 1].max : 1
          step = (s1 - s0) / n
          n.times do |k|
            a0 = s0 + step * k
            pt, seg, = PathOps.point_at(pts, closed, a0 + step / 2.0, cum)
            f = frs[[seg, frs.size - 1].min]
            start = Vec.sub(pt, Vec.mul(f[0], step / 2.0))
            items << { origin: start, frame: f, v0: v0, len: h, along: step, s: a0 + step / 2.0, s0: a0, s1: a0 + step }
          end
        end
        { row: row, index: idx, items: items }
      end

      def plan_repeat(row, idx, loops, pts, closed, frs, cum, total, corner_s, openings)
        bb = Profiles.bbox(loops)
        th = bb[3] - bb[1] # thickness along the path
        v0 = (row['v0'] || 0).to_f * MM
        len = if component?(row) && !row['scale']
                [row['comp_h'].to_f * MM, 0.04].max
              else
                [(row['length'] || 2400).to_f * MM, 0.04].max
              end
        list = positions(total, closed, row, corner_s).map { |s| [s, false] }
        if row['jambs']
          openings.select { |o| o[:jambs] }.each do |o|
            [o[:a] - th / 2.0, o[:b] + th / 2.0].each do |js|
              next if js < -1e-6 || js > total + 1e-6
              list.reject! { |s, j| !j && (s - js).abs < th }
              list << [js, true]
            end
          end
        end
        items = []
        list.sort_by(&:first).each do |s, jamb|
          pieces = [[v0, v0 + len]]
          unless jamb
            openings.each do |o|
              next unless s > o[:a] - th / 2.0 + 1e-6 && s < o[:b] + th / 2.0 - 1e-6
              pieces = subtract_range(pieces, o[:sill], o[:head])
            end
          end
          next if pieces.empty?
          pt, seg, = PathOps.point_at(pts, closed, s, cum)
          f = frs[[seg, frs.size - 1].min]
          pieces.each { |p0, p1| items << { origin: pt, frame: f, v0: p0, len: p1 - p0, s: s } }
        end
        { row: row, index: idx, loops: loops, items: items, area_mm2: Profiles.area(Profiles.to_mm(loops)) }
      end

      # Quantity entries for a plan (mm based).
      def quantities(plan)
        q = []
        plan[:layers].each do |l|
          r = l[:row]
          q << qty_entry(r, 'layer', l[:paths].size, l[:length] * 25.4, l[:area_mm2])
        end
        plan[:repeats].each do |rp|
          r = rp[:row]
          total = rp[:items].inject(0.0) { |s, it| s + it[:len] } * 25.4
          e = qty_entry(r, r['type'], rp[:items].size, total, component?(r) ? 0.0 : rp[:area_mm2])
          if component?(r)
            e['profile'] = "component:#{r['component']}"
            e['size'] = [r['comp_w'], r['comp_d'], r['comp_h']].map { |v| Profiles.fmt(v) }.join("\u00D7")
          end
          q << e
        end
        (plan[:bays] || []).each do |b|
          r = b[:row]
          along = b[:items].inject(0.0) { |s, it| s + it[:along] } * 25.4
          e = qty_entry(r, 'bay', b[:items].size, along, 0.0)
          e['profile'] = "component:#{r['component']}"
          e['size'] = [r['comp_w'], r['comp_d'], r['comp_h']].map { |v| Profiles.fmt(v) }.join("\u00D7")
          q << e
        end
        q
      end

      # Front elevation of an assembly on a straight path (for thumbnails and
      # the panel preview). Returns [x0, y0, x1, y1, type, material, hidden, depth]
      # rectangles in mm, sorted back to front.
      def elevation(spec, length_mm = 2400.0)
        prep = Sweep.prepare([[0.0, 0.0, 0.0], [length_mm * MM, 0.0, 0.0]], false, nil)
        pl = plan(prep, spec)
        rects = []
        pl[:layers].each do |l|
          bb = Profiles.bbox(l[:loops])
          l[:paths].each do |p, _|
            xs = p.map { |q| q[0] }
            rects << [xs.min * 25.4, bb[1] * 25.4, xs.max * 25.4, bb[3] * 25.4, 'layer',
                      l[:row]['material'].to_s, l[:row]['visible'] == false, (bb[0] + bb[2]) * 12.7, l[:index], false]
          end
        end
        pl[:repeats].each do |rp|
          bb = Profiles.bbox(rp[:loops])
          rp[:items].each do |it|
            rects << [(it[:s] + bb[1]) * 25.4, it[:v0] * 25.4, (it[:s] + bb[3]) * 25.4, (it[:v0] + it[:len]) * 25.4,
                      rp[:row]['type'], rp[:row]['material'].to_s, rp[:row]['visible'] == false, (bb[0] + bb[2]) * 12.7,
                      rp[:index], rp[:row]['flip'] ? true : false]
          end
        end
        (pl[:bays] || []).each do |b|
          depth = (b[:row]['offset_u'] || 0).to_f
          b[:items].each do |it|
            rects << [it[:s0] * 25.4, it[:v0] * 25.4, it[:s1] * 25.4, (it[:v0] + it[:len]) * 25.4, 'bay',
                      b[:row]['material'].to_s, b[:row]['visible'] == false, depth, b[:index], b[:row]['flip'] ? true : false]
          end
        end
        rects.sort_by { |r| r[7] }.map { |r| r[0, 4].map { |v| v.round(1) } + r[4, 3] + [r[8], r[9]] }
      end

      def qty_entry(row, type, count, length_mm, area_mm2)
        spec = row_profile_spec(row)
        {
          'name' => row['name'].to_s, 'type' => type, 'profile' => spec['profile'],
          'size' => Profiles.size_label(spec), 'count' => count,
          'length_mm' => length_mm.round(1), 'area_mm2' => area_mm2.round(2),
          'volume_mm3' => (length_mm * area_mm2).round(0), 'material' => row['material'].to_s
        }
      end
    end

    module Profiles
      def self.to_mm(loops)
        loops.map { |l| l.map { |q| [q[0] * 25.4, q[1] * 25.4] } }
      end
    end
  end
end
