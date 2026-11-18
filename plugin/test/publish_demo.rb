# frozen_string_literal: true
# Builds a demo "house" with the SketchUp API stub, exports + compresses it with the plugin code
# and publishes it to a running SkpShare server with the plugin's ApiClient (Net::HTTP transport).
# Usage: ruby publish_demo.rb <server-url> <token> [gltfpack-path]
require 'json'
require 'tmpdir'
require 'fileutils'
require_relative 'sketchup_stub'
module SkpShare; VERSION = 'demo'; end
require_relative '../skpshare/gltf_writer'
require_relative '../skpshare/exporter'
require_relative '../skpshare/manifest'
require_relative '../skpshare/jobs'
require_relative '../skpshare/api_client'

include Sketchup
P = ->(x, y, z) { Geom::Point3d.new(x, y, z) }

def box(ents, layer, x0, y0, z0, x1, y1, z1, mat = nil)
  c = [P[x0, y0, z0], P[x1, y0, z0], P[x1, y1, z0], P[x0, y1, z0], P[x0, y0, z1], P[x1, y0, z1], P[x1, y1, z1], P[x0, y1, z1]]
  [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]].each do |f|
    ents << Face.new(layer, f.map { |i| c[i] }, material: mat)
  end
  [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]].each do |a, b|
    ents << Edge.new(layer, c[a], c[b])
  end
end

def build
  m = Model.new
  l0 = m.layers[0]
  structure = Layer.new('Structure'); furniture = Layer.new('Furniture'); roof = Layer.new('Roof')
  m.layers.push(structure, furniture, roof)
  concrete = Material.new('Concrete', [190, 190, 185]); wall = Material.new('Plaster', [240, 236, 228], texture: 'plaster.png')
  wood = Material.new('Oak', [170, 120, 70]); fabric = Material.new('Fabric', [60, 90, 160]); glass = Material.new('Glass', [150, 200, 230], alpha: 0.35)
  red = Material.new('Red', [200, 60, 50])
  # inches: house 400" x 320", walls 8" thick, 110" high
  shell = ComponentDefinition.new('Shell')
  box(shell.entities, l0, 0, 0, -8, 400, 320, 0, concrete)
  box(shell.entities, l0, 0, 0, 0, 400, 8, 110, wall)
  box(shell.entities, l0, 0, 312, 0, 400, 320, 110, wall)
  box(shell.entities, l0, 0, 8, 0, 8, 312, 110, wall)
  box(shell.entities, l0, 392, 8, 0, 400, 140, 110, wall)
  box(shell.entities, l0, 392, 200, 0, 400, 312, 110, wall)
  box(shell.entities, l0, 396, 140, 0, 397, 200, 110, glass)
  box(shell.entities, l0, 200, 8, 0, 206, 200, 110, wall)
  m.definitions << shell
  m.entities << Group.new(shell, Geom::Transformation.new, structure)
  slab = ComponentDefinition.new('Roof slab')
  box(slab.entities, l0, -12, -12, 110, 412, 332, 118, concrete)
  m.definitions << slab
  m.entities << Group.new(slab, Geom::Transformation.new, roof)
  chair = ComponentDefinition.new('Chair')
  box(chair.entities, l0, 0, 0, 16, 18, 18, 19)
  [[0, 0], [0, 15], [15, 0], [15, 15]].each { |x, y| box(chair.entities, l0, x, y, 0, x + 3, y + 3, 16) }
  box(chair.entities, l0, 0, 15, 19, 18, 18, 36)
  m.definitions << chair
  table = ComponentDefinition.new('Table')
  box(table.entities, l0, 0, 0, 28, 72, 36, 30, wood)
  [[0, 0], [0, 33], [69, 0], [69, 33]].each { |x, y| box(table.entities, l0, x, y, 0, x + 3, y + 3, 28, wood) }
  m.definitions << table
  2.times do |t|
    tx = 40 + t * 200
    m.entities << ComponentInstance.new(table, Geom::Transformation.translation(tx, 120, 0), furniture)
    6.times do |i|
      x = tx + (i % 3) * 26
      y = i < 3 ? 95 : 160
      inst = ComponentInstance.new(chair, Geom::Transformation.translation(x, y, 0), furniture)
      inst.material = i.even? ? fabric : red
      m.entities << inst
    end
  end
  if ENV['DEMO_V2'] # second version: an extra room divider and a sofa
    box(shell.entities, l0, 300, 200, 0, 306, 312, 110, wall)
    sofa = ComponentDefinition.new('Sofa')
    box(sofa.entities, l0, 0, 0, 0, 84, 36, 30, Material.new('Green', [60, 140, 90]))
    m.definitions << sofa
    m.entities << ComponentInstance.new(sofa, Geom::Transformation.translation(220, 250, 0), furniture)
  end
  m.entities << SectionPlane.new([0, 0, -1, 60])
  eye = ->(x, y, z) { Geom::Point3d.new(x, y, z) }
  m.pages << Page.new('Exterior', Camera.new(eye[900, -500, 500], eye[200, 160, 40], Geom::Vector3d.new(0, 0, 1)), [])
  m.pages << Page.new('Interior', Camera.new(eye[60, 40, 64], eye[300, 250, 40], Geom::Vector3d.new(0, 0, 1), true, 60.0), [roof])
  m.pages << Page.new('Plan', Camera.new(eye[200, 160, 1200], eye[200, 160.1, 0], Geom::Vector3d.new(0, 1, 0)), [roof])
  def m.title = 'Demo House'
  m
