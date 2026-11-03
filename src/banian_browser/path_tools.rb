module BanianStudio
  module BanianBrowser
    # Tools that work on a path of selected edges:
    #  * array a library component along the path (fences, posts, lamps...)
    #  * sweep a library profile (a face in a .skp) along the path (cornices, skirting...)
    module PathTools
      class << self
        def model
          Sketchup.active_model
        end

        # Ordered point chains built from the selected edges.
        def chains
          edges = model.selection.grep(Sketchup::Edge)
          return [] if edges.empty?
          adj = Hash.new { |h, k| h[k] = [] }
          edges.each { |e| e.vertices.each { |v| adj[v] << e } }
          used = {}
          result = []
          starts = adj.keys.select { |v| adj[v].length == 1 } + adj.keys
          starts.each do |v0|
            next if adj[v0].all? { |e| used[e] }
            chain = [v0.position]
            v = v0
            loop do
              e = adj[v].find { |x| !used[x] }
              break unless e
              used[e] = true
              v = e.other_vertex(v)
              chain << v.position
            end
            result << chain if chain.length > 1
          end
          result
        end

        def need_path
          c = chains
          UI.messagebox(I18n.t(:select_path)) if c.empty?
          c
        end

        def frame_for(dir)
          t = dir.clone
          t.normalize!
          xa = t
          za = Z_AXIS.clone
          if xa.parallel?(za)
            za = Y_AXIS.clone
          end
          ya = za.cross(xa)
          ya.normalize!
          za = xa.cross(ya)
          za.normalize!
          [xa, ya, za]
        end

        # ---- array along path ---------------------------------------------------------
        def array_along(path)
          ch = need_path
          return false if ch.empty?
          d = ModelOps.load_definition(path)
          return false unless d
          bb = d.bounds
          default_spacing = bb.width > 0 ? bb.width : 100
          prompts = [I18n.t(:spacing), I18n.t(:align_to_path), I18n.t(:include_end)]
          yes = I18n.t(:yes)
          no = I18n.t(:no)
          res = UI.inputbox(prompts, [default_spacing.to_l, yes, yes], ['', "#{yes}|#{no}", "#{yes}|#{no}"],
                            I18n.t(:array_along_path))
          return false unless res
          spacing = res[0].to_l.to_f
          return false if spacing <= 0
          align = res[1] == yes
          include_end = res[2] == yes
          model.start_operation(I18n.t(:op_array), true)
          grp = model.active_entities.add_group
          count = 0
          ch.each do |pts|
            placements(pts, spacing, include_end).each do |pt, dir|
              tr = if align
                     xa, ya, za = frame_for(dir)
                     Geom::Transformation.axes(pt, xa, ya, za)
                   else
                     Geom::Transformation.new(pt)
                   end
              grp.entities.add_instance(d, tr)
              count += 1
            end
          end
          grp.name = "#{d.name} x#{count}"
          model.commit_operation
          model.selection.clear
          model.selection.add(grp)
          Settings.record_use(path)
          count
        end

        # [[point, direction], ...] every `spacing` along the polyline.
        def placements(pts, spacing, include_end)
          out = []
          segs = []
          total = 0.0
          (0...(pts.length - 1)).each do |i|
            v = pts[i + 1] - pts[i]
            len = v.length.to_f
            next if len < 1e-6
            segs << [pts[i], v, len, total]
            total += len
          end
          return out if segs.empty?
          s = 0.0
          while s <= total + 1e-6
            out << point_at(segs, s)
            s += spacing
          end
          last = out.last
          if include_end && last && (total - (s - spacing)) > spacing * 0.05
            out << point_at(segs, total)
          end
          out
        end

        def point_at(segs, s)
          seg = segs.find { |x| s <= x[3] + x[2] + 1e-6 } || segs.last
          local = [[s - seg[3], 0].max, seg[2]].min
          dir = seg[1].clone
          [seg[0].offset(dir, local), dir]
        end

        # ---- profile sweep ------------------------------------------------------------
        def sweep_profile(path)
          ch = need_path
          return false if ch.empty?
          d = ModelOps.load_definition(path)
          return false unless d
          face, tr_in = largest_face(d.entities, Geom::Transformation.new, 0)
          unless face
            UI.messagebox(I18n.t(:no_profile))
            return false
          end
          model.start_operation(I18n.t(:op_sweep), true)
          made = 0
          begin
            ch.each do |pts|
              made += 1 if sweep_one(face, tr_in, pts)
            end
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            Util.log_error(e, 'sweep')
            UI.messagebox(I18n.t(:sweep_failed) + "\n" + e.message)
            return false
          end
          Settings.record_use(path)
          made
        end

        def largest_face(ents, tr, depth)
          best = nil
          best_tr = nil
          best_area = 0
          ents.each do |e|
            if e.is_a?(Sketchup::Face)
              a = e.area(tr)
              if a > best_area
                best = e
                best_tr = tr
                best_area = a
              end
            elsif depth < 4 && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
              f, t = largest_face(Util.definition_of(e).entities, tr * e.transformation, depth + 1)
              if f && f.area(t) > best_area
                best = f
                best_tr = t
                best_area = f.area(t)
              end
            end
          end
          [best, best_tr]
        end

        def sweep_one(face, tr_in, pts)
          return false if pts.length < 2
          nf = face.normal.transform(tr_in)
          nf.normalize!
          pv = if nf.parallel?(Z_AXIS)
                 Y_AXIS.clone
               else
                 dz = Z_AXIS % nf
                 v = Geom::Vector3d.new(-nf.x * dz, -nf.y * dz, 1.0 - nf.z * dz)
                 v.normalize!
                 v
               end
          pu = pv.cross(nf)
          pu.normalize!
          t = pts[1] - pts[0]
          t.normalize!
          side = t.parallel?(Z_AXIS) ? X_AXIS.clone : Z_AXIS.cross(t)
          side.normalize!
          up = t.cross(side)
          up.normalize!
          src = Geom::Transformation.axes(ORIGIN, pu, pv, nf)
          dst = Geom::Transformation.axes(pts[0], side, up, t)
          tr = dst * src.inverse * tr_in
          grp = model.active_entities.add_group
          ents = grp.entities
          outer = face.outer_loop.vertices.map { |v| v.position.transform(tr) }
          pf = ents.add_face(outer)
          return false unless pf
          face.loops.each do |lp|
            next if lp.outer?
            hole = ents.add_face(lp.vertices.map { |v| v.position.transform(tr) })
            hole.erase! if hole && hole.valid?
          end
          pf = ents.grep(Sketchup::Face).max_by(&:area)
          path_edges = ents.add_edges(pts)
          pf.reverse! if pf.normal % t < 0
          pf.followme(path_edges)
          ents.grep(Sketchup::Edge).each { |e| e.erase! if e.valid? && e.faces.empty? }
          mat = face.material
          grp.material = mat if mat
          true
        end
      end
    end
  end
end
