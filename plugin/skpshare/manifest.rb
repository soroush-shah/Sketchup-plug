# frozen_string_literal: true
# Builds manifest.json: scenes (cameras + hidden tags), tags, section planes, BOM, units, bounds.
# All positions are converted to the GLB space (meters, Y-up).
require 'json'

module SkpShare
  module Manifest
    module_function

    S = Exporter::INCH_TO_M

    def gl(p)
      [(p.x.to_f * S).round(5), (p.z.to_f * S).round(5), (-p.y.to_f * S).round(5)]
    end

    def glv(v)
      [v.x.to_f.round(6), v.z.to_f.round(6), -v.y.to_f.round(6)]
    end

    def layer_name(l)
      l.respond_to?(:display_name) ? l.display_name : l.name
    end

    def build(model, stats, scene_thumbs = {})
      bb = model.bounds
      {
        'format' => 1,
        'generator' => "SkpShare plugin #{SkpShare::VERSION}",
        'sketchup_version' => Sketchup.version,
        'title' => model.title.to_s.empty? ? 'Untitled' : model.title,
        'units' => units(model),
        'bounds' => { 'min' => gl(bb.min), 'max' => gl(bb.max) },
        'tags' => tags(model),
        'scenes' => scenes(model, scene_thumbs),
        'section_planes' => section_planes(model),
        'bom' => bom(model),
        'stats' => stats.reject { |k, _| k == :tags }.transform_keys(&:to_s),
        'created_at' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      }
    end

    def units(model)
      opts = model.options['UnitsOptions']
      lu = opts['LengthUnit'] # 0 in, 1 ft, 2 mm, 3 cm, 4 m
      { 'length' => %w[in ft mm cm m][lu] || 'mm', 'precision' => opts['LengthPrecision'].to_i }
    rescue StandardError
      { 'length' => 'mm', 'precision' => 0 }
    end

    def tags(model)
      model.layers.to_a.drop(1).map do |l|
        c = l.color
        { 'name' => layer_name(l), 'visible' => l.visible?, 'color' => format('#%02x%02x%02x', c.red, c.green, c.blue) }
      end
    end

    def camera_hash(cam)
      h = { 'eye' => gl(cam.eye), 'target' => gl(cam.target), 'up' => glv(cam.up), 'perspective' => cam.perspective? }
      if cam.perspective?
        h['fov'] = cam.fov.to_f
      else
        h['height'] = (cam.height.to_f * S).round(4)
      end
      h
    end

    def scenes(model, thumbs)
      model.pages.to_a.map do |page|
        hidden = page.layers ? page.layers.map { |l| layer_name(l) } : nil
        {
          'name' => page.name, 'description' => page.description.to_s,
          'camera' => page.use_camera? ? camera_hash(page.camera) : nil,
          'hidden_tags' => page.use_hidden_layers? ? hidden : nil,
          'thumb' => thumbs[page.name]
        }
      end
    end

    def section_planes(model)
      out = []
      collect = lambda do |entities, tr, depth|
        return if depth > 16

        entities.each do |e|
          if e.is_a?(Sketchup::SectionPlane)
            a, b, c, d = e.get_plane
            normal = Geom::Vector3d.new(a, b, c)
            pt = Geom::Point3d.new(-a * d, -b * d, -c * d)
            n = normal.transform(tr)
            n.normalize!
            out << { 'name' => (e.respond_to?(:name) ? e.name.to_s : ''), 'point' => gl(pt.transform(tr)), 'normal' => glv(n),
                     'active' => entities.active_section_plane == e }
          elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            collect.call(e.definition.entities, tr * e.transformation, depth + 1)
          end
        end
      end
      collect.call(model.entities, Geom::Transformation.new, 0)
      out
    end

    # Bill of materials: component definitions with instance counts and sizes (mm).
    def bom(model)
      model.definitions.to_a.reject { |d| d.image? || d.group? }.map do |d|
        n = d.respond_to?(:count_used_instances) ? d.count_used_instances : d.instances.size
        next if n.zero?

        b = d.bounds
        { 'name' => d.name, 'description' => d.description.to_s, 'count' => n,
          'size_mm' => [b.width, b.height, b.depth].map { |v| (v.to_f * 25.4).round(1) } }
      end.compact.sort_by { |r| -r['count'] }
    end

    # Capture a JPEG of each scene's camera without touching tags/styles (restores the camera afterwards).
    def capture_scene_thumbs(model, dir, width = 320, height = 200)
      view = model.active_view
      c = view.camera
      original = Sketchup::Camera.new(c.eye, c.target, c.up, c.perspective?, c.perspective? ? c.fov : 35.0)
      original.height = c.height unless c.perspective?
      thumbs = {}
      model.pages.to_a.each_with_index do |page, i|
        next unless page.use_camera?

        view.camera = page.camera
        file = File.join(dir, "scene_#{i}.jpg")
        ok = view.write_image(filename: file, width: width, height: height, antialias: true, compression: 0.8)
        # Small JPEGs are embedded in the manifest as data URLs (no zip library in SketchUp Ruby).
        thumbs[page.name] = "data:image/jpeg;base64,#{[File.binread(file)].pack('m0')}" if ok && File.exist?(file)
      end
      view.camera = original
      thumbs
    rescue StandardError => e
      puts "SkpShare: scene thumbnails failed: #{e.message}"
      {}
    end
  end
end
