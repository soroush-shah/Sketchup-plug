# encoding: UTF-8
#
# Banian Material UV - SketchUp adapter: collects faces, builds the abstract
# mesh, runs the core and writes UVs with Face#position_material.
#
module BanianStudio
  module MaterialUV
    module Mapper

      C = Core

      # One face to paint, with its world transformation and owning instance.
      class Target
        attr_reader :face, :tr, :inst
        def initialize(face, tr, inst)
          @face = face; @tr = tr; @inst = inst
        end
      end

      module_function

      def entities_of(inst)
        if inst.is_a?(Sketchup::Group)
          inst.entities
        else
          inst.definition.entities
        end
      end

      def definition_of(inst)
        if inst.respond_to?(:definition)
          inst.definition
        else
          inst.entities.parent
        end
      end

      def active_transform(model)
        model.respond_to?(:edit_transform) ? model.edit_transform : Geom::Transformation.new
      end

      # Collect targets from a list of entities (selection).
      # opts: :expand (soft-connected surface)
      def collect(model, ents, opts = {})
        out = []
        seen_faces = {}
        seen_defs = {}
        tr0 = active_transform(model)
        ents.each { |e| collect_entity(e, tr0, nil, out, seen_faces, seen_defs) }
        out = expand_surface(out, seen_faces) if opts[:expand]
        out
      end

      def collect_entity(e, tr, inst, out, seen_faces, seen_defs)
        if e.is_a?(Sketchup::Face)
          return if seen_faces[e.entityID]
          return if e.respond_to?(:hidden?) && e.hidden?
          seen_faces[e.entityID] = true
          out << Target.new(e, tr, inst)
        elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          return if e.hidden?
          d = definition_of(e)
          key = d ? d.entityID : e.entityID
          return if seen_defs[key]
          seen_defs[key] = true
          t = tr * e.transformation
          entities_of(e).each { |c| collect_entity(c, t, e, out, seen_faces, seen_defs) }
        end
      end

      # Grow each face to the surface it belongs to (faces joined by soft /
      # smooth edges) - same behaviour as clicking a curved surface in SketchUp.
      def expand_surface(targets, seen)
        out = targets.dup
        stack = targets.dup
        until stack.empty?
          t = stack.pop
          t.face.edges.each do |edge|
            next unless edge.soft? || edge.smooth?
            edge.faces.each do |g|
              next if seen[g.entityID]
              seen[g.entityID] = true
              nt = Target.new(g, t.tr, t.inst)
              out << nt
              stack << nt
            end
          end
        end
        out
      end

      # All faces of the surface a face belongs to, or of its whole container.
      def targets_for_face(face, tr, inst, scope)
        case scope
        when 'face'
          [Target.new(face, tr, inst)]
        when 'object'
          seen_f = {}; seen_d = {}
          out = []
          face.parent.entities.each do |e|
            collect_entity(e, tr, inst, out, seen_f, seen_d) if e.is_a?(Sketchup::Face)
          end
          out
        else
          seen = { face.entityID => true }
          expand_surface([Target.new(face, tr, inst)], seen)
        end
      end

      def mirrored?(tr)
        x = tr.xaxis; y = tr.yaxis; z = tr.zaxis
        (x * y) % z < 0
      end

      # Build the abstract mesh. Returns [mesh, face_ids]
      def build_mesh(targets)
        mesh = C::Mesh.new
        vkey = {}
        targets.each do |t|
          f = t.face
          vids = []
          f.outer_loop.vertices.each do |v|
            id = v.entityID
            unless vkey[id]
              vkey[id] = true
              mesh.add_vertex(id, (t.tr * v.position).to_a)
            end
            vids << id
          end
          mesh.add_face(vids, t, mirrored?(t.tr))
        end
        targets.each do |t|
          t.face.edges.each do |e|
            mesh.set_soft(e.start.entityID, e.end.entityID, e.soft? || e.smooth?)
          end
        end
        [mesh, (0...mesh.faces.size).to_a]
      end

      # ------------------------------------------------------------------
      # Settings helpers
      # ------------------------------------------------------------------
      AXES = {
        'x' => [1.0, 0.0, 0.0],
        'y' => [0.0, 1.0, 0.0],
        'z' => [0.0, 0.0, 1.0]
      }

      def deg(x) x.to_f * Math::PI / 180.0 end

      def num(h, k, d)
        v = h[k]
        return d if v.nil? || v == ''
        f = v.to_f
        f.finite? ? f : d
      end

      def core_settings(model, s, start_face_id = nil)
        cs = {}
        cs[:mode] = s['mode'] || 'auto'
        cs[:axis] = AXES[s['axis']]
        cs[:size_mode] = s['size_mode'] == 'fit' ? 'fit' : 'real'
        cs[:repeat_u] = num(s, 'repeat_u', 1.0)
        cs[:repeat_v] = num(s, 'repeat_v', 1.0)
        cs[:seam] = deg(num(s, 'seam', 0.0))
        cs[:cross_hard] = s['cross_hard'] != false
        cs[:start_face] = start_face_id
        if cs[:mode] == 'planar'
          case s['planar_dir']
          when 'camera'
            cam = model.active_view.camera
            dir = cam.direction.to_a
            up = cam.up.to_a
            u = C::V.norm(C::V.cross(dir, up))
            v = C::V.norm(C::V.cross(u, dir))
            cs[:planar_u] = u; cs[:planar_v] = v
          when 'x' then cs[:planar_dir] = [1.0, 0.0, 0.0]
          when 'y' then cs[:planar_dir] = [0.0, -1.0, 0.0]
          when 'z' then cs[:planar_dir] = [0.0, 0.0, 1.0]
          end
        end
        cs
      end

      def uv_transform(s)
        su = num(s, 'scale_u', 100.0) / 100.0
        sv = num(s, 'scale_v', 100.0) / 100.0
        su = 1.0 if su.abs < 1.0e-6
        sv = 1.0 if sv.abs < 1.0e-6
        {
          :scale_u => su, :scale_v => sv,
          :rot => deg(num(s, 'rotation', 0.0)),
          :off_u => num(s, 'offset_u', 0.0), :off_v => num(s, 'offset_v', 0.0),
          :flip_u => s['flip_u'] == true, :flip_v => s['flip_v'] == true
        }
      end

      # Length conversion from model units to inches
      def unit_factor(model)
        u = model.options['UnitsOptions']['LengthUnit'] rescue 0
        case u
        when 1 then 12.0
        when 2 then 1.0 / 25.4
        when 3 then 1.0 / 2.54
        when 4 then 39.37007874015748
        when 5 then 36.0
        else 1.0
        end
      end

      def unit_name(model)
        u = model.options['UnitsOptions']['LengthUnit'] rescue 0
        %w[in ft mm cm m yd][u.to_i] || 'in'
      end

      def material_for(target, s, chosen)
        return chosen if chosen
        m = target.face.material
        m = target.inst.material if m.nil? && target.inst
        m
      end

      def tile_size(mat, s, model)
        tw = th = nil
        if mat && mat.texture
          tw = mat.texture.width.to_f
          th = mat.texture.height.to_f
        end
        f = unit_factor(model)
        ow = num(s, 'tile_w', 0.0) * f
        oh = num(s, 'tile_h', 0.0) * f
        if ow > 0 && oh > 0
          tw = ow; th = oh
        elsif ow > 0
          th = tw && tw > 0 ? th * ow / tw : ow
          tw = ow
        elsif oh > 0
          tw = th && th > 0 ? tw * oh / th : oh
          th = oh
        end
        tw = 39.37 if tw.nil? || tw <= 0
        th = 39.37 if th.nil? || th <= 0
        [tw, th]
      end

      # ------------------------------------------------------------------
      # Apply
      # ------------------------------------------------------------------
      # Returns result hash {:faces, :skipped, :modes => {mode=>count}}
      def apply(model, targets, s, chosen_mat, start_target = nil)
        res = { :faces => 0, :skipped => 0, :modes => {}, :no_texture => false }
        return res if targets.empty?
        mesh, ids = build_mesh(targets)
        start_id = nil
        if start_target
          mesh.faces.each { |f| if f.ref.face == start_target.face then start_id = f.id; break end }
        end
        cs = core_settings(model, s, start_id)
        computed = C.compute(mesh, ids, cs)
        maps = computed[:maps]
        computed[:islands].each { |i| res[:modes][i[:mode]] = (res[:modes][i[:mode]] || 0) + 1 }
        t = uv_transform(s)
        sides = s['sides'] || 'front'
        allow4 = s['allow_distort'] != false
        fit = cs[:size_mode] == 'fit'
        size_cache = {}

        mesh.faces.each do |fr|
          target = fr.ref
          face = target.face
          next unless face.valid?
          mat = material_for(target, s, chosen_mat)
          if mat.nil?
            res[:skipped] += 1
            next
          end
          unless mat.texture
            face.material = mat if sides != 'back'
            face.back_material = mat if sides != 'front'
            res[:no_texture] = true
            res[:faces] += 1
            next
          end
          m = maps[fr.id]
          unless m
            res[:skipped] += 1
            next
          end
          tw, th = (size_cache[mat] ||= tile_size(mat, s, model))
          tm = {}
          m.each do |v, uv|
            base = fit ? uv : [uv[0] / tw, uv[1] / th]
            tm[v] = C.transform_uv(base, t)
          end
          ok = write_uv(face, mesh, fr.id, tm, mat, sides, allow4)
          ok ? res[:faces] += 1 : res[:skipped] += 1
        end
        res
      end

      def write_uv(face, mesh, fi, tm, mat, sides, allow4)
        pairs = C.face_pairs(mesh, fi, tm, allow4)
        return false unless pairs
        vmap = {}
        face.outer_loop.vertices.each { |v| vmap[v.entityID] = v }
        build = lambda do |prs|
          arr = []
          prs.each do |vid, uv|
            arr << vmap[vid].position
            arr << Geom::Point3d.new(uv[0], uv[1], 0)
          end
          arr
        end
        done = false
        [pairs, (pairs.size == 4 ? C.face_pairs(mesh, fi, tm, false) : nil)].compact.each do |prs|
          begin
            pts = build.call(prs)
            face.position_material(mat, pts, true) if sides != 'back'
            face.position_material(mat, pts, false) if sides != 'front'
            done = true
            break
          rescue StandardError
            next
          end
        end
        done
      end

      # Restore SketchUp's default texture placement
      def reset(model, targets, sides)
        n = 0
        targets.each do |t|
          f = t.face
          next unless f.valid?
          [[true, f.material], [false, f.back_material]].each do |front, mat|
            next if mat.nil?
            next if front && sides == 'back'
            next if !front && sides == 'front'
            if f.respond_to?(:clear_texture_position)
              begin
                f.clear_texture_position(front)
                next
              rescue StandardError
              end
            end
            if front
              f.material = nil; f.material = mat
            else
              f.back_material = nil; f.back_material = mat
            end
          end
          n += 1
        end
        n
      end

      # Analyse selection only (for the "Detect" button)
      def detect(targets)
        return [] if targets.empty?
        mesh, ids = build_mesh(targets)
        fset = {}
        ids.each { |i| fset[i] = true }
        mesh.islands(fset).map { |isl| C.analyze(mesh, isl)[:mode] }
      end
    end
  end
end
