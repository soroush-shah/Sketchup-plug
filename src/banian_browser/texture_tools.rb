module BanianStudio
  module BanianBrowser
    # Texture positioning: rotate, flip, scale, nudge, fit, align.
    # Works on textured faces in the selection (and optionally inside selected
    # groups/components). A face that only inherits its texture from a parent group
    # gets the material painted on it first, so it can be positioned.
    # With nothing selected it works on every face painted with the material chosen in
    # SketchUp (paint bucket / Materials panel).
    module TextureTools
      SUMMARY_LIMIT = 3000

      class << self
        def model
          Sketchup.active_model
        end

        # [[face, front?], ...] for every textured face that can be positioned.
        # limit: stop collecting after this many faces (for the quick summary).
        def targets(limit = nil)
          include_groups = Settings['tex_include_groups']
          out = []
          seen = {}
          visit = nil
          visit = lambda do |e, inherited, depth|
            return if depth > 12 || (limit && out.length >= limit)
            if e.is_a?(Sketchup::Face)
              return if seen[e]
              seen[e] = true
              out << [e, inherited]
            elsif include_groups && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
              mat = e.material || inherited
              Util.definition_of(e).entities.each { |c| visit.call(c, mat, depth + 1) }
            end
          end
          model.selection.each { |e| visit.call(e, nil, 0) }
          result = []
          out.each do |face, inherited|
            if face.material && face.material.texture
              result << [face, true]
            elsif face.back_material && face.back_material.texture && face.material.nil?
              result << [face, false]
            elsif face.material.nil? && inherited && inherited.texture
              result << [face, true, inherited]
            end
          end
          result
        end

        # Every face (model + all definitions) painted with mat on either side.
        def faces_with(mat)
          out = []
          scan = lambda do |ents|
            ents.each do |e|
              next unless e.is_a?(Sketchup::Face)
              if e.material == mat
                out << [e, true]
              elsif e.back_material == mat
                out << [e, false]
              end
            end
          end
          scan.call(model.entities)
          model.definitions.each { |d| scan.call(d.entities) unless d.image? }
          out
        end

        def picked_texture
          m = MaterialOps.current
          m && !m.deleted? && m.texture ? m : nil
        end

        # Something selected: only the selection. Nothing selected: every face using
        # the material chosen in SketchUp (paint bucket / Materials panel).
        def resolve_targets
          return targets unless model.selection.empty?
          mat = picked_texture
          mat ? faces_with(mat) : []
        end

        # What the texture buttons will change right now (shown in the browser).
        def summary
          if model.selection.empty?
            m = MaterialOps.current
            return { 'mode' => 'material', 'mat' => MaterialOps.info(m), 'textured' => !!(m && m.texture) }
          end
          list = targets(SUMMARY_LIMIT)
          mats = list.map { |f, front, bake| bake || (front ? f.material : f.back_material) }.compact.uniq
          { 'mode' => 'selection', 'faces' => list.length, 'more' => list.length >= SUMMARY_LIMIT,
            'mats' => mats.length, 'mat' => MaterialOps.info(mats.first) }
        end

        def run(name)
          list = resolve_targets
          if list.empty?
            UI.messagebox(I18n.t(:select_textured))
            return 0
          end
          @single = list.length == 1
          model.start_operation(I18n.t(:op_texture), true)
          n = 0
          list.each do |face, front, bake|
            begin
              face.material = bake if bake
              n += 1 if yield(face, front)
            rescue StandardError => e
              Util.log_error(e, name)
            end
          end
          model.commit_operation
          n
        end

        # Three non-collinear points on the face plane and their UVs.
        def sample(face, front, _tw = nil)
          uvh = face.get_UVHelper(true, true)
          p0 = face.bounds.center.project_to_plane(face.plane)
          axes = face.normal.axes
          pts = [p0, p0.offset(axes[0], 10), p0.offset(axes[1], 10)]
          uvs = pts.map do |p|
            q = front ? uvh.get_front_UVQ(p) : uvh.get_back_UVQ(p)
            z = q.z.abs < 1e-12 ? 1.0 : q.z
            [q.x / z, q.y / z]
          end
          [pts, uvs]
        end

        def apply(face, front, pts, uvs)
          mat = front ? face.material : face.back_material
          args = []
          pts.each_with_index do |p, i|
            args << p
            args << Geom::Point3d.new(uvs[i][0], uvs[i][1], 0)
          end
          face.position_material(mat, args, front)
          true
        end

        # Generic UV transform. One face turns around its own centre; several faces
        # turn around the texture origin so neighbouring faces stay seamless.
        def transform_uv(name)
          run(name) do |face, front|
            pts, uvs = sample(face, front)
            c = @single ? uvs[0] : [0.0, 0.0]
            new_uvs = uvs.map { |u| yield(u[0] - c[0], u[1] - c[1], c) }
            apply(face, front, pts, new_uvs)
          end
        end

        def rotate(deg)
          a = deg.to_f * Math::PI / 180.0
          ca = Math.cos(a)
          sa = Math.sin(a)
          transform_uv('rotate') { |du, dv, c| [c[0] + du * ca + dv * sa, c[1] - du * sa + dv * ca] }
        end

        def flip(axis)
          transform_uv('flip') do |du, dv, c|
            axis == 'h' ? [c[0] - du, c[1] + dv] : [c[0] + du, c[1] - dv]
          end
        end

        # factor > 1 makes the texture bigger on the face.
        def scale(factor)
          f = factor.to_f
          return 0 if f <= 0
          transform_uv('scale') { |du, dv, c| [c[0] + du / f, c[1] + dv / f] }
        end

        # Offset in fractions of one texture tile.
        def nudge(du_tile, dv_tile)
          transform_uv('nudge') { |du, dv, c| [c[0] + du - du_tile.to_f, c[1] + dv - dv_tile.to_f] }
        end

        # Longest edge of the outer loop gives a natural "X" direction on the face.
        def face_frame(face)
          edge = face.outer_loop.edges.max_by(&:length)
          xa = edge.line[1].clone
          xa.normalize!
          ya = face.normal.cross(xa)
          ya.normalize!
          pts = face.outer_loop.vertices.map(&:position)
          o = pts.first
          xs = pts.map { |p| (p - o) % xa }
          ys = pts.map { |p| (p - o) % ya }
          [o, xa, ya, xs.min, xs.max, ys.min, ys.max]
        end

        # Stretch one texture tile exactly over the face.
        def fit
          run('fit') do |face, front|
            o, xa, ya, x0, x1, y0, y1 = face_frame(face)
            next false if (x1 - x0) < 1e-6 || (y1 - y0) < 1e-6
            p0 = o.offset(xa, x0).offset(ya, y0)
            p1 = o.offset(xa, x1).offset(ya, y0)
            p2 = o.offset(xa, x0).offset(ya, y1)
            apply(face, front, [p0, p1, p2], [[0, 0], [1, 0], [0, 1]])
          end
        end

        # Real-world size, aligned to the longest edge, starting at its corner.
        def align
          run('align') do |face, front|
            mat = front ? face.material : face.back_material
            tex = mat.texture
            o, xa, ya, x0, _x1, y0, _y1 = face_frame(face)
            p0 = o.offset(xa, x0).offset(ya, y0)
            apply(face, front, [p0, p0.offset(xa, tex.width), p0.offset(ya, tex.height)], [[0, 0], [1, 0], [0, 1]])
          end
        end

        # Reset to SketchUp's default mapping by repainting.
        def reset
          run('reset') do |face, front|
            if front
              m = face.material
              face.material = nil
              face.material = m
            else
              m = face.back_material
              face.back_material = nil
              face.back_material = m
            end
            true
          end
        end

        # Sample the mapping of one face and paste it on others (same plane mapping).
        def copy_mapping
          list = targets
          return UI.messagebox(I18n.t(:select_textured)) && false if list.empty?
          face, front = list.first
          pts, uvs = sample(face, front)
          @clip = { 'mat' => (front ? face.material : face.back_material), 'pts' => pts, 'uvs' => uvs }
          true
        end

        def paste_mapping
          return false unless @clip && !@clip['mat'].deleted?
          clip = @clip
          run('paste') do |face, front|
            if front
              face.material = clip['mat']
            else
              face.back_material = clip['mat']
            end
            plane = face.plane
            pts = clip['pts'].map { |p| p.project_to_plane(plane) }
            apply(face, front, pts, clip['uvs'])
          end
        end
      end
    end
  end
end
