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

      def row_profile_spec(row)
        {
          'profile' => row['profile'] || 'rect', 'params' => row['params'] || {},
          'custom_loops' => row['custom_loops'],
          'anchor' => row['anchor'] || (row['type'] == 'repeat' ? 'mc' : 'bc'),
          'rotation' => row['rotation'] || 0, 'flip' => row['flip'] ? true : false,
          'offset_u' => row['offset_u'] || 0, 'offset_v' => row['type'] == 'repeat' ? 0 : (row['offset_v'] || 0)
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
        result = { layers: [], repeats: [], total: total }
        (spec['rows'] || []).each_with_index do |row0, idx|
          row = apply_global_flip(row0, flip)
          loops_mm = Profiles.placed_loops(row_profile_spec(row))
          next if loops_mm.empty?
          loops = Profiles.to_inches(loops_mm)
          if row['type'] == 'repeat'
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
        result
      end

      def plan_repeat(row, idx, loops, pts, closed, frs, cum, total, corner_s, openings)
        bb = Profiles.bbox(loops)
        th = bb[3] - bb[1] # thickness along the path
        v0 = (row['v0'] || 0).to_f * MM
        len = [(row['length'] || 2400).to_f * MM, 0.04].max
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
          q << qty_entry(r, 'repeat', rp[:items].size, total, rp[:area_mm2])
        end
        q
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
