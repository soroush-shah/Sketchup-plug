# frozen_string_literal: true

require 'json'

module MEPStudio
  # Commands that do not need an interactive tool.
  module Commands
    module_function

    # ---------------------------------------------- runs from selected edges
    # Each chain of connected edges between end points / junctions becomes
    # one run, so a whole branched network can be converted at once.
    def runs_from_edges(kind)
      edges = Util.model.selection.grep(Sketchup::Edge)
      if edges.empty?
        UI.messagebox("Select edges (lines) that describe the route first.\nابتدا خطوط مسیر را انتخاب کنید.")
        return
      end
      section = kind == 'tray' ? 'tray' : kind
      o = Settings[section].dup
      o['kind'] = kind
      fields = []
      if kind == 'duct'
        fields = [['System', o['system'], Catalog::DUCT_SYSTEMS], ['Shape', o['shape'], %w[rect round]],
                  ['Width mm', o['width'].to_f], ['Height mm', o['height'].to_f], ['Diameter mm', o['diameter'].to_f]]
      elsif kind == 'pipe'
        fields = [['System', o['system'], Catalog::PIPE_SYSTEMS], ['DN', o['dn'].to_i.to_s, Catalog::PIPE_OD.keys.map(&:to_s)]]
      else
        fields = [['Width mm', o['width'].to_f], ['Height mm', o['height'].to_f]]
      end
      fields += [['Lines are / خطوط معرف', 'centerline', %w[centerline bottom top]],
                 ['Offset above lines mm / فاصله از خطوط', 0.0],
                 ['Elbow radius factor (0 = mitred)', o['elbow_radius'].to_f],
                 ['Delete source edges / حذف خطوط', 'No', Util.bool_list]]
      r = Util.ask("#{kind.capitalize} from edges / ساخت از روی خطوط", fields)
      return unless r
      if kind == 'duct'
        o['system'], o['shape'], o['width'], o['height'], o['diameter'] = r.shift(5)
      elsif kind == 'pipe'
        o['system'], dn = r.shift(2)
        o['dn'] = dn.to_i
      else
        o['width'], o['height'] = r.shift(2)
        o['system'] = 'TRAY'
        o['shape'] = 'rect'
      end
      ref, offset, o['elbow_radius'], del = r
      h = if kind == 'pipe'
            Catalog::PIPE_OD[o['dn'].to_i].to_f
          elsif o['shape'] == 'round'
            o['diameter'].to_f
          else
            o['height'].to_f
          end
      dz = offset.to_f + (ref == 'bottom' ? h / 2.0 : (ref == 'top' ? -h / 2.0 : 0.0))
      chains = chains_from(edges)
      count = 0
      Util.operation("MEP: #{kind} from edges") do
        ents = Util.model.active_entities
        chains.each do |chain|
          pts = chain.map { |p| [p[0], p[1], p[2] + Util.mm(dz)] }
          RunBuilder.build(ents, pts, o)
          count += 1
        end
        ents.erase_entities(edges.select(&:valid?)) if Util.yes?(del)
      end
      Settings.set(section, o.reject { |k, _| k == 'kind' })
      Sketchup.set_status_text("MEP Studio: #{count} #{kind} run(s) created")
    end

    # Split an edge graph into polylines between nodes of degree != 2.
    def chains_from(edges)
      adj = Hash.new { |h, k| h[k] = [] }
      edges.each do |e|
        adj[e.start] << e
        adj[e.end] << e
      end
      used = {}
      chains = []
      nodes = adj.keys.select { |v| adj[v].size != 2 }
      walk = lambda do |start, edge|
        pts = [Util.pt_a(start.position)]
        v = start
        e = edge
        loop do
          used[e] = true
          v = e.other_vertex(v)
          pts << Util.pt_a(v.position)
          break if adj[v].size != 2
          e = adj[v].find { |x| !used[x] }
          break unless e
        end
        pts
      end
      nodes.each do |n|
        adj[n].each { |e| chains << walk.call(n, e) unless used[e] }
      end
      # closed loops
      edges.each do |e|
        chains << walk.call(e.start, e) unless used[e]
      end
      chains
    end

    # ---------------------------------------------- edit / resize selected
    def edit_selected
      runs = Util.model.selection.select { |e| e.is_a?(Sketchup::Group) && Clash::RUN_TYPES.include?(Util.mep_type(e)) }
      if runs.empty?
        UI.messagebox("Select one or more MEP Studio ducts / pipes / trays.\nیک یا چند داکت/لوله را انتخاب کنید.")
        return
      end
      a = Util.attrs(runs.first)
      kind = a['type']
      fields = []
      if kind == 'duct'
        fields = [['System', a['system'], Catalog::DUCT_SYSTEMS], ['Shape', a['shape'], %w[rect round]],
                  ['Width mm', a['width'].to_f], ['Height mm', a['height'].to_f], ['Diameter mm', a['diameter'].to_f],
                  ['Insulation mm', a['insulation'].to_f], ['Show insulation', Util.yes?(a['show_insulation']) ? 'Yes' : 'No', Util.bool_list]]
      elsif kind == 'pipe'
        fields = [['System', a['system'], Catalog::PIPE_SYSTEMS], ['DN', a['dn'].to_i.to_s, Catalog::PIPE_OD.keys.map(&:to_s)],
                  ['Insulation mm', a['insulation'].to_f]]
      else
        fields = [['Width mm', a['width'].to_f], ['Height mm', a['height'].to_f]]
      end
      fields << ['Elbow radius factor', a['elbow_radius'].to_f]
      r = Util.ask("Edit #{runs.size} #{kind} run(s) / ویرایش", fields)
      return unless r
      n = {}
      if kind == 'duct'
        n['system'], n['shape'], n['width'], n['height'], n['diameter'], n['insulation'], si = r.shift(7)
        n['show_insulation'] = Util.yes?(si)
      elsif kind == 'pipe'
        n['system'], dn, n['insulation'] = r.shift(3)
        n['dn'] = dn.to_i
      else
        n['width'], n['height'] = r.shift(2)
      end
      n['elbow_radius'] = r.shift
      Util.operation('MEP: edit runs') do
        sel = Util.model.selection
        sel.clear
        runs.select { |g| Util.mep_type(g) == kind }.each { |g| sel.add(RunBuilder.rebuild(g, n)) }
      end
    end

    # ---------------------------------------------- bill of quantities
    def boq
      m = Util.model
      rows = Hash.new { |h, k| h[k] = { 'qty' => 0.0, 'count' => 0, 'area' => 0.0 } }
      walk(m.entities, Geom::Transformation.new) do |ent|
        a = Util.attrs(ent)
        case a['type']
        when 'duct', 'pipe', 'tray'
          len = a['length_mm'].to_f / 1000.0
          key = [a['type'], a['system'], a['size']]
          rows[key]['qty'] += len
          rows[key]['count'] += 1
          if a['type'] == 'duct'
            per = a['shape'] == 'round' ? Math::PI * a['diameter'].to_f : 2 * (a['width'].to_f + a['height'].to_f)
            rows[key]['area'] += per / 1000.0 * len
          end
        when 'fcu', 'terminal', 'sprinkler', 'light'
          key = [a['type'], a['system'], a['model'] || ent.definition.name]
          rows[key]['count'] += 1
        end
      end
      if rows.empty?
        UI.messagebox('No MEP Studio elements found in the model.')
        return
      end
      list = rows.sort_by { |k, _| k.map(&:to_s) }.map do |(type, sys, size), v|
        unit = %w[duct pipe tray].include?(type) ? 'm' : 'pcs'
        qty = unit == 'm' ? v['qty'].round(2) : v['count']
        { 'type' => type, 'system' => sys, 'label' => Catalog.system_label(sys), 'size' => size, 'qty' => qty,
          'unit' => unit, 'area' => v['area'].round(2), 'pieces' => v['count'] }
      end
      show_boq(list)
    end

    def walk(entities, tr, &blk)
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        if Util.mep_type(e) && !e.get_attribute(DICT, 'container')
          blk.call(e)
        else
          defn = e.respond_to?(:definition) ? e.definition : e.entities.parent
          walk(defn.entities, tr, &blk)
        end
      end
    end

    def show_boq(list)
      dlg = UI::HtmlDialog.new(dialog_title: 'MEP Studio - Bill of Quantities', preferences_key: 'MEPStudio_boq',
                               width: 820, height: 560, style: UI::HtmlDialog::STYLE_DIALOG)
      html = File.read(File.join(PLUGIN_DIR, 'ui', 'boq.html'), encoding: 'UTF-8')
      json = JSON.generate(list)
      dlg.set_html(html.sub('/*DATA*/null') { json })
      dlg.add_action_callback('export') do |_c|
        path = UI.savepanel('Export BOQ', '', 'mep_boq.csv')
        if path
          path += '.csv' unless path.downcase.end_with?('.csv')
          lines = ['Type,System,Description,Size,Quantity,Unit,Sheet metal area m2,Pieces']
          list.each do |r|
            lines << [r['type'], r['system'], r['label'], r['size'], r['qty'], r['unit'], r['area'], r['pieces']]
                     .map { |v| Clash.csv_cell(v) }.join(',')
          end
          File.write(path, "﻿" + lines.join("\r\n"), encoding: 'UTF-8')
          UI.messagebox("Saved: #{path}")
        end
      end
      dlg.show
      @boq = dlg
    end

    # ---------------------------------------------- visibility by discipline
    def isolate(discipline)
      m = Util.model
      Util.operation('MEP: discipline visibility') do
        Catalog::SYSTEMS.each_value do |_label, _rgb, tag, disc|
          layer = m.layers[tag]
          next unless layer
          layer.visible = discipline == 'all' || disc == discipline
        end
      end
    end

    # ---------------------------------------------- settings
    def settings
      d = Settings['duct']
      p = Settings['pipe']
      f = Settings['fcu']
      r = Util.ask('MEP Studio defaults / پیش‌فرض‌ها', [
                     ['Duct system', d['system'], Catalog::DUCT_SYSTEMS],
                     ['Duct width mm', d['width'].to_f], ['Duct height mm', d['height'].to_f],
                     ['Duct elevation mm (bottom)', d['elevation'].to_f],
                     ['Duct insulation mm', d['insulation'].to_f],
                     ['Duct elbow radius factor', d['elbow_radius'].to_f],
                     ['Pipe system', p['system'], Catalog::PIPE_SYSTEMS],
                     ['Pipe DN', p['dn'].to_i.to_s, Catalog::PIPE_OD.keys.map(&:to_s)],
                     ['Pipe elevation mm (center)', p['elevation'].to_f],
                     ['Fan coil model', f['model'], Settings.fcu_catalog.keys],
                     ['Fan coil bottom elevation mm', f['bottom_elevation'].to_f],
                     ['Fan coil gap to slab mm', f['gap_to_slab'].to_f],
                     ['Reset everything to factory defaults', 'No', Util.bool_list]
                   ])
      return unless r
      if Util.yes?(r[12])
        Settings.reset!
        UI.messagebox('Defaults restored.')
        return
      end
      Settings.set('duct', 'system' => r[0], 'width' => r[1], 'height' => r[2], 'elevation' => r[3], 'elev_ref' => 'bottom',
                           'insulation' => r[4], 'elbow_radius' => r[5])
      Settings.set('pipe', 'system' => r[6], 'dn' => r[7].to_i, 'elevation' => r[8], 'elev_ref' => 'center')
      Settings.set('fcu', 'model' => r[9], 'bottom_elevation' => r[10], 'gap_to_slab' => r[11])
    end

    # Add / override a fan coil model in the catalogue.
    def add_fcu_model
      base = Settings.fcu_catalog[Settings['fcu']['model']] || Catalog::FCU.values.first
      r = Util.ask('New fan coil model / افزودن مدل فن کویل', [
                     ['Name / نام', 'My FCU-500'],
                     ['Type', base['type'], %w[ducted cassette exposed floor]],
                     ['CFM', base['cfm'].to_f],
                     ['Length L mm / طول', base['L'].to_f], ['Depth D mm / عمق', base['D'].to_f], ['Height H mm / ارتفاع', base['H'].to_f],
                     ['Supply outlet width mm', (base['out'] || [600, 120])[0].to_f], ['Supply outlet height mm', (base['out'] || [600, 120])[1].to_f],
                     ['Return width mm (0 = none)', (base['ret'] || [0, 0])[0].to_f], ['Return height mm', (base['ret'] || [0, 0])[1].to_f],
                     ['Coil pipe DN', base['pipe'].to_i.to_s, Catalog::PIPE_OD.keys.map(&:to_s)],
                     ['Drain DN', base['drain'].to_i.to_s, Catalog::PIPE_OD.keys.map(&:to_s)]
                   ])
      return unless r
      spec = { 'type' => r[1], 'cfm' => r[2].to_i, 'L' => r[3], 'D' => r[4], 'H' => r[5], 'out' => [r[6], r[7]],
               'pipe' => r[10].to_i, 'drain' => r[11].to_i }
      spec['ret'] = [r[8], r[9]] if r[8].to_f > 0
      spec['panel'] = r[3] + 45 if r[1] == 'cassette'
      cat = Settings['fcu_catalog'] || {}
      cat[r[0]] = spec
      Settings.data['fcu_catalog'] = cat
      Settings.set('fcu', 'model' => r[0])
      UI.messagebox("Model \"#{r[0]}\" saved. / مدل ذخیره شد.")
    end
  end
end
