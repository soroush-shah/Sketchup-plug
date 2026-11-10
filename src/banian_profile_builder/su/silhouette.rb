# encoding: UTF-8
# Banian Profile Builder - flat front-view drawings of components for the
# panel previews (the real look of the user's balusters / bays instead of
# boxes). Computed once per definition and cached.

module BanianStudio
  module ProfileBuilder
    module Silhouette
      MAX_FACES = 450
      MAX_SCAN = 4000

      module_function

      # view 'x': horizontal = definition X, seen from -Y (bays)
      # view 'y': horizontal = definition Y, seen from +X (repeated components)
      def of(definition, view)
        @cache ||= {}
        key = [definition.object_id, view, definition.entities.size, definition.bounds.diagonal.to_f.round(4)]
        return @cache[key] if @cache.key?(key)
        faces = []
        collect(definition.entities, Geom::Transformation.new, nil, faces, 0)
        polys = []
        faces.each do |loops, normal, color|
          facing = view == 'x' ? -normal.y : normal.x
          next if facing < 0.05
          pts2 = loops.map { |l| l.map { |p| [hor(p, view), p.z * 25.4] } }
          depth = view == 'x' ? -loops[0][0].y : loops[0][0].x
          area = Profiles.signed_area(pts2[0]).abs
          polys << [pts2, color, depth, area]
        end
        polys = polys.sort_by { |q| -q[3] }.first(MAX_FACES).sort_by { |q| q[2] }
        bb = definition.bounds
        h0 = view == 'x' ? bb.min.x : bb.min.y
        h1 = view == 'x' ? bb.max.x : bb.max.y
        res = {
          'h0' => (h0 * 25.4).round(1), 'h1' => (h1 * 25.4).round(1),
          'z0' => (bb.min.z * 25.4).round(1), 'z1' => (bb.max.z * 25.4).round(1),
          'polys' => polys.map { |l, c, _d, _a| [l.map { |lp| lp.flatten.map { |v| v.round(1) } }, c] }
        }
        @cache[key] = res
      end

      def hor(p, view)
        (view == 'x' ? p.x : p.y) * 25.4
      end

      def collect(entities, tr, inherited, out, depth)
        return if out.size >= MAX_SCAN || depth > 5
        entities.each do |e|
          if e.is_a?(Sketchup::Face)
            mat = e.material || inherited
            loops = e.loops.map { |lp| lp.vertices.map { |v| tr * v.position } }
            n = tr * e.normal
            n.normalize! if n.valid?
            out << [loops, n, color_of(mat)]
            return if out.size >= MAX_SCAN
          elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            next if e.hidden?
            collect(e.definition.entities, tr * e.transformation, e.material || inherited, out, depth + 1)
          end
        end
      end

      def color_of(mat)
        return nil unless mat
        c = mat.color
        format('#%02x%02x%02x', c.red, c.green, c.blue)
      end

      # Silhouettes for every user component referenced by an assembly spec.
      def for_spec(model, spec)
        out = {}
        (spec['rows'] || []).each do |r|
          next unless r['type'] == 'component' || r['type'] == 'bay'
          view = r['type'] == 'bay' ? 'x' : 'y'
          k = "#{r['component']}|#{view}"
          next if out.key?(k)
          d = model.definitions[r['component'].to_s]
          out[k] = of(d, view) if d && d.valid?
        end
        out
      rescue StandardError => e
        puts "Banian silhouette: #{e.message}"
        out
      end
    end
  end
end
