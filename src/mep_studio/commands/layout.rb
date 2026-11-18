# frozen_string_literal: true

module MEPStudio
  # Automatic layouts inside a selected horizontal face (room ceiling or floor):
  #  * sprinkler heads by hazard class + branch lines, drops and cross main
  #    sized with the pipe schedule method
  #  * light fixtures / diffusers on a regular grid
  module Layout
    module_function

    def selected_faces
      sel = Util.model.selection.grep(Sketchup::Face)
      faces = sel.select { |f| f.normal.z.abs > 0.99 }
      if faces.empty?
        UI.messagebox("Select one or more horizontal faces first (room floor or ceiling).\n" \
                      'ابتدا یک یا چند سطح افقی (کف یا سقف اتاق) را انتخاب کنید.')
        return nil
      end
      faces
    end

    # Ceiling elevation (active coords) for a face.
    def ceiling_z(face, ceiling_height_mm)
      z = face.vertices.first.position.z
      n = face.normal.transform(Util.edit_tr)
      n.z < 0 ? z : z + Util.mm(ceiling_height_mm)
    end

    def grid_points(face, spacing_mm, area_m2, wall_min_mm, angle_aligned = true)
      bb = face.bounds
      xmin = bb.min.x
      ymin = bb.min.y
      l = bb.width
      w = bb.height
      s = Util.mm(spacing_mm)
      a = area_m2 ? area_m2 * 1_000_000.0 * Util::MM * Util::MM : nil
      nx, ny, dx, dy = Geo.grid_counts(l, w, s, a)
      z = face.vertices.first.position.z
      rows = []
      ny.times do |j|
        row = []
        nx.times do |i|
          x = xmin + dx * (i + 0.5)
          y = ymin + dy * (j + 0.5)
          pt = Geom::Point3d.new(x, y, z)
          cls = face.classify_point(pt)
          next unless [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(cls)
          next unless far_from_edges?(face, pt, Util.mm(wall_min_mm))
          row << [x, y]
        end
        rows << row unless row.empty?
      end
      { rows: rows, nx: nx, ny: ny, dx: dx, dy: dy, xmin: xmin, ymin: ymin, l: l, w: w }
    end

    def far_from_edges?(face, pt, dmin)
      return true if dmin <= 0
      face.edges.all? do |e|
        a = Util.pt_a(e.start.position)
        b = Util.pt_a(e.end.position)
        Geo.point_seg_dist(Util.pt_a(pt), a, b) >= dmin - 1.0e-6
      end
    end

    # ---------------------------------------------------------- sprinklers
    def sprinklers
      faces = selected_faces
      return unless faces
      o = Settings['sprinkler']
      r = Util.ask('Sprinkler layout / جانمایی اسپرینکلر', [
                     ['Hazard / کلاس خطر', o['hazard'], Catalog::HAZARDS.keys],
                     ['Head type / نوع هد', o['head'], %w[Pendent Upright]],
                     ['Max spacing mm (0 = by hazard) / فاصله', o['spacing'].to_f],
                     ['Min distance to wall mm / حداقل فاصله تا دیوار', o['wall_min'].to_f],
                     ['Ceiling height if floor selected mm / ارتفاع سقف', o['ceiling_height'].to_f],
                     ['Deflector below ceiling mm / فاصله دفلکتور', o['deflector'].to_f],
                     ['Branch pipe above ceiling mm / تراز لوله فرعی', o['branch_above'].to_f],
                     ['Branch direction / جهت لوله‌های فرعی', o['main_side'], %w[Auto X Y]],
                     ['Generate piping / ایجاد لوله‌کشی', 'Yes', Util.bool_list],
                     ['K-factor', o['k_factor'].to_f]
                   ])
      return unless r
      keys = %w[hazard head spacing wall_min ceiling_height deflector branch_above main_side]
      vals = keys.each_with_index.to_h { |k, i| [k, r[i]] }
      vals['k_factor'] = r[9]
      Settings.set('sprinkler', vals)
      piping = Util.yes?(r[8])
      hz = Catalog::HAZARDS[vals['hazard']]
      spacing = vals['spacing'].to_f > 0 ? [vals['spacing'].to_f, hz['spacing']].min : hz['spacing']
      report = []
      Util.operation('MEP: sprinkler layout') do
        faces.each do |face|
          report << sprinkler_zone(face, vals, spacing, hz['area'], piping)
        end
      end
      UI.messagebox(report.compact.join("\n\n")) unless report.compact.empty?
    end

    def sprinkler_zone(face, o, spacing, area, piping)
      g = grid_points(face, spacing, area, o['wall_min'])
      rows = g[:rows]
      return 'No heads fit inside the face.' if rows.empty?
      cz = ceiling_z(face, o['ceiling_height'])
      along_x = case o['main_side']
                when 'X' then true
                when 'Y' then false
                else g[:l] >= g[:w]
                end
      head_def = Equipment.sprinkler_definition(o['head'], o['k_factor'])
      zone = Util.model.active_entities.add_group
      zone.name = "Sprinkler zone #{o['hazard']}"
      zone.layer = Util.system_tag('SPR')
      Util.set_attrs(zone, 'container' => 'sprinkler_zone', 'hazard' => o['hazard'])
      ents = zone.entities
      upright = o['head'] == 'Upright'
      head_len = 48.0 # inlet -> deflector (mm)
      defl_z = cz - Util.mm(o['deflector'])
      origin_z = upright ? defl_z - Util.mm(head_len) : defl_z + Util.mm(head_len)
      zb = upright ? origin_z : cz + Util.mm(o['branch_above'])
      heads = rows.flatten(1)
      heads.each do |x, y|
        Equipment.place(ents, head_def, Geom::Transformation.translation(Geom::Point3d.new(x, y, origin_z)), 'SPR',
                        'model' => o['head'])
      end
      pipe_len = 0.0
      if piping
        # Branch lines: group heads by the coordinate perpendicular to branch direction.
        key = along_x ? 1 : 0
        lines = heads.group_by { |h| h[key].round(3) }.values
        main_c = if along_x
                   g[:xmin] + Util.mm(150)
                 else
                   g[:ymin] + Util.mm(150)
                 end
        taps = []
        lines.each do |line|
          line = line.sort_by { |h| h[1 - key] }
          # far end = farthest from the main
          line.reverse! if (line.first[1 - key] - main_c).abs > (line.last[1 - key] - main_c).abs
          # line[0] is nearest to main. Build segments from main to each head.
          fixed = line.first[key]
          coords = [main_c] + line.map { |h| h[1 - key] }
          n = line.size
          (0...coords.size - 1).each do |i|
            downstream = n - i
            dn = Catalog.sprinkler_pipe_dn(o['hazard'], downstream)
            a = along_x ? [coords[i], fixed, zb] : [fixed, coords[i], zb]
            b = along_x ? [coords[i + 1], fixed, zb] : [fixed, coords[i + 1], zb]
            pipe(ents, [a, b], dn)
            pipe_len += Geo.dist(a, b)
          end
          unless upright
            line.each do |x, y|
              pipe(ents, [[x, y, zb], [x, y, origin_z]], 25)
              pipe_len += (zb - origin_z).abs
            end
          end
          taps << [fixed, n]
        end
        # Cross main along the perpendicular axis, fed from the low side.
        taps.sort_by!(&:first)
        lo = along_x ? g[:ymin] : g[:xmin]
        feed = lo + Util.mm(150)
        coords = [feed] + taps.map(&:first)
        total = taps.sum(&:last)
        acc = total
        (0...coords.size - 1).each do |i|
          flow = acc
          acc -= taps[i][1]
          next if (coords[i + 1] - coords[i]).abs < 1.0e-3
          dn = Catalog.sprinkler_pipe_dn(o['hazard'], flow)
          a = along_x ? [main_c, coords[i], zb] : [coords[i], main_c, zb]
          b = along_x ? [main_c, coords[i + 1], zb] : [coords[i + 1], main_c, zb]
          pipe(ents, [a, b], dn)
          pipe_len += Geo.dist(a, b)
        end
      end
      area_m2 = (g[:l] * g[:w]) / (1_000_000.0 * Util::MM * Util::MM)
      "#{zone.name}: #{heads.size} heads, grid #{Util.fmt(Util.to_mm(g[:dx]))} x #{Util.fmt(Util.to_mm(g[:dy]))} mm, " \
        "#{Util.fmt(Util.to_mm(g[:dx]) * Util.to_mm(g[:dy]) / 1.0e6, 1)} m²/head (bbox #{Util.fmt(area_m2, 1)} m²), " \
        "pipe #{Util.fmt(Util.to_mm(pipe_len) / 1000.0, 1)} m"
    end

    def pipe(ents, pts, dn)
      RunBuilder.build(ents, pts, 'kind' => 'pipe', 'system' => 'SPR', 'dn' => dn,
                                  'elbow_radius' => 0, 'insulation' => 0)
    end

    # ------------------------------------------------------ lights / grid
    def lights
      faces = selected_faces
      return unless faces
      o = Settings['light']
      r = Util.ask('Lighting layout / جانمایی چراغ', [
                     ['Fixture / چراغ', o['model'], Catalog::LIGHTS.keys],
                     ['Max spacing mm / فاصله', o['spacing'].to_f],
                     ['Ceiling height if floor selected mm', o['ceiling_height'].to_f]
                   ])
      return unless r
      Settings.set('light', 'model' => r[0], 'spacing' => r[1], 'ceiling_height' => r[2])
      count = 0
      Util.operation('MEP: lighting layout') do
        defn = Equipment.light_definition(r[0])
        faces.each do |face|
          g = grid_points(face, r[1], nil, 0)
          cz = ceiling_z(face, r[2])
          zone = Util.model.active_entities.add_group
          zone.name = 'Lighting zone'
          Util.set_attrs(zone, 'container' => 'light_zone')
          g[:rows].flatten(1).each do |x, y|
            Equipment.place(zone.entities, defn, Geom::Transformation.translation(Geom::Point3d.new(x, y, cz)), 'LIGHT', 'model' => r[0])
            count += 1
          end
        end
      end
      UI.messagebox("#{count} fixtures placed / چراغ جانمایی شد")
    end

    def diffusers
      faces = selected_faces
      return unless faces
      o = Settings['terminal']
      r = Util.ask('Diffuser layout / جانمایی دیفیوزر', [
                     ['Terminal / دریچه', o['model'], Catalog::TERMINALS.keys],
                     ['Max spacing mm / فاصله', 3000.0],
                     ['Ceiling height if floor selected mm', o['ceiling_height'].to_f]
                   ])
      return unless r
      Settings.set('terminal', 'model' => r[0], 'ceiling_height' => r[2])
      count = 0
      Util.operation('MEP: diffuser layout') do
        defn = Equipment.terminal_definition(r[0])
        sys = defn.get_attribute(DICT, 'system') || 'SA'
        faces.each do |face|
          g = grid_points(face, r[1], nil, 0)
          cz = ceiling_z(face, r[2])
          g[:rows].flatten(1).each do |x, y|
            Equipment.place(Util.model.active_entities, defn,
                            Geom::Transformation.translation(Geom::Point3d.new(x, y, cz)), sys, 'model' => r[0])
            count += 1
          end
        end
      end
      UI.messagebox("#{count} terminals placed / دریچه جانمایی شد")
    end
  end
end
