# frozen_string_literal: true

require 'json'

module MEPStudio
  # Clash detection
  #   * MEP  vs MEP          (duct / pipe / tray / equipment, any discipline)
  #   * MEP  vs Arch/Struct  (every visible face of non-MEP geometry:
  #                           beams, columns, walls, slabs, imported models)
  # Hard clash  = bodies intersect.
  # Soft clash  = bodies are closer than the clearance (insulation,
  #               maintenance space ...).
  # Pieces that are meant to touch (duct leaving a fan coil, branch pipe
  # tapping into its main, sprinkler drop + head) are recognised as
  # connections and ignored.
  module Clash
    RUN_TYPES = %w[duct pipe tray].freeze
    EQUIP_TYPES = %w[fcu terminal sprinkler light].freeze
    # Items that are supposed to sit in / pass through the ceiling.
    ARCH_EXEMPT = %w[terminal light sprinkler].freeze

    Item = Struct.new(:id, :ent, :root, :name, :type, :system, :size, :parts, :ends, :aabb, :layer)
    # part: {obb:, aabb:, seg: [p0,p1] or nil, r: radius or nil}

    @results = []
    @dialog = nil

    module_function

    def results
      @results
    end

    # ------------------------------------------------------------ dialog
    def run
      o = Settings['clash']
      r = Util.ask('Clash detection / تشخیص تداخل', [
                     ['Clearance for soft clash mm / فاصله مجاز', o['clearance'].to_f],
                     ['Check MEP vs MEP / تاسیسات با تاسیسات', Util.yes?(o['check_mep']) ? 'Yes' : 'No', Util.bool_list],
                     ['Check MEP vs Arch/Struct / تاسیسات با سازه و معماری', Util.yes?(o['check_arch']) ? 'Yes' : 'No', Util.bool_list],
                     ['Only visible / فقط موارد قابل مشاهده', Util.yes?(o['only_visible']) ? 'Yes' : 'No', Util.bool_list],
                     ['Ignore tags (comma separated) / تگ‌های نادیده', o['ignore_tags'].to_s],
                     ['Place markers in model / علامت‌گذاری در مدل', Util.yes?(o['markers']) ? 'Yes' : 'No', Util.bool_list]
                   ])
      return unless r
      opts = {
        'clearance' => r[0], 'check_mep' => Util.yes?(r[1]), 'check_arch' => Util.yes?(r[2]),
        'only_visible' => Util.yes?(r[3]), 'ignore_tags' => r[4], 'markers' => Util.yes?(r[5])
      }
      Settings.set('clash', opts)
      t0 = Time.now
      Sketchup.set_status_text('MEP Studio: detecting clashes ...')
      @results = detect(opts)
      dt = Time.now - t0
      if opts['markers']
        Util.operation('MEP: clash markers') { place_markers(@results) }
      end
      show_dialog(dt)
    rescue StandardError => e
      Util.ui_error(e)
    end

    # ------------------------------------------------------------ collect
    def detect(opts)
      m = Util.model
      ignore = opts['ignore_tags'].to_s.split(',').map(&:strip).reject(&:empty?)
      ignore << 'MEP-CLASH'
      ctx = { opts: opts, ignore: ignore, items: [], tris: [], tri_cache: {}, next_id: 0 }
      collect(m.entities, Geom::Transformation.new, ctx, nil, nil)
      clearance = Util.mm(opts['clearance'])
      shrink = Util.mm(1.0)
      found = {}
      if opts['check_mep']
        mep_vs_mep(ctx[:items], clearance, shrink, found)
      end
      if opts['check_arch'] && !ctx[:tris].empty?
        mep_vs_arch(ctx[:items], ctx[:tris], clearance, shrink, found)
      end
      found.values.sort_by { |c| [c[:hard] ? 0 : 1, c[:a].name] }.each_with_index.map do |c, i|
        c.merge(no: i + 1)
      end
    end

    def visible?(ent, ctx)
      return false if ctx[:ignore].include?(ent.layer.name)
      return true unless ctx[:opts]['only_visible']
      !ent.hidden? && ent.layer.visible?
    end

    def collect(entities, tr, ctx, root, owner)
      entities.each do |ent|
        next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Face)
        next unless visible?(ent, ctx)
        if ent.is_a?(Sketchup::Face)
          add_face(ent, tr, ctx, root, owner)
          next
        end
        t = tr * ent.transformation
        r = root || ent
        type = Util.mep_type(ent)
        if RUN_TYPES.include?(type)
          add_run(ent, t, ctx, r)
        elsif EQUIP_TYPES.include?(type)
          add_equipment(ent, t, ctx, r)
        else
          defn = ent.respond_to?(:definition) ? ent.definition : ent.entities.parent
          # MEP containers (sprinkler zones ...) are traversed, but their loose
          # faces are never treated as architecture.
          own = ent.get_attribute(DICT, 'container') ? :mep : ent
          collect(defn.entities, t, ctx, r, own)
        end
      end
    end

    def label_for(ent)
      n = ent.name.to_s
      n = ent.definition.name if n.empty? && ent.respond_to?(:definition)
      n = ent.typename if n.empty?
      n
    end

    def add_run(ent, tr, ctx, root)
      a = Util.attrs(ent)
      pts = RunBuilder.path_from(ent, 'centerline')
      pts = RunBuilder.path_from(ent) if pts.size < 2
      return if pts.size < 2
      m = tr.to_a
      wp = pts.map { |p| xform(m, p) }
      ins = Util.mm(a['insulation'].to_f)
      round = a['shape'] == 'round'
      if round
        w = h = Util.mm(a['diameter'].to_f) + 2 * ins
      else
        w = Util.mm(a['width'].to_f) + (a['shape'] == 'tray' ? 0 : 2 * ins)
        h = Util.mm(a['height'].to_f) + (a['shape'] == 'tray' ? 0 : 2 * ins)
      end
      parts = []
      (0...wp.size - 1).each do |i|
        p0 = wp[i]
        p1 = wp[i + 1]
        next if Geo.dist(p0, p1) < 1.0e-4
        ob = Geo.segment_obb(p0, p1, w, h)
        parts << { obb: ob, aabb: Geo.obb_aabb(ob), seg: [p0, p1], r: round ? w / 2.0 : nil }
      end
      return if parts.empty?
      push_item(ctx, ent, root, a['type'], a['system'], a['size'], parts, [wp.first, wp.last])
    end

    def add_equipment(ent, tr, ctx, root)
      a = Util.attrs(ent)
      bb = ent.definition.bounds
      m = tr.to_a
      c = xform(m, Util.pt_a(bb.center))
      axes = [[1, 0, 0], [0, 1, 0], [0, 0, 1]].map { |v| Geo.sub(xform(m, v), xform(m, [0, 0, 0])) }
      scales = axes.map { |v| Geo.len(v) }
      half = [bb.width, bb.height, bb.depth].each_with_index.map { |d, i| d / 2.0 * scales[i] }
      ob = Geo.obb(c, axes, half)
      parts = [{ obb: ob, aabb: Geo.obb_aabb(ob), seg: nil, r: nil }]
      sys = a['system'] || 'EQ'
      push_item(ctx, ent, root, a['type'], sys, a['model'] || ent.definition.name, parts, [])
    end

    def push_item(ctx, ent, root, type, sys, size, parts, ends)
      ctx[:next_id] += 1
      aabb = parts.map { |p| p[:aabb] }.reduce { |x, y| Geo.aabb_union(x, y) }
      ctx[:items] << Item.new(ctx[:next_id], ent, root, label_for(ent), type, sys, size.to_s, parts, ends, aabb, ent.layer.name)
    end

    def add_face(face, tr, ctx, root, owner)
      return if owner == :mep
      local = ctx[:tri_cache][face] ||= begin
        mesh = face.mesh(0)
        pts = mesh.points.map { |p| Util.pt_a(p) }
        mesh.polygons.map { |poly| poly.map { |i| pts[i.abs - 1] } }.select { |t| t.size == 3 }
      end
      m = tr.to_a
      name = owner.nil? ? 'Loose geometry' : label_for(owner)
      layer = owner.nil? ? face.layer.name : owner.layer.name
      local.each do |t|
        wt = t.map { |p| xform(m, p) }
        lo = (0..2).map { |k| wt.map { |p| p[k] }.min }
        hi = (0..2).map { |k| wt.map { |p| p[k] }.max }
        ctx[:tris] << { t: wt, aabb: [lo, hi], owner: owner, name: name, layer: layer, root: root || face }
      end
    end

    def xform(m, p)
      x, y, z = p
      w = m[3] * x + m[7] * y + m[11] * z + m[15]
      w = 1.0 if w.abs < 1.0e-12
      [(m[0] * x + m[4] * y + m[8] * z + m[12]) / w,
       (m[1] * x + m[5] * y + m[9] * z + m[13]) / w,
       (m[2] * x + m[6] * y + m[10] * z + m[14]) / w]
    end

    # ------------------------------------------------------------ spatial hash
    CELL = 1000.0 / 25.4

    def cells(aabb, pad = 0.0)
      lo = aabb[0].map { |v| ((v - pad) / CELL).floor }
      hi = aabb[1].map { |v| ((v + pad) / CELL).floor }
      res = []
      (lo[0]..hi[0]).each do |i|
        (lo[1]..hi[1]).each do |j|
          (lo[2]..hi[2]).each { |k| res << [i, j, k] }
        end
      end
      res
    end

    def build_hash(objs, pad)
      h = Hash.new { |hh, k| hh[k] = [] }
      objs.each_with_index do |o, idx|
        cs = cells(o[:aabb], pad)
        next if cs.size > 200_000
        cs.each { |c| h[c] << idx }
      end
      h
    end

    # ------------------------------------------------------------ checks
    def connected?(a, b)
      tol = Util.mm(10)
      a_eq = EQUIP_TYPES.include?(a.type)
      b_eq = EQUIP_TYPES.include?(b.type)
      return false if a_eq && b_eq
      if a_eq || b_eq
        eq, run = a_eq ? [a, b] : [b, a]
        return run.ends.any? { |p| eq.parts.any? { |pt| Geo.point_in_obb?(p, pt[:obb], tol) } }
      end
      return false unless a.system == b.system
      a.ends.any? { |p| b.parts.any? { |pt| Geo.point_in_obb?(p, pt[:obb], tol) } } ||
        b.ends.any? { |p| a.parts.any? { |pt| Geo.point_in_obb?(p, pt[:obb], tol) } }
    end

    # :hard, :soft or nil
    def part_clash(pa, pb, clearance, shrink)
      if pa[:r] && pb[:r]
        d, = Geo.seg_seg_dist(pa[:seg][0], pa[:seg][1], pb[:seg][0], pb[:seg][1])
        gap = d - pa[:r] - pb[:r]
        return :hard if gap < -shrink
        return :soft if gap < clearance
        return nil
      end
      return :hard if Geo.obb_overlap?(Geo.obb_inflate(pa[:obb], -shrink), Geo.obb_inflate(pb[:obb], -shrink))
      return :soft if clearance > 0 && Geo.obb_overlap?(Geo.obb_inflate(pa[:obb], clearance / 2.0), Geo.obb_inflate(pb[:obb], clearance / 2.0))
      nil
    end

    def mep_vs_mep(items, clearance, shrink, found)
      parts = []
      items.each { |itm| itm.parts.each { |p| parts << { item: itm, part: p, aabb: p[:aabb] } } }
      hash = build_hash(parts, clearance)
      checked = {}
      hash.each_value do |idxs|
        next if idxs.size < 2
        idxs.each_with_index do |i, n|
          ((n + 1)...idxs.size).each do |m|
            j = idxs[m]
            a = parts[i]
            b = parts[j]
            next if a[:item].id == b[:item].id
            key = i < j ? [i, j] : [j, i]
            next if checked[key]
            checked[key] = true
            ia = a[:item]
            ib = b[:item]
            pair = ia.id < ib.id ? [ia.id, ib.id] : [ib.id, ia.id]
            next if found[pair] && found[pair][:hard]
            pad = [[clearance, 0].max, 0].max
            grown_a = [Geo.sub(a[:aabb][0], [pad] * 3), Geo.add(a[:aabb][1], [pad] * 3)]
            next unless Geo.aabb_overlap?(grown_a, b[:aabb])
            kind = part_clash(a[:part], b[:part], clearance, shrink)
            next unless kind
            conn_key = [:conn] + pair
            checked[conn_key] = connected?(ia, ib) if checked[conn_key].nil?
            next if checked[conn_key]
            loc = Geo.aabb_intersection_center(grown_a, b[:aabb])
            record(found, pair, ia, ib_info(ib), kind, loc, 'MEP')
          end
        end
      end
    end

    def ib_info(item)
      { name: item.name, system: item.system, size: item.size, type: item.type, layer: item.layer, ent: item.ent, root: item.root }
    end

    def mep_vs_arch(items, tris, clearance, shrink, found)
      hash = build_hash(tris, clearance)
      items.each do |item|
        next if ARCH_EXEMPT.include?(item.type)
        drops_exempt = item.system == 'SPR'
        item.parts.each do |p|
          if drops_exempt && p[:seg]
            d = Geo.norm(Geo.sub(p[:seg][1], p[:seg][0]))
            next if d[2].abs > 0.9 # vertical sprinkler drop through the ceiling
          end
          cand = {}
          cells(p[:aabb], clearance).each { |c| (hash[c] if hash.key?(c))&.each { |ti| cand[ti] = true } }
          next if cand.empty?
          hard_box = Geo.obb_inflate(p[:obb], -shrink)
          soft_box = clearance > 0 ? Geo.obb_inflate(p[:obb], clearance) : nil
          cand.each_key do |ti|
            tri = tris[ti]
            okey = tri[:owner].nil? ? :loose : tri[:owner]
            pair = [item.id, okey.is_a?(Symbol) ? okey : okey.object_id]
            next if found[pair] && found[pair][:hard]
            grown = [Geo.sub(p[:aabb][0], [clearance] * 3), Geo.add(p[:aabb][1], [clearance] * 3)]
            next unless Geo.aabb_overlap?(grown, tri[:aabb])
            kind = if Geo.tri_obb_overlap?(tri[:t], hard_box)
                     :hard
                   elsif soft_box && Geo.tri_obb_overlap?(tri[:t], soft_box)
                     :soft
                   end
            next unless kind
            loc = Geo.aabb_intersection_center(grown, tri[:aabb])
            info = { name: tri[:name], system: 'ARCH', size: '', type: 'arch', layer: tri[:layer],
                     ent: tri[:owner].is_a?(Sketchup::Entity) ? tri[:owner] : nil, root: tri[:root] }
            record(found, pair, item, info, kind, loc, 'Arch/Struct')
          end
        end
      end
    end

    def record(found, pair, a, binfo, kind, loc, vs)
      prev = found[pair]
      return if prev && (prev[:hard] || kind == :soft)
      found[pair] = { a: a, b: binfo, hard: kind == :hard, loc: loc, vs: vs }
    end

    # ------------------------------------------------------------ markers
    def place_markers(res)
      m = Util.model
      clear_markers
      return if res.empty?
      tag = Util.tag('MEP-CLASH')
      grp = m.entities.add_group
      grp.name = 'MEP Clash Markers'
      grp.layer = tag
      Util.set_attrs(grp, 'container' => 'clash_markers')
      red = Util.plain_material('MEP_ClashHard', [255, 0, 0], 0.6)
      yel = Util.plain_material('MEP_ClashSoft', [255, 190, 0], 0.6)
      s = Util.mm(75)
      res.each do |c|
        g = grp.entities.add_group
        e = g.entities
        p = c[:loc]
        pts = [[-s, -s], [s, -s], [s, s], [-s, s]].map { |x, y| Geom::Point3d.new(p[0] + x, p[1] + y, p[2] - s) }
        f = e.add_face(pts)
        f.pushpull(f.normal.z < 0 ? -2 * s : 2 * s)
        g.material = c[:hard] ? red : yel
        grp.entities.add_text("C#{c[:no]}", Util.a_pt(p), Geom::Vector3d.new(Util.mm(300), Util.mm(300), Util.mm(300)))
      end
    end

    def clear_markers
      m = Util.model
      old = m.entities.select { |e| e.is_a?(Sketchup::Group) && e.get_attribute(DICT, 'container') == 'clash_markers' }
      m.entities.erase_entities(old) unless old.empty?
    end

    # ------------------------------------------------------------ report
    def rows
      @results.map do |c|
        a = c[:a]
        b = c[:b]
        {
          'no' => c[:no], 'kind' => c[:hard] ? 'Hard' : 'Soft', 'vs' => c[:vs],
          'a' => "#{a.name} [#{a.system}] #{a.size}", 'a_layer' => a.layer,
          'b' => "#{b[:name]} #{b[:system] == 'ARCH' ? '' : "[#{b[:system]}] #{b[:size]}"}".strip, 'b_layer' => b[:layer],
          'x' => Util.to_mm(c[:loc][0]).round, 'y' => Util.to_mm(c[:loc][1]).round, 'z' => Util.to_mm(c[:loc][2]).round
        }
      end
    end

    def show_dialog(seconds)
      @dialog&.close
      dlg = UI::HtmlDialog.new(dialog_title: 'MEP Studio - Clash Report', preferences_key: 'MEPStudio_clash',
                               width: 900, height: 560, style: UI::HtmlDialog::STYLE_DIALOG)
      data = { rows: rows, seconds: seconds.round(2) }
      html = File.read(File.join(PLUGIN_DIR, 'ui', 'clash.html'), encoding: 'UTF-8')
      json = JSON.generate(data)
      dlg.set_html(html.sub('/*DATA*/null') { json })
      dlg.add_action_callback('zoom') { |_ctx, n| zoom_to(n.to_i) }
      dlg.add_action_callback('export') { |_ctx| export_csv }
      dlg.add_action_callback('clear') { |_ctx| Util.operation('MEP: clear clash markers') { clear_markers } }
      dlg.add_action_callback('rerun') { |_ctx| UI.start_timer(0.1, false) { run } }
      dlg.show
      @dialog = dlg
    end

    def zoom_to(no)
      c = @results.find { |r| r[:no] == no }
      return unless c
      m = Util.model
      p = Util.a_pt(c[:loc])
      d = Util.mm(2500)
      eye = Geom::Point3d.new(p.x - d, p.y - d * 1.3, p.z + d * 0.8)
      m.active_view.camera = Sketchup::Camera.new(eye, p, Z_AXIS)
      sel = m.selection
      sel.clear
      [c[:a].root, c[:b][:root]].compact.each do |e|
        sel.add(e) if e.valid? && e.parent == m.active_entities.parent
      rescue StandardError
        nil
      end
    end

    def export_csv
      path = UI.savepanel('Export clash report', '', 'clash_report.csv')
      return unless path
      path += '.csv' unless path.downcase.end_with?('.csv')
      head = %w[No Type Against ElementA TagA ElementB TagB X_mm Y_mm Z_mm]
      lines = [head.join(',')]
      rows.each do |r|
        lines << [r['no'], r['kind'], r['vs'], r['a'], r['a_layer'], r['b'], r['b_layer'], r['x'], r['y'], r['z']]
                 .map { |v| csv_cell(v) }.join(',')
      end
      File.write(path, "﻿" + lines.join("\r\n"), encoding: 'UTF-8')
      UI.messagebox("Saved: #{path}")
    end

    def csv_cell(v)
      s = v.to_s
      s =~ /[",\r\n]/ ? "\"#{s.gsub('"', '""')}\"" : s
    end
  end
end
