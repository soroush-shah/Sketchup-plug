# frozen_string_literal: true
# Run: ruby plugin/test/exporter_test.rb   (optionally GLTF_TOOLS=<dir with node_modules/.bin> for validation + gltfpack)
require 'minitest/autorun'
require 'json'
require 'tmpdir'
require_relative 'sketchup_stub'
module SkpShare; VERSION = 'test'; end
require_relative '../skpshare/gltf_writer'
require_relative '../skpshare/exporter'
require_relative '../skpshare/manifest'
require_relative '../skpshare/jobs'

class ExporterTest < Minitest::Test
  include Sketchup

  def box_faces(defn, layer, mat = nil)
    p = ->(x, y, z) { Geom::Point3d.new(x, y, z) }
    [0, 20].each do |z|
      defn.entities << Face.new(layer, [p[0, 0, z], p[20, 0, z], p[20, 20, z], p[0, 20, z]], material: mat)
    end
    defn.entities << Edge.new(layer, p[0, 0, 0], p[20, 0, 0])
  end

  def build_model
    m = Model.new
    l0 = m.layers[0]
    furniture = Layer.new('Furniture')
    walls = Layer.new('Walls')
    hidden = Layer.new('Hidden', false)
    m.layers.push(furniture, walls, hidden)

    chair = ComponentDefinition.new('Chair')
    box_faces(chair, l0)
    m.definitions << chair
    red = Material.new('Red', [200, 0, 0])
    50.times do |i|
      inst = ComponentInstance.new(chair, Geom::Transformation.translation(i * 30, 0, 0), furniture)
      inst.material = red if i.even? # chair faces are unpainted → inherit instance material
      m.entities << inst
    end

    wall_def = ComponentDefinition.new('Group#1')
    def wall_def.group? = true
    brick = Material.new('Brick', [255, 255, 255], texture: 'brick.jpg')
    box_faces(wall_def, l0, brick)
    m.entities << Group.new(wall_def, Geom::Transformation.translation(0, 100, 0), walls)

    secret = ComponentDefinition.new('Secret')
    box_faces(secret, l0)
    m.entities << ComponentInstance.new(secret, Geom::Transformation.new, hidden)

    glass = Material.new('Glass', [100, 150, 255], alpha: 0.4)
    m.entities << Face.new(l0, [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(500, 0, 0), Geom::Point3d.new(500, 500, 0), Geom::Point3d.new(0, 500, 0)], material: glass)
    m.entities << SectionPlane.new([0, 0, 1, -50])
    m.entities.active_section_plane = m.entities.last

    cam = Camera.new(Geom::Point3d.new(100, -300, 200), Geom::Point3d.new(100, 0, 0), Geom::Vector3d.new(0, 0, 1))
    m.pages << Page.new('Front', cam, [furniture])
    m
  end

  def read_glb(path)
    data = File.binread(path)
    magic, version, total = data.unpack('a4VV')
    assert_equal 'glTF', magic
    assert_equal 2, version
    assert_equal data.bytesize, total
    jlen = data[12, 4].unpack1('V')
    JSON.parse(data[20, jlen])
  end

  def test_export_instances_tags_materials
    model = build_model
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'raw.glb')
      stats = SkpShare::Exporter.new(model, edges: true).export(out)
      json = read_glb(out)

      tag_nodes = json['nodes'].select { |n| n['name'].to_s.start_with?('tag:') }
      assert_equal ['tag:Furniture', 'tag:Hidden', 'tag:Untagged', 'tag:Walls'].sort, tag_nodes.map { |n| n['name'] }.sort
      hidden = tag_nodes.find { |n| n['name'] == 'tag:Hidden' }
      assert_equal false, hidden['extras']['visible']

      furniture = tag_nodes.find { |n| n['name'] == 'tag:Furniture' }
      assert_equal 50, furniture['children'].size
      meshes = furniture['children'].map { |c| json['nodes'][c]['mesh'] }.uniq
      assert_equal 2, meshes.size, 'chair geometry reused: one mesh per inherited material (red / default)'

      names = json['materials'].map { |m| m['name'] }
      assert_includes names, 'Brick'
      assert json['materials'].find { |m| m['name'] == 'Brick' }['pbrMetallicRoughness']['baseColorTexture']
      assert_equal 'BLEND', json['materials'].find { |m| m['name'] == 'Glass' }['alphaMode']
      assert_equal 'Furniture', json['materials'].find { |m| m['name'] == 'Red' }['extras']['tag']
      assert_equal false, json['materials'].find { |m| m.dig('extras', 'tag') == 'Hidden' }['extras']['tagVisible']
      assert json['meshes'].any? { |m| m['primitives'].any? { |p| p['mode'] == 1 } }, 'edges exported as lines'
      assert_equal 53, stats[:instances] + 1 # 50 chairs + wall + secret + root
      assert_equal 1, json['images'].size

      manifest = SkpShare::Manifest.build(model, stats, {})
      assert_equal 'mm', manifest['units']['length']
      assert_equal 'Front', manifest['scenes'][0]['name']
      assert_equal ['Furniture'], manifest['scenes'][0]['hidden_tags']
      sp = manifest['section_planes'][0]
      assert_equal [0.0, 1.0, -0.0], sp['normal']
      assert_in_delta 50 * 0.0254, sp['point'][1], 1e-6
      assert sp['active']
      assert_equal 'Chair', manifest['bom'][0]['name']
      assert_equal 50, manifest['bom'][0]['count']

      tools = ENV['GLTF_TOOLS']
      next unless tools

      report = JSON.parse(`node -e "const v=require('#{tools}/node_modules/gltf-validator');v.validateBytes(new Uint8Array(require('fs').readFileSync('#{out}'))).then(r=>console.log(JSON.stringify(r.issues)))"`)
      assert_equal 0, report['numErrors'], report['messages'].select { |m| m['severity'].zero? }.inspect
      packed = File.join(dir, 'full.glb')
      ENV['SKPSHARE_GLTFPACK'] = File.join(tools, 'node_modules/.bin/gltfpack')
      ok = nil
      SkpShare::Compressor.run(out, packed, preset: 'balanced') { |r, _msg| ok = r }
      assert ok, 'gltfpack succeeded'
      pj = read_glb(packed)
      puts "\n  raw #{File.size(out)} B → packed #{File.size(packed)} B; extensions: #{pj['extensionsUsed']}"
      tags = pj['materials'].map { |mt| mt.dig('extras', 'tag') }.uniq.sort
      assert_equal %w[Furniture Hidden Untagged Walls], tags, 'tags survive gltfpack via material extras'
      assert_includes pj['extensionsUsed'], 'EXT_meshopt_compression'
      assert_includes pj['extensionsUsed'], 'EXT_mesh_gpu_instancing'
      assert pj['nodes'].size < 20, "nodes merged/instanced (#{pj['nodes'].size})"
    end
  end

  def test_gzipper_and_hash
    Dir.mktmpdir do |dir|
      src = File.join(dir, 'a.skp')
      File.binwrite(src, 'SketchUp ' * 100_000)
      res = nil
      SkpShare::Gzipper.run(src, "#{src}.gz") { |sha, orig| res = [sha, orig] }
      assert_equal 900_000, res[1]
      assert_equal Digest::SHA256.file("#{src}.gz").hexdigest, res[0]
      assert_equal File.binread(src), Zlib.gunzip(File.binread("#{src}.gz"))
      assert File.size("#{src}.gz") < 20_000
    end
  end
end
