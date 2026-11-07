# SketchUp geometry creation: 3D tiles, face division, pattern textures.
require 'json'

module BanianStudio
  module FloorStudio
    # Spatial hash over tile polygons for point lookup.
    class TileIndex
      def initialize(tiles, cell)
        @cell = cell > 0 ? cell : 1.0
        @grid = {}
        tiles.each do |t|
          bb = Geom2D.bbox(t.poly)
          ((bb[0] / @cell).floor..(bb[2] / @cell).floor).each do |i|
            ((bb[1] / @cell).floor..(bb[3] / @cell).floor).each do |j|
              (@grid[[i, j]] ||= []) << t
            end
          end
        end
      end

      def find(pt)
        list = @grid[[(pt[0] / @cell).floor, (pt[1] / @cell).floor]]
        return nil unless list
        list.each { |t| return t if Geom2D.point_in_poly?(pt, t.poly) }
        nil
      end
    end

    module Builder
      DICT = 'BanianFloorStudio'.freeze
      VERSION_TAG = 1

      module_function

      def pt3(p, z = 0.0)
        Geom::Point3d.new(p[0], p[1], z)
      end

      # ---------------------------------------------------------------
      # Edge profiles: list of [inset, z] from bottom outer edge to top.
      def profile_pts(kind, t, r)
        r = [[r.to_f, t * 0.95].min, 0.0].max
        pi = Math::PI
        pts =
          case kind.to_s
          when 'chamfer'
            r < 0.002 ? nil : [[0, 0], [0, t - r], [r, t]]
          when 'round'
            r < 0.002 ? nil : [[0, 0]] + (0..6).map { |k| f = k * pi / 12; [r * (1 - Math.cos(f)), t - r + r * Math.sin(f)] }
          when 'bullnose'
            rr = t * 0.5
            (0..8).map { |k| f = -pi / 2 + k * pi / 8; [rr * (1 - Math.cos(f)), rr + rr * Math.sin(f)] }
          when 'cove'
            r < 0.002 ? nil : [[0, 0]] + (0..6).map { |k| f = k * pi / 12; [r * Math.sin(f), t - r * Math.cos(f)] }
          when 'ogee'
            if r < 0.002
              nil
            else
              h = r * 0.5
              a = (0..3).map { |k| f = k * pi / 6; [h * (1 - Math.cos(f)), t - r + h * Math.sin(f)] }
              b = (1..3).map { |k| f = k * pi / 6; [h + h * Math.sin(f), t - h + h * (1 - Math.cos(f))] }
              [[0, 0]] + a + b
            end
          end
        pts ||= [[0, 0], [0, t]]
        out = []
        pts.each { |q| out << q if out.empty? || (out.last[0] - q[0]).abs > 1.0e-6 || (out.last[1] - q[1]).abs > 1.0e-6 }
        out
      end

      def curved?(kind)
        %w[round bullnose cove ogee].include?(kind.to_s)
      end

      # Convex solid from polygon via PolygonMesh (fast). flags: per-edge
      # booleans (true = factory edge, gets the profile). Returns top face.
      def mesh_solid(ents, poly, flags, prof, mat)
        n = poly.length
        rings = []
        prof.each do |ins, z|
          ring = poly
          if ins > 1.0e-9
            ring = Geom2D.offset_convex(poly, flags.map { |f| f ? ins : 0.0 })
            return nil unless ring
          end
          rings << [ring, z]
        end
        mesh = Geom::PolygonMesh.new(rings.length * n, rings.length * n + 2)
        idx = rings.map { |ring, z| ring.map { |q| mesh.add_point(pt3(q, z)) } }
        mesh.add_polygon(idx[0].reverse)
        (0...(rings.length - 1)).each do |k|
          n.times do |i|
            a = idx[k][i]
            b = idx[k][(i + 1) % n]
            c = idx[k + 1][(i + 1) % n]
            d = idx[k + 1][i]
            mesh.add_polygon(a, b, c, d)
          end
        end
        mesh.add_polygon(idx.last)
        ents.add_faces_from_mesh(mesh, 0, mat, nil)
        top_face(ents)
      end

      def top_face(ents)
        best = nil
        bz = -Float::INFINITY
        ents.each do |e|
          next unless e.is_a?(Sketchup::Face) && e.normal.z > 0.9999
          z = e.vertices.first.position.z
          if z > bz
            bz = z
            best = e
          end
        end
        best
      end

      def soften(ents)
        ents.grep(Sketchup::Edge).each do |e|
          fs = e.faces
          next unless fs.length == 2
          next if fs[0].normal.angle_between(fs[1].normal) > 0.62
          e.soft = true
          e.smooth = true
        end
      end

      def extrude(ents, outer, holes, t, mat)
        f = ents.add_face(outer.map { |q| pt3(q) })
        return nil unless f
        holes.each do |h|
          hf = ents.add_face(h.map { |q| pt3(q) })
          hf.erase! if hf && hf.valid? && hf != f
        end
        f.reverse! if f.normal.z < 0
        f.pushpull(t) if t > 1.0e-6
        ents.grep(Sketchup::Face).each { |ff| ff.material = mat }
        top_face(ents)
      end

      # Build one tile solid in tile-local coords into ents; returns top face.
      def tile_solid(ents, poly, flags, holes, ctx, mat)
        top = nil
        if holes.empty? && Geom2D.convex?(poly) && ctx[:thickness] > 1.0e-6
          top = mesh_solid(ents, poly, flags, ctx[:profile], mat)
          top ||= mesh_solid(ents, poly, flags, [[0, 0], [0, ctx[:thickness]]], mat)
          soften(ents) if top && ctx[:curved]
        end
        top ||= extrude(ents, poly, holes, ctx[:thickness], mat)
        top
      end

      def placement(t, ctx, rng)
        tr =
          if ctx[:surface]
            ctx[:surface].tile_frame(t)
          else
            Geom::Transformation.new(Geom::Point3d.new(t.cx, t.cy, 0)) *
              Geom::Transformation.rotation(ORIGIN, Z_AXIS, t.ang)
          end
        if t.tilt.to_f.abs > 1.0e-6
          hy = 0.0
          t.shape.each { |q| hy = q[1] if q[1] < hy }
          tr *= Geom::Transformation.rotation(Geom::Point3d.new(0, hy, 0), X_AXIS, t.tilt)
        end
        ia = ctx[:imp_angle]
        ih = ctx[:imp_height]
        if ia > 1.0e-6 || ih > 1.0e-6
          phi = rng.rand * 2 * Math::PI
          axis = Geom::Vector3d.new(Math.cos(phi), Math.sin(phi), 0)
          tr *= Geom::Transformation.new(Geom::Point3d.new(0, 0, rng.rand * ih)) if ih > 1.0e-6
          tr *= Geom::Transformation.rotation(ORIGIN, axis, (rng.rand * 2 - 1) * ia) if ia > 1.0e-6
        end
        tr
      end

      def add_region_face(ents, region, z)
        f = ents.add_face(region[:outer].map { |q| pt3(q, z) })
        return nil unless f
        region[:holes].each do |h|
          hf = ents.add_face(h.map { |q| pt3(q, z) })
          hf.erase! if hf && hf.valid? && hf != f
        end
        f.reverse! if f.valid? && f.normal.z < 0
        f.valid? ? f : nil
      end

      def sample_point(face)
        m = face.mesh(0)
        tri = m.polygon_points_at(1)
        x = (tri[0].x + tri[1].x + tri[2].x) / 3.0
        y = (tri[0].y + tri[1].y + tri[2].y) / 3.0
        [x.to_f, y.to_f]
      end

      def loops2d(face, xf = nil)
        outer = nil
        holes = []
        face.loops.each do |lp|
          pts = lp.vertices.map do |v|
            q = xf ? v.position.transform(xf) : v.position
            [q.x.to_f, q.y.to_f]
          end
          if lp.outer?
            outer = Geom2D.ccw(pts)
          else
            holes << pts
          end
        end
        [outer, holes]
      end

      def edge_flags(poly, shape)
        n = poly.length
        m = shape.length
        (0...n).map do |i|
          a = poly[i]
          b = poly[(i + 1) % n]
          (0...m).any? do |j|
            s0 = shape[j]
            s1 = shape[(j + 1) % m]
            Geom2D.dist_point_line(a, s0, s1) < 1.0e-4 && Geom2D.dist_point_line(b, s0, s1) < 1.0e-4
          end
        end
      end

      def to_tile_local(pts, t)
        ca = Math.cos(-t.ang)
        sa = Math.sin(-t.ang)
        pts.map do |q|
          dx = q[0] - t.cx
          dy = q[1] - t.cy
          [dx * ca - dy * sa, dx * sa + dy * ca]
        end
      end

      def material_ctx(model, p, tiles)
        base = Materials.resolve(model, p[:materials], Materials::DEFAULT_TILE, [217, 212, 204])
        weights = base.each_index.map { |i| (p[:weights][i] || 1.0).to_f }
        mats = base
        wts = weights
        if p[:shades] > 1
          mats = Materials.with_shades(model, base, p[:shades], p[:shade_amount])
          wts = []
          base.each_with_index do |m, i|
            k = m.texture ? 1 : p[:shades]
            k.times { wts << weights[i] / k }
          end
        end
        textured = mats.any?(&:texture)
        nvar = p[:tex_random] && textured ? [[p[:tex_variants], 1].max, 24].min : 1
        Materials.assign(tiles, p, wts, nvar)
        [mats, Materials.variants(p, nvar)]
      end

      # ---------------------------------------------------------------
      # 3D tiles. Returns stats hash.
      def build_3d(model, ents, lay, region, p, surf = nil)
        tiles = lay[:tiles]
        mats, vars = material_ctx(model, p, tiles)
        t = [p[:thickness].to_f, 0.0].max
        ctx = {
          :thickness => t,
          :profile => profile_pts(p[:profile], t, p[:profile_size]),
          :curved => curved?(p[:profile]),
          :imp_angle => p[:imp_angle].to_f, :imp_height => p[:imp_height].to_f,
          :surface => surf
        }
        rng = Random.new(p[:seed] * 101 + 3)
        full = tiles.select { |x| x.state == :inside }
        cut = tiles.select { |x| x.state == :boundary }

        counts = Hash.new(0)
        full.each { |x| counts[[x.key, x.mat, x.variant]] += 1 if x.key }
        defs = {}
        all_flags = lambda { |poly| Array.new(poly.length, true) }

        full.each do |tile|
          tr = placement(tile, ctx, rng)
          mat = mats[tile.mat]
          var = vars[tile.variant]
          k = [tile.key, tile.mat, tile.variant]
          if tile.key && counts[k] > 1
            d = defs[k]
            unless d
              d = model.definitions.add("BFS Tile #{p[:pattern]}")
              d.set_attribute(DICT, 'tile_def', true)
              top = tile_solid(d.entities, tile.shape, all_flags.call(tile.shape), [], ctx, mat)
              Materials.map_uv(top, mat, 0, 0, 0, var) if top
              defs[k] = d
            end
            ents.add_instance(d, tr)
          else
            g = ents.add_group
            top = tile_solid(g.entities, tile.shape, all_flags.call(tile.shape), [], ctx, mat)
            Materials.map_uv(top, mat, 0, 0, 0, var) if top
            g.transformation = tr
          end
        end

        npieces = 0
        unless cut.empty?
          pieces = cut_pieces(ents, cut, region, lay[:index], p)
          pieces.each do |tile, outer, holes|
            lo = to_tile_local(outer, tile)
            lh = holes.map { |h| to_tile_local(h, tile) }
            flags = edge_flags(lo, tile.shape)
            mat = mats[tile.mat]
            g = ents.add_group
            top = tile_solid(g.entities, lo, flags, lh, ctx, mat)
            Materials.map_uv(top, mat, 0, 0, 0, vars[tile.variant]) if top
            g.transformation = placement(tile, ctx, rng)
            npieces += 1
          end
        end

        if p[:gap] > 1.0e-6
          zg = t - [p[:grout_depth].to_f, 0.0].max
          zg = 0.0 if zg < 0
          gg = ents.add_group
          gg.name = 'Grout'
          gm = Materials.grout(model, p)
          if surf
            surf.grout(gg.entities, zg, gm)
            soften(gg.entities)
          else
            gf = add_region_face(gg.entities, region, zg)
            if gf
              gf.material = gm
              gf.back_material = gm
            end
          end
        end
        { 'full' => full.length, 'cut' => npieces, 'defs' => defs.length }
      end

      # Split region by boundary-tile outlines using SketchUp's engine and
      # return [[tile, outer, holes], ...] in local coords.
      def cut_pieces(ents, cut, region, index, p)
        temp = ents.add_group
        te = temp.entities
        add_region_face(te, region, 0.0)
        cut.each do |t|
          poly = t.poly
          n = poly.length
          n.times do |i|
            Geom2D.clip_segment_region(poly[i], poly[(i + 1) % n], region, index).each do |s|
              next if Math.hypot(s[1][0] - s[0][0], s[1][1] - s[0][1]) < 1.0e-4
              te.add_line(pt3(s[0]), pt3(s[1]))
            end
          end
        end
        cell = Math.sqrt(Geom2D.area(cut.first.poly)) * 1.5
        tidx = TileIndex.new(cut, cell)
        min_area = p[:min_piece].to_f**2
        out = []
        te.grep(Sketchup::Face).to_a.each do |f|
          sp = sample_point(f)
          tile = tidx.find(sp)
          next unless tile
          next if min_area > 0 && f.area < min_area
          outer, holes = loops2d(f)
          out << [tile, outer, holes]
        end
        temp.erase!
        out
      end

      # ---------------------------------------------------------------
      # Divide face only (no 3D). Splits the face in place.
      def divide(model, face, frame, lay, region, p)
        ents = face.parent.entities
        tiles = lay[:tiles]
        idx = lay[:index]
        segs = {}
        gap = p[:gap] > 1.0e-6
        tiles.each do |t|
          poly = t.poly
          n = poly.length
          n.times do |i|
            a = poly[i]
            b = poly[(i + 1) % n]
            list = t.state == :inside ? [[a, b]] : Geom2D.clip_segment_region(a, b, region, idx)
            list.each do |s|
              next if Math.hypot(s[1][0] - s[0][0], s[1][1] - s[0][1]) < 1.0e-4
              k = seg_key(s, gap)
              segs[k] ||= s
            end
          end
        end
        before = {}
        ents.grep(Sketchup::Face).each { |f| before[f.entityID] = true }
        temp = ents.add_group
        temp.transformation = frame
        te = temp.entities
        segs.each_value { |s| te.add_line(pt3(s[0]), pt3(s[1])) }
        temp.explode
        newf = ents.grep(Sketchup::Face).reject { |f| before[f.entityID] }
        newf << face if face.valid?
        if newf.length <= 1 && segs.length > 2
          # fallback: draw directly (always splits faces)
          segs.each_value { |s| ents.add_line(pt3(s[0]).transform(frame), pt3(s[1]).transform(frame)) }
          newf = ents.grep(Sketchup::Face).reject { |f| before[f.entityID] }
          newf << face if face.valid?
        end
        paint_divided(model, newf, frame, tiles, p) if p[:paint] || p[:paint_grout]
        { 'full' => tiles.count { |t| t.state == :inside }, 'cut' => tiles.count { |t| t.state == :boundary },
          'faces' => newf.length }
      end

      # Divide a curved / multi-face surface: pattern lines are cut per facet
      # in the unrolled 2D space and mapped back onto each facet.
      def divide_surface(model, ents, surf, lay, region, p)
        tiles = lay[:tiles]
        idx = lay[:index]
        gap = p[:gap] > 1.0e-6
        segs = {}
        tiles.each do |t|
          poly = t.poly
          n = poly.length
          n.times do |i|
            a = poly[i]
            b = poly[(i + 1) % n]
            list = t.state == :inside ? [[a, b]] : Geom2D.clip_segment_region(a, b, region, idx)
            list.each do |sg|
              next if Math.hypot(sg[1][0] - sg[0][0], sg[1][1] - sg[0][1]) < 1.0e-4
              segs[seg_key(sg, gap)] ||= sg
            end
          end
        end
        fidx = {}
        surf.facets.each do |f|
          fidx[f] = Geom2D::SegmentIndex.new(Geom2D.region_segments(:outer => f.outer, :holes => f.holes),
                                             [f.bb[2] - f.bb[0], f.bb[3] - f.bb[1], 1.0].max)
        end
        before = {}
        ents.grep(Sketchup::Face).each { |f| before[f.entityID] = true }
        temp = ents.add_group
        te = temp.entities
        count = 0
        segs.each_value do |sg|
          sb = Geom2D.bbox(sg)
          surf.facets.each do |f|
            next unless Geom2D.bbox_overlap?(sb, f.bb)
            Geom2D.clip_segment_region(sg[0], sg[1], { :outer => f.outer, :holes => f.holes }, fidx[f]).each do |q|
              next if Math.hypot(q[1][0] - q[0][0], q[1][1] - q[0][1]) < 1.0e-4
              te.add_line(surf.to3d(q[0], f), surf.to3d(q[1], f))
              count += 1
            end
          end
        end
        temp.explode
        newf = ents.grep(Sketchup::Face).reject { |f| before[f.entityID] }
        surf.facets.each { |f| newf << f.face if f.face && f.face.valid? }
        paint_surface(model, newf, surf, tiles, p) if p[:paint] || p[:paint_grout]
        { 'full' => tiles.count { |t| t.state == :inside }, 'cut' => tiles.count { |t| t.state == :boundary },
          'faces' => newf.length, 'lines' => count }
      end

      def paint_surface(model, faces, surf, tiles, p)
        mats, vars = material_ctx(model, p, tiles)
        gm = p[:paint_grout] && p[:gap] > 1.0e-6 ? Materials.grout(model, p) : nil
        cell = Math.sqrt(Geom2D.area(tiles.first.poly)) * 1.5
        tidx = TileIndex.new(tiles, cell)
        faces.each do |f|
          next unless f.valid?
          tri = f.mesh(0).polygon_points_at(1)
          c = Geom::Point3d.new((tri[0].x + tri[1].x + tri[2].x) / 3.0, (tri[0].y + tri[1].y + tri[2].y) / 3.0,
                                (tri[0].z + tri[1].z + tri[2].z) / 3.0)
          fc = surf.facet_for_3d(c)
          next unless fc
          front = f.normal.dot(fc.normal) >= 0
          q = c.transform(fc.xf)
          t = tidx.find([q.x.to_f, q.y.to_f])
          m = t ? (p[:paint] ? mats[t.mat] : nil) : gm
          next unless m
          if front
            f.material = m
          else
            f.back_material = m
          end
          Materials.map_uv(f, m, t.cx, t.cy, t.ang, vars[t.variant], front, fc.inv) if t && m.texture
        end
      end

      def seg_key(s, gap)
        a = s[0].map { |v| (v * 1000).round }
        b = s[1].map { |v| (v * 1000).round }
        return [a, b] if gap
        (a <=> b) <= 0 ? [a, b] : [b, a]
      end

      def paint_divided(model, faces, frame, tiles, p)
        mats, vars = material_ctx(model, p, tiles)
        gm = p[:paint_grout] && p[:gap] > 1.0e-6 ? Materials.grout(model, p) : nil
        inv = frame.inverse
        zaxis = frame.zaxis
        cell = Math.sqrt(Geom2D.area(tiles.first.poly)) * 1.5
        tidx = TileIndex.new(tiles, cell)
        faces.each do |f|
          next unless f.valid?
          front = f.normal.dot(zaxis) >= 0
          sp3 = f.mesh(0).polygon_points_at(1)
          c = Geom::Point3d.new((sp3[0].x + sp3[1].x + sp3[2].x) / 3.0, (sp3[0].y + sp3[1].y + sp3[2].y) / 3.0,
                                (sp3[0].z + sp3[1].z + sp3[2].z) / 3.0).transform(inv)
          t = tidx.find([c.x.to_f, c.y.to_f])
          if t
            next unless p[:paint]
            m = mats[t.mat]
            if front
              f.material = m
            else
              f.back_material = m
            end
            Materials.map_uv(f, m, t.cx, t.cy, t.ang, vars[t.variant], front, frame) if m.texture
          elsif gm
            if front
              f.material = gm
            else
              f.back_material = gm
            end
          end
        end
      end

      # ---------------------------------------------------------------
      # Pattern texture material from an image file; w, h in inches.
      def texture_material(model, file, w, h, name)
        mat = model.materials.add(name)
        mat.texture = file
        mat.texture.size = [w, h]
        mat
      end

      # Map texture on face: pattern origin o (local), rotation th.
      def map_texture(face, frame, o, th, mat, w, h)
        ca = Math.cos(th)
        sa = Math.sin(th)
        pts = []
        [[0, 0], [1, 0], [1, 1], [0, 1]].each do |q|
          px = q[0] * w
          py = q[1] * h
          lx = o[0] + px * ca - py * sa
          ly = o[1] + px * sa + py * ca
          pts << Geom::Point3d.new(lx, ly, 0).transform(frame)
          pts << Geom::Point3d.new(q[0], q[1], 0)
        end
        face.position_material(mat, pts, true)
        face.position_material(mat, pts, false)
        mat
      end

      def store(group, region, ui_params, mode, surf = nil)
        if surf
          group.set_attribute(DICT, 'surface', JSON.generate(surf.to_h))
        elsif group.get_attribute(DICT, 'surface')
          group.delete_attribute(DICT, 'surface')
        end
        group.set_attribute(DICT, 'version', VERSION_TAG)
        group.set_attribute(DICT, 'mode', mode)
        group.set_attribute(DICT, 'params', JSON.generate(ui_params))
        group.set_attribute(DICT, 'region', JSON.generate(Region.to_json_h(region)))
      end

      def generated?(ent)
        (ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)) &&
          !ent.get_attribute(DICT, 'params').nil?
      end

      def purge_tile_defs(model)
        defs = model.definitions
        return unless defs.respond_to?(:remove)
        defs.to_a.each do |d|
          next unless d.get_attribute(DICT, 'tile_def')
          next unless d.count_instances.zero?
          begin
            defs.remove(d)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
