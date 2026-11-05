# Material helpers: listing, defaults, assignment and UV mapping.
module BanianStudio
  module FloorStudio
    module Materials
      DEFAULT_TILE = 'BFS Tile'.freeze
      DEFAULT_GROUT = 'BFS Grout'.freeze

      module_function

      def hex(color)
        format('#%02x%02x%02x', color.red, color.green, color.blue)
      end

      def list(model)
        out = []
        model.materials.each do |m|
          tex = m.texture
          out << {
            'name' => m.name,
            'label' => (m.respond_to?(:display_name) ? m.display_name : m.name),
            'color' => hex(m.color),
            'textured' => !tex.nil?,
            'tw' => tex ? (tex.width * 25.4).round(1) : 0,
            'th' => tex ? (tex.height * 25.4).round(1) : 0
          }
        end
        out.sort_by { |h| h['label'].to_s.downcase }
      end

      def ensure_color(model, name, rgb)
        m = model.materials[name]
        return m if m
        m = model.materials.add(name)
        m.color = Sketchup::Color.new(*rgb)
        m
      end

      # names: array of material names (may be empty -> default)
      def resolve(model, names, fallback_name, fallback_rgb)
        mats = (names || []).map { |n| model.materials[n.to_s] }.compact
        mats = [ensure_color(model, fallback_name, fallback_rgb)] if mats.empty?
        mats
      end

      def parse_color(str, default)
        s = str.to_s.sub('#', '')
        return default unless s =~ /\A[0-9a-fA-F]{6}\z/
        [s[0, 2].to_i(16), s[2, 2].to_i(16), s[4, 2].to_i(16)]
      end

      # Grout: model material by name, or colour material.
      def grout(model, p)
        n = p[:grout_mat].to_s
        m = n.empty? ? nil : model.materials[n]
        return m if m
        rgb = parse_color(p[:grout_color], [138, 133, 128])
        name = format('BFS Grout %02x%02x%02x', *rgb)
        ensure_color(model, name, rgb)
      end

      # Colour shade variations for non-textured materials. Returns array.
      def with_shades(model, mats, count, amount)
        return mats if count <= 1 || amount <= 0
        out = []
        mats.each do |m|
          out << m
          next if m.texture
          base = m.color
          (1...count).each do |k|
            f = 1.0 + amount * ((k.to_f / (count - 1)) * 2 - 1)
            f = 1.0 + amount * 0.5 if (f - 1.0).abs < 1.0e-3
            name = "#{m.name} ~#{k}"
            v = model.materials[name]
            unless v
              v = model.materials.add(name)
              v.color = Sketchup::Color.new(clamp255(base.red * f), clamp255(base.green * f), clamp255(base.blue * f))
            end
            out << v
          end
        end
        out
      end

      def clamp255(v)
        v = v.round
        v < 0 ? 0 : (v > 255 ? 255 : v)
      end

      # Assign material index + texture variant index to tiles.
      def assign(tiles, p, weights, nvariants)
        n = weights.length
        total = 0.0
        weights.each { |w| total += w }
        total = n.to_f if total <= 0
        rng = Random.new(p[:seed].to_i * 31 + 17)
        mode = p[:mat_mode].to_s
        tiles.each_with_index do |t, i|
          t.mat =
            if n <= 1 then 0
            elsif mode == 'type' || mode == 'checker' then t.tag % n
            elsif mode == 'sequence' then i % n
            else
              r = rng.rand * total
              k = 0
              acc = weights[0]
              while r > acc && k < n - 1
                k += 1
                acc += weights[k]
              end
              k
            end
          t.variant = nvariants > 1 ? rng.rand(nvariants) : 0
        end
      end

      # Variant transforms for texture randomisation: [[ou, ov, rot], ...]
      def variants(p, count)
        rng = Random.new(p[:seed].to_i * 13 + 5)
        rot_mode = p[:tex_rot].to_s
        (0...[count, 1].max).map do |i|
          if i == 0 && count <= 1
            [0.0, 0.0, 0.0]
          else
            rot =
              case rot_mode
              when '180' then rng.rand(2) * Math::PI
              when '90' then rng.rand(4) * Math::PI / 2
              when 'random' then rng.rand * 2 * Math::PI
              else 0.0
              end
            [rng.rand, rng.rand, rot]
          end
        end
      end

      # Position material on a planar face whose plane is z = const (in the
      # face's entities coordinates). Tile frame: centre (cx, cy), angle ang.
      # xf (optional): transformation from tile-plane coords to the face's
      # entities coords (used for faces that are not horizontal).
      def map_uv(face, mat, cx, cy, ang, var, front = true, xf = nil)
        tex = mat.texture
        return unless tex
        tw = tex.width.to_f
        th = tex.height.to_f
        return if tw <= 0 || th <= 0
        z = xf ? 0.0 : face.vertices.first.position.z
        ca = Math.cos(ang)
        sa = Math.sin(ang)
        cr = Math.cos(var[2])
        sr = Math.sin(var[2])
        pts = []
        [[0, 0], [1, 0], [1, 1], [0, 1]].each do |q|
          lx = q[0] * 10.0
          ly = q[1] * 10.0
          wx = cx + lx * ca - ly * sa
          wy = cy + lx * sa + ly * ca
          u = (lx * cr + ly * sr) / tw + var[0]
          v = (-lx * sr + ly * cr) / th + var[1]
          wp = Geom::Point3d.new(wx, wy, z)
          wp = wp.transform(xf) if xf
          pts << wp
          pts << Geom::Point3d.new(u, v, 0)
        end
        face.position_material(mat, pts, front)
      rescue StandardError
        nil
      end
    end
  end
end
