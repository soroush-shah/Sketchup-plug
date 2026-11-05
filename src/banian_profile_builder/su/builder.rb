# encoding: UTF-8
# Banian Profile Builder - turns core geometry into SketchUp entities.
#
# Speed rules used everywhere in this file:
#  * one PolygonMesh + Entities#fill_from_mesh per solid (no Follow Me)
#  * repeated pieces share one ComponentDefinition (keyed by geometry)
#  * editing rebuilds only the edited object
#  * callers wrap work in start_operation(..., disable_ui = true)

require 'json'
require 'digest/md5'

module BanianStudio
  module ProfileBuilder
    module Builder
      DICT = 'banian_pb'.freeze
      FORMAT = 1

      FLAGS = begin
        Geom::PolygonMesh::SOFTEN_BASED_ON_INDEX | Geom::PolygonMesh::SMOOTH_SOFT_EDGES
      rescue NameError
        2 | 8
      end

      PRESET_COLORS = {
        'BPB Wood' => [[201, 160, 112], 1.0],
        'BPB Metal' => [[160, 166, 172], 1.0],
        'BPB Glass' => [[150, 200, 225], 0.35],
        'BPB White' => [[242, 240, 234], 1.0],
        'BPB Concrete' => [[180, 178, 172], 1.0]
      }.freeze

      module_function

      # ---------- identification -----------------------------------------

      def kind(ent)
        return nil unless ent.is_a?(Sketchup::Group) && ent.valid?
        ent.get_attribute(DICT, 'kind')
      end

      def pb?(ent)
        !kind(ent).nil?
      end

      def read(ent)
        {
          'kind' => kind(ent),
          'spec' => JSON.parse(ent.get_attribute(DICT, 'spec', '{}')),
          'path' => JSON.parse(ent.get_attribute(DICT, 'path', '[]')),
          'closed' => ent.get_attribute(DICT, 'closed', false) ? true : false,
          'up' => (u = ent.get_attribute(DICT, 'up', nil)) ? JSON.parse(u) : nil
        }
      rescue JSON::ParserError
        nil
      end

      # ---------- geometry helpers ---------------------------------------

      def pt(a)
        Geom::Point3d.new(a[0], a[1], a[2])
      end

      # PolygonMesh#add_point looks for duplicates, which gets slow on huge
      # meshes, so very long sweeps are inserted in bounded chunks.
      CHUNK = 2000

      def fill(entities, data)
        return false unless data && !data[:polygons].empty?
        verts = data[:vertices]
        first = true
        data[:polygons].each_slice(CHUNK) do |chunk|
          mesh = Geom::PolygonMesh.new(chunk.size * 2 + 8, chunk.size)
          local = {}
          chunk.each do |poly|
            idx = poly.map do |i|
              j = i.abs
              li = (local[j] ||= mesh.add_point(pt(verts[j - 1])))
              i < 0 ? -li : li
            end
            next if idx.map(&:abs).uniq.size < 3
            mesh.add_polygon(idx)
          end
          if first
            entities.fill_from_mesh(mesh, true, FLAGS)
            first = false
          else
            entities.add_faces_from_mesh(mesh, FLAGS)
          end
        end
        data[:caps].each { |loops, normal| add_cap(entities, loops, normal) }
        true
      end

      def add_cap(entities, loops, normal)
        outer = loops[0].map { |q| pt(q) }
        face = entities.add_face(outer)
        return unless face
        n = Geom::Vector3d.new(normal[0], normal[1], normal[2])
        face.reverse! if face.normal.dot(n) < 0
        loops[1..-1].each do |l|
          hole = entities.add_face(l.map { |q| pt(q) })
          hole.erase! if hole && hole.valid?
        end
      rescue ArgumentError
        nil
      end

      def material(model, name)
        return nil if name.nil? || name.to_s.empty?
        m = model.materials[name]
        return m if m
        preset = PRESET_COLORS[name]
        return nil unless preset
        m = model.materials.add(name)
        m.color = Sketchup::Color.new(*preset[0])
        m.alpha = preset[1] if preset[1] < 1.0
        m
      end

      def local_path(points)
        o = points[0]
        [o, points.map { |p| [p[0] - o[0], p[1] - o[1], p[2] - o[2]] }]
      end

      # ---------- create / rebuild ---------------------------------------

      # points: path in the coordinates of `entities` (inches).
      def create(entities, kind, spec, points, closed, up = nil)
        prep = Sweep.prepare(points, closed, up)
        return nil if prep[:points].size < 2
        origin, pts = local_path(prep[:points])
        group = entities.add_group
        group.transformation = Geom::Transformation.new(pt(origin))
        store_path(group, pts, prep[:closed], prep[:up])
        group.set_attribute(DICT, 'kind', kind)
        ok = build_into(group, kind, spec, pts, prep[:closed], prep[:up])
        unless ok
          group.erase! if group.valid?
          return nil
        end
        group
      end

      def store_path(group, pts, closed, up)
        group.set_attribute(DICT, 'path', JSON.generate(pts.map { |p| p.map { |c| c.round(6) } }))
        group.set_attribute(DICT, 'closed', closed)
        group.set_attribute(DICT, 'up', up ? JSON.generate(up) : nil)
      end

      def rebuild(group, spec = nil, new_path = nil)
        info = read(group)
        return false unless info
        spec ||= info['spec']
        pts = new_path || info['path']
        prep = Sweep.prepare(pts, info['closed'], info['up'])
        return false if prep[:points].size < 2
        group.make_unique if group.definition.count_instances > 1
        old_defs = JSON.parse(group.get_attribute(DICT, 'defs', '[]')) rescue []
        group.entities.clear!
        store_path(group, prep[:points], prep[:closed], prep[:up]) if new_path
        ok = build_into(group, info['kind'], spec, prep[:points], prep[:closed], prep[:up])
        purge_defs(group.model, old_defs)
        ok
      end

      def build_into(group, kind, spec, pts, closed, up)
        prep = { points: pts, closed: closed, up: up }
        model = group.model
        if kind == 'assembly'
          build_assembly(group, spec, prep)
        else
          loops = Profiles.to_inches(Profiles.placed_loops(spec))
          return false if loops.empty?
          return false unless fill(group.entities, Sweep.mesh(prep, loops))
          group.material = material(model, spec['material'])
          len = PathOps.length(pts, closed) * 25.4
          area = Profiles.area(Profiles.placed_loops(spec))
          qty = [{ 'name' => spec['name'].to_s, 'type' => 'member', 'profile' => spec['profile'],
                   'size' => Profiles.size_label(spec), 'count' => 1, 'length_mm' => len.round(1),
                   'area_mm2' => area.round(2), 'volume_mm3' => (len * area).round(0),
                   'material' => spec['material'].to_s }]
          group.name = "#{profile_name(spec)} #{Profiles.size_label(spec)}"
          finish(group, spec, qty, [])
        end
      end

      def profile_name(spec)
        e = Profiles.entry(spec['profile'].to_s)
        return e.name_en if e
        spec['custom_name'].to_s.empty? ? 'Custom profile' : spec['custom_name'].to_s
      end

      def finish(group, spec, qty, defs)
        group.set_attribute(DICT, 'spec', JSON.generate(spec))
        group.set_attribute(DICT, 'qty', JSON.generate(qty))
        group.set_attribute(DICT, 'defs', JSON.generate(defs))
        group.set_attribute(DICT, 'format', FORMAT)
        true
      end

      def build_assembly(group, spec, prep)
        model = group.model
        plan = Assembly.plan(prep, spec)
        ents = group.entities
        plan[:layers].each do |l|
          row = l[:row]
          mat = material(model, row['material'])
          l[:paths].each do |p, c|
            sub = ents.add_group
            ok = fill(sub.entities, Sweep.mesh({ points: p, closed: c, up: prep[:up] }, l[:loops]))
            unless ok
              sub.erase!
              next
            end
            sub.name = row['name'].to_s
            sub.material = mat
            sub.hidden = true if row['visible'] == false
            sub.set_attribute(DICT, 'part', l[:index])
          end
        end
        defs = []
        plan[:repeats].each do |rp|
          row = rp[:row]
          mat = material(model, row['material'])
          rp[:items].each do |it|
            d = piece_definition(model, rp[:loops], it[:len], row['name'])
            next unless d
            defs << d.name unless defs.include?(d.name)
            t, r, u = it[:frame]
            o = Vec.add(it[:origin], Vec.mul(u, it[:v0]))
            tr = Geom::Transformation.axes(pt(o), Geom::Vector3d.new(*r), Geom::Vector3d.new(*t), Geom::Vector3d.new(*u))
            inst = ents.add_instance(d, tr)
            inst.material = mat
            inst.hidden = true if row['visible'] == false
          end
        end
        name = spec['name'].to_s
        if name.empty?
          pr = Presets::INDEX[spec['preset'].to_s]
          name = pr ? pr.name_en : 'Assembly'
        end
        group.name = name
        finish(group, spec, Assembly.quantities(plan), defs)
      end

      # Shared definition for a straight piece: studs, posts and balusters
      # of every wall in the model reuse the same definition when equal.
      def piece_definition(model, loops, len, label)
        key = Digest::MD5.hexdigest(JSON.generate([loops.map { |l| l.map { |q| q.map { |c| c.round(5) } } }, len.round(5)]))
        @defs ||= {}
        cache = (@defs[model.object_id] ||= {})
        d = cache[key]
        return d if d && d.valid?
        if cache.empty?
          model.definitions.each do |dd|
            k = dd.get_attribute(DICT, 'piece')
            cache[k] = dd if k
          end
          d = cache[key]
          return d if d && d.valid?
        end
        mm = (len * 25.4).round
        d = model.definitions.add("BPB #{label.to_s.empty? ? 'Piece' : label} #{mm}mm")
        unless fill(d.entities, Sweep.prism(loops, len))
          model.definitions.remove(d) if model.definitions.respond_to?(:remove)
          return nil
        end
        d.set_attribute(DICT, 'piece', key)
        cache[key] = d
        d
      end

      def purge_defs(model, names)
        return unless model.definitions.respond_to?(:remove)
        names.each do |n|
          d = model.definitions[n]
          next unless d && d.valid? && d.count_instances == 0 && d.get_attribute(DICT, 'piece')
          model.definitions.remove(d)
        end
      end

      def forget_cache(model)
        @defs.delete(model.object_id) if @defs
      end
    end
  end
end
