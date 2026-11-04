# encoding: UTF-8
# Turns the polygons produced by the dialog's text engine into SketchUp
# geometry inside a component definition, and stores the parameters on it so
# the text can be edited later.

require 'json'

module BanianStudio
  module PersianText
    module Builder

      DICT = 'BS_PersianText'.freeze

      class << self

        def text_definition?(defn)
          defn.is_a?(Sketchup::ComponentDefinition) && !defn.get_attribute(DICT, 'params').nil?
        end

        def params_of(defn)
          raw = defn.get_attribute(DICT, 'params')
          raw ? JSON.parse(raw) : nil
        rescue StandardError
          nil
        end

        def definition_name(text)
          first = text.to_s.split(/\r?\n/).find { |l| !l.strip.empty? }.to_s.strip
          first = first[0, 24] + '…' if first.length > 24
          first.empty? ? 'متن فارسی' : "متن: #{first}"
        end

        # Creates a new definition with the text geometry.
        def create_definition(model, params, polys)
          defn = model.definitions.add(definition_name(params['text']))
          defn.behavior.is2d = true # glue to faces like native 3D text
          defn.behavior.snapto = SnapTo_Arbitrary
          defn.behavior.cuts_opening = false
          fill(defn, params, polys)
          defn
        end

        # (Re)fills a definition.
        def fill(defn, params, polys)
          ents = defn.entities
          ents.clear!
          filled = params['filled'] != false
          depth = params['extrudeIn'].to_f
          z = params['zOffsetIn'].to_f
          material = resolve_material(defn.model, params['material'])

          faces = []
          polys.each do |poly|
            outer = to_points(poly['o'], z)
            next if outer.length < 3
            holes = (poly['h'] || []).map { |h| to_points(h, z) }.select { |h| h.length >= 3 }
            if filled
              face = safe_face(ents, outer)
              next unless face
              holes.each do |h|
                hf = safe_face(ents, h)
                hf.erase! if hf && hf.valid? && hf != face
              end
              faces << face
            else
              ents.add_edges(outer + [outer.first])
              holes.each { |h| ents.add_edges(h + [h.first]) }
            end
          end

          faces = faces.select(&:valid?)
          faces.each { |f| f.reverse! if f.normal.z < 0 }
          if filled && depth.abs > 0.0001
            faces.each do |f|
              next unless f.valid?
              begin
                f.pushpull(depth)
              rescue StandardError
                next
              end
            end
            soften_sides(ents) if params['smooth'] != false
          end

          if material
            ents.grep(Sketchup::Face).each do |f|
              f.material = material
              f.back_material = material if depth.abs <= 0.0001
            end
          end

          new_name = definition_name(params['text'])
          if defn.name != new_name && defn.name.start_with?('متن')
            begin
              defn.name = new_name
            rescue StandardError
              nil
            end
          end
          defn.set_attribute(DICT, 'params', JSON.generate(params))
          defn.set_attribute(DICT, 'version', PLUGIN_VERSION)
          defn
        end

        def to_points(ring, z)
          pts = []
          ring.each do |xy|
            pts << Geom::Point3d.new(xy[0].to_f, xy[1].to_f, z)
          end
          # drop consecutive duplicates that SketchUp would merge
          clean = []
          pts.each { |p| clean << p unless clean.last && clean.last == p }
          clean.pop while clean.length > 2 && clean.first == clean.last
          clean
        end

        def safe_face(ents, pts)
          ents.add_face(pts)
        rescue StandardError
          # fall back: add the edges, then let SketchUp find the face
          begin
            edges = ents.add_edges(pts + [pts.first])
            edges.each { |e| e.find_faces if e.valid? }
            f = edges.map { |e| e.valid? ? e.faces : [] }.flatten.uniq.first
            f
          rescue StandardError
            nil
          end
        end

        # Soft/smooth the vertical edges between the side faces of extrusions,
        # so curved letters don't show every segment.
        def soften_sides(ents)
          limit = 35.degrees
          ents.grep(Sketchup::Edge).each do |e|
            fs = e.faces
            next unless fs.length == 2
            n1 = fs[0].normal
            n2 = fs[1].normal
            next unless n1.z.abs < 0.01 && n2.z.abs < 0.01
            next unless n1.angle_between(n2) < limit
            e.soft = true
            e.smooth = true
          end
        end

        def resolve_material(model, spec)
          return nil if spec.nil? || spec.to_s.empty?
          if spec.to_s =~ /\A#([0-9a-fA-F]{6})\z/
            name = "PersianText #{spec.upcase}"
            mat = model.materials[name]
            unless mat
              mat = model.materials.add(name)
              mat.color = Sketchup::Color.new(spec[1, 2].hex, spec[3, 2].hex, spec[5, 2].hex)
            end
            mat
          else
            model.materials[spec.to_s]
          end
        end

      end
    end
  end
end
