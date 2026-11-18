# frozen_string_literal: true
# Converts the active SketchUp model to GLB.
#
# Size strategy:
#  * Each ComponentDefinition is written ONCE as a mesh; every instance is just a node
#    with a transform. gltfpack later turns repeats into GPU instancing.
#  * Geometry is flattened under one top-level node per Tag ("tag:<name>"), so the viewer can
#    toggle tags while gltfpack is free to merge everything else into few draw calls.
#  * Textures are written once per material.
require 'fileutils'

module SkpShare
  class Exporter
    INCH_TO_M = 0.0254
    # SketchUp is Z-up in inches; glTF is Y-up in meters. Column-major matrix.
    ROOT_MATRIX = [
      INCH_TO_M, 0, 0, 0,
      0, 0, -INCH_TO_M, 0,
      0, INCH_TO_M, 0, 0,
      0, 0, 0, 1
    ].freeze
    UNTAGGED = 'Untagged'

    attr_reader :stats

    # options: :edges (bool), :hidden_tags (bool, include geometry on hidden tags), :progress (proc(msg))
    def initialize(model, options = {})
      @model = model
      @opt = { edges: true, hidden_tags: true }.merge(options)
      @w = GltfWriter.new
      @mesh_cache = {}
      @materials = {}
      @tag_nodes = {}
      @texture_files = {}
      @stats = Hash.new(0)
      @tex_dir = File.join(Sketchup.temp_dir, "skpshare_tex_#{Process.pid}_#{Time.now.to_i}")
      FileUtils.mkdir_p(@tex_dir)
      @default_layer = model.layers[0]
    end

    def export(path)
      @root = @w.add_node(name: 'SketchUpModel', matrix: ROOT_MATRIX, root: true)
      @edge_materials = {}
      walk(@model.entities, Geom::Transformation.new, nil, UNTAGGED, 0)
      @stats[:bytes] = @w.write(path)
      @stats[:tags] = @tag_nodes.keys
      @stats
    ensure
      FileUtils.rm_rf(@tex_dir)
    end

    private

    def progress(msg)
      @opt[:progress]&.call(msg)
    end

    def tag_name(layer)
      return nil if layer.nil? || layer == @default_layer

      layer.respond_to?(:display_name) ? layer.display_name : layer.name
    end

    def tag_node(name)
      @tag_nodes[name] ||= begin
        layer = name == UNTAGGED ? nil : @model.layers[name]
        visible = layer.nil? || layer.visible?
        n = @w.add_node(name: "tag:#{name}", extras: { 'tag' => name, 'visible' => visible })
        @w.add_child(@root, n)
        n
      end
    end

    def visible_layer?(layer)
      @opt[:hidden_tags] || layer.nil? || layer.visible?
    end

    def walk(entities, transform, inherited_mat, tag, depth)
      return if depth > 64

      # Faces/edges of this entities collection, bucketed by their own tag.
      buckets = Hash.new { |h, k| h[k] = { faces: [], edges: [] } }
      instances = []
      entities.each do |e|
        case e
        when Sketchup::Face
          next if e.hidden? || !visible_layer?(e.layer)

          buckets[tag_name(e.layer)][:faces] << e
        when Sketchup::Edge
          next unless @opt[:edges]
          next if e.hidden? || e.soft? || e.smooth? || !visible_layer?(e.layer)

          buckets[tag_name(e.layer)][:edges] << e
        when Sketchup::Group, Sketchup::ComponentInstance
          next if e.hidden? || !visible_layer?(e.layer)

          instances << e
        end
      end

      parent = entities.parent
      owner_id = parent.is_a?(Sketchup::Model) ? 0 : parent.entityID
      matrix = transform.to_a
      buckets.each do |layer_name, geo|
        # Only instances that actually show the inherited (instance) material need their own mesh copy.
        inherits = geo[:faces].any? { |f| f.material.nil? && f.back_material.nil? }
        effective_tag = layer_name || tag
        key = [owner_id, inherits ? inherited_mat&.entityID : nil, effective_tag]
        mesh = @mesh_cache.fetch(key) { @mesh_cache[key] = build_mesh(geo[:faces], geo[:edges], inherited_mat, effective_tag) }
        next unless mesh

        node = @w.add_node(mesh: mesh, matrix: matrix)
        @w.add_child(tag_node(effective_tag), node)
        @stats[:nodes] += 1
      end

      instances.each do |inst|
        @stats[:instances] += 1
        progress("Exporting… #{@stats[:instances]} groups/components") if (@stats[:instances] % 200).zero?
        mat = inst.material || inherited_mat
        child_tag = tag_name(inst.layer) || tag
        walk(inst.definition.entities, transform * inst.transformation, mat, child_tag, depth + 1)
      end
    end

    def build_mesh(faces, edges, inherited_mat, tag)
      by_mat = Hash.new { |h, k| h[k] = { positions: [], normals: [], uvs: [], indices: [], textured: false } }
      faces.each do |f|
        mat = f.material
        back = false
        if mat.nil? && f.back_material
          mat = f.back_material
          back = true
        end
        mat ||= inherited_mat
        textured = mat&.texture ? true : false
        bucket = by_mat[mat]
        bucket[:textured] = textured
        add_face(bucket, f, textured, back)
        @stats[:faces] += 1
      end

      prims = by_mat.map do |mat, b|
        { positions: b[:positions], normals: b[:normals], uvs: b[:textured] ? b[:uvs] : nil,
          indices: b[:indices], material: material_index(mat, tag), mode: GltfWriter::MODE_TRIANGLES }
      end

      unless edges.empty?
        pos = []
        idx = []
        edges.each do |e|
          a = e.start.position
          b = e.end.position
          base = pos.size / 3
          pos.push(a.x.to_f, a.y.to_f, a.z.to_f, b.x.to_f, b.y.to_f, b.z.to_f)
          idx.push(base, base + 1)
          @stats[:edges] += 1
        end
        prims << { positions: pos, indices: idx, material: edge_material(tag), mode: GltfWriter::MODE_LINES }
      end
      @w.add_mesh(prims)
    end

    def add_face(b, face, textured, back)
      flags = 4 # normals
      flags |= (back ? 2 : 1) if textured # UVQ back/front
      mesh = face.mesh(flags)
      base = b[:positions].size / 3
      n = mesh.count_points
      (1..n).each do |i|
        p = mesh.point_at(i)
        b[:positions].push(p.x.to_f, p.y.to_f, p.z.to_f)
        nv = mesh.normal_at(i)
        nv = nv.reverse if back
        b[:normals].push(nv.x.to_f, nv.y.to_f, nv.z.to_f)
        if textured
          uvq = mesh.uv_at(i, !back)
          q = uvq.z.to_f.zero? ? 1.0 : uvq.z.to_f
          b[:uvs].push(uvq.x.to_f / q, 1.0 - (uvq.y.to_f / q))
        end
      end
      mesh.polygons.each do |poly|
        tri = poly.map { |v| v.abs - 1 + base }
        tri = tri.reverse if back
        # face.mesh always returns triangles, but be defensive with fans.
        (1...(tri.size - 1)).each { |k| b[:indices].push(tri[0], tri[k], tri[k + 1]) }
      end
    end

    def tag_extras(tag)
      layer = tag == UNTAGGED ? nil : @model.layers[tag]
      tag_node(tag)
      { 'tag' => tag, 'tagVisible' => layer.nil? || layer.visible? }
    end

    def edge_material(tag)
      @edge_materials[tag] ||= @w.add_material(name: 'Edges', color: [0.05, 0.05, 0.05, 1.0], unlit: true,
                                               extras: tag_extras(tag).merge('edges' => true))
    end

    def material_index(mat, tag)
      return default_material(tag) if mat.nil?

      @materials.fetch([mat, tag]) do
        c = mat.color
        rgba = [srgb_to_linear(c.red), srgb_to_linear(c.green), srgb_to_linear(c.blue), mat.alpha.to_f]
        img = nil
        if mat.texture
          ext = mat.texture.filename.to_s.downcase.end_with?('.png') ? 'png' : 'jpg'
          ext = 'png' if mat.alpha < 1.0
          img = @texture_files[mat] ||= begin
            path = File.join(@tex_dir, "t#{@texture_files.size}.#{ext}")
            mat.texture.write(path, true) # colorized
            @stats[:textures] += 1
            path
          rescue StandardError
            nil
          end
        end
        name = mat.respond_to?(:display_name) ? mat.display_name : mat.name
        @materials[[mat, tag]] = @w.add_material(name: name, color: rgba, image_path: img, extras: tag_extras(tag))
      end
    end

    def default_material(tag)
      @materials[[:default, tag]] ||= @w.add_material(name: 'Default', color: [0.85, 0.85, 0.85, 1.0], extras: tag_extras(tag))
    end

    def srgb_to_linear(c)
      v = c.to_f / 255.0
      (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4).round(4)
    end
  end
end