end

server, token, gltfpack, existing_model = ARGV
ENV['SKPSHARE_GLTFPACK'] = gltfpack if gltfpack
model = build
dir = Dir.mktmpdir
raw = File.join(dir, 'raw.glb')
stats = SkpShare::Exporter.new(model).export(raw)
manifest = SkpShare::Manifest.build(model, stats, {})
File.write(File.join(dir, 'manifest.json'), JSON.generate(manifest))
files = [{ path: File.join(dir, 'manifest.json'), kind: 'manifest' }]
full = File.join(dir, 'full.glb')
SkpShare::Compressor.run(raw, full, preset: 'balanced') { |ok, msg| puts(ok ? "compressed #{File.size(raw)} -> #{File.size(full)}" : "compress failed: #{msg}") }
files << { path: File.exist?(full) ? full : raw, kind: 'full', filename: 'model.glb' }
skp = File.join(dir, 'Demo House.skp')
File.binwrite(skp, ('SketchUp demo payload ' * 50_000))
SkpShare::Gzipper.run(skp, "#{skp}.gz") { |sha, orig| files << { path: "#{skp}.gz", kind: 'skp', filename: 'Demo House.skp', gzipped: true, original_size: orig, sha256: sha } }

client = SkpShare::ApiClient.new(server, token, SkpShare::NetHttpTransport.new)
call = ->(m, p, b = nil) { r = nil; client.call(m, p, b) { |d, e| raise e if e; r = d }; r }
mdl = if existing_model
        { 'id' => existing_model.to_i }
      else
        project = call.('POST', '/api/projects', { name: 'Demo project' })
        call.('POST', '/api/models', { project_id: project['id'], name: 'Demo House' })
      end
ver = call.('POST', "/api/models/#{mdl['id']}/versions", { note: ENV['DEMO_V2'] ? 'Added divider and sofa' : 'First issue', stats: stats.reject { |k, _| k == :tags } })
files.each do |f|
  f[:sha256] ||= Digest::SHA256.file(f[:path]).hexdigest
  client.upload_file(f[:path], version_id: ver['id'], kind: f[:kind], filename: f[:filename] || File.basename(f[:path]), sha256: f[:sha256],
                     gzipped: f[:gzipped], original_size: f[:original_size],
                     progress: ->(s, t) { print "\r#{f[:kind]} #{s}/#{t}" }) { |_r, e| raise e if e }
  puts
end
res = call.('POST', "/api/versions/#{ver['id']}/finalize")
puts JSON.generate(res)
