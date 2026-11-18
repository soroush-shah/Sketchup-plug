# frozen_string_literal: true
# Pure-Ruby glTF 2.0 binary (GLB) writer with no SketchUp dependency.
# Binary data is streamed to a temp file so very large models do not need to fit in memory.
require 'json'
require 'tempfile'

module SkpShare
  class GltfWriter
    FLOAT = 5126
    UINT16 = 5123
    UINT32 = 5125
    ARRAY_BUFFER = 34_962
    ELEMENT_ARRAY_BUFFER = 34_963
    MODE_LINES = 1
    MODE_TRIANGLES = 4

    attr_reader :json

    def initialize(generator: 'SkpShare SketchUp exporter')
      @json = {
        'asset' => { 'version' => '2.0', 'generator' => generator },
        'scene' => 0, 'scenes' => [{ 'nodes' => [] }],
        'nodes' => [], 'meshes' => [], 'materials' => [], 'accessors' => [],
        'bufferViews' => [], 'buffers' => [], 'images' => [], 'textures' => [], 'samplers' => []
      }
      @bin = Tempfile.new(['skpshare', '.bin'])
      @bin.binmode
      @bin_len = 0
    end

    # ------------------------------------------------------------------ public API

    # color: [r,g,b,a] 0..1. image_path: optional png/jpg. Returns material index.
    def add_material(name:, color: [0.8, 0.8, 0.8, 1.0], image_path: nil, double_sided: true, unlit: false, extras: nil)
      pbr = { 'baseColorFactor' => color.map { |c| c.to_f.round(4) }, 'metallicFactor' => 0.0, 'roughnessFactor' => 0.9 }
      if image_path && File.exist?(image_path)
        tex = add_texture(image_path)
        pbr['baseColorTexture'] = { 'index' => tex }
        pbr['baseColorFactor'] = [1.0, 1.0, 1.0, color[3].to_f.round(4)]
      end
      mat = { 'name' => name.to_s, 'pbrMetallicRoughness' => pbr, 'doubleSided' => double_sided }
      mat['alphaMode'] = 'BLEND' if color[3].to_f < 0.999
      mat['extras'] = extras if extras
      if unlit
        mat['extensions'] = { 'KHR_materials_unlit' => {} }
        use_extension('KHR_materials_unlit')
      end
      @json['materials'] << mat
      @json['materials'].size - 1
    end

    # primitives: [{ positions: [x,y,z,...], normals: [...]?, uvs: [...]?, indices: [...], material: idx, mode: 4 }]
    # Returns mesh index or nil when nothing to write.
    def add_mesh(primitives, name: nil)
      prims = primitives.reject { |p| p[:indices].nil? || p[:indices].empty? }.map { |p| build_primitive(p) }
      return nil if prims.empty?

      mesh = { 'primitives' => prims }
      mesh['name'] = name if name
      @json['meshes'] << mesh
      @json['meshes'].size - 1
    end

    # matrix: 16 floats column-major (or nil). Returns node index.
    def add_node(name: nil, mesh: nil, matrix: nil, children: nil, extras: nil, root: false)
      node = {}
      node['name'] = name if name
      node['mesh'] = mesh if mesh
      node['matrix'] = matrix.map { |v| v.to_f.round(9) } if matrix && !identity?(matrix)
      node['children'] = children if children && !children.empty?
      node['extras'] = extras if extras
      @json['nodes'] << node
      idx = @json['nodes'].size - 1
      @json['scenes'][0]['nodes'] << idx if root
      idx
    end

    def add_child(parent, child)
      (@json['nodes'][parent]['children'] ||= []) << child
    end

    def node(idx)
      @json['nodes'][idx]
    end

    def write(path)
      pad_bin
      @json['buffers'] = [{ 'byteLength' => @bin_len }] if @bin_len.positive?
      %w[images textures samplers bufferViews accessors materials meshes buffers].each do |k|
        @json.delete(k) if @json[k].empty?
      end
      json_str = JSON.generate(@json)
      json_str += ' ' * ((4 - json_str.bytesize % 4) % 4)
      total = 12 + 8 + json_str.bytesize + (@bin_len.positive? ? 8 + @bin_len : 0)
      @bin.flush
      @bin.rewind
      File.open(path, 'wb') do |f|
        f.write(['glTF', 2, total].pack('a4VV'))
        f.write([json_str.bytesize, 0x4E4F534A].pack('VV'))
        f.write(json_str)
        if @bin_len.positive?
          f.write([@bin_len, 0x004E4942].pack('VV'))
          IO.copy_stream(@bin, f)
        end
      end
      @bin.close!
      total
    end

    private

    def identity?(m)
      m.each_with_index.all? { |v, i| (v - ((i % 5).zero? ? 1.0 : 0.0)).abs < 1e-9 }
    end

    def use_extension(name)
      (@json['extensionsUsed'] ||= []) << name unless (@json['extensionsUsed'] || []).include?(name)
    end

    def build_primitive(p)
      pos = p[:positions]
      count = pos.size / 3
      attrs = { 'POSITION' => accessor(pos.pack('e*'), FLOAT, count, 'VEC3', ARRAY_BUFFER, minmax(pos)) }
      attrs['NORMAL'] = accessor(p[:normals].pack('e*'), FLOAT, count, 'VEC3', ARRAY_BUFFER) if p[:normals] && !p[:normals].empty?
      attrs['TEXCOORD_0'] = accessor(p[:uvs].pack('e*'), FLOAT, count, 'VEC2', ARRAY_BUFFER) if p[:uvs] && !p[:uvs].empty?
      idx = p[:indices]
      big = count > 65_535
      ia = accessor(idx.pack(big ? 'V*' : 'v*'), big ? UINT32 : UINT16, idx.size, 'SCALAR', ELEMENT_ARRAY_BUFFER)
      prim = { 'attributes' => attrs, 'indices' => ia, 'mode' => p[:mode] || MODE_TRIANGLES }
      prim['material'] = p[:material] if p[:material]
      prim
    end

    def minmax(pos)
      mn = [Float::INFINITY] * 3
      mx = [-Float::INFINITY] * 3
      pos.each_slice(3) do |v|
        3.times do |i|
          mn[i] = v[i] if v[i] < mn[i]
          mx[i] = v[i] if v[i] > mx[i]
        end
      end
      [mn, mx]
    end

    def accessor(bytes, ctype, count, type, target, mm = nil)
      view = buffer_view(bytes, target)
      acc = { 'bufferView' => view, 'componentType' => ctype, 'count' => count, 'type' => type }
      if mm
        acc['min'] = mm[0]
        acc['max'] = mm[1]
      end
      @json['accessors'] << acc
      @json['accessors'].size - 1
    end

    def buffer_view(bytes, target = nil)
      pad_bin
      view = { 'buffer' => 0, 'byteOffset' => @bin_len, 'byteLength' => bytes.bytesize }
      view['target'] = target if target
      @bin.write(bytes)
      @bin_len += bytes.bytesize
      @json['bufferViews'] << view
      @json['bufferViews'].size - 1
    end

    def pad_bin
      pad = (4 - @bin_len % 4) % 4
      return if pad.zero?

      @bin.write("\0" * pad)
      @bin_len += pad
    end

    def add_texture(path)
      @texture_cache ||= {}
      return @texture_cache[path] if @texture_cache.key?(path)

      if @json['samplers'].empty?
        @json['samplers'] << { 'magFilter' => 9729, 'minFilter' => 9987, 'wrapS' => 10_497, 'wrapT' => 10_497 }
      end
      data = File.binread(path)
      mime = data.start_with?("\x89PNG".b) ? 'image/png' : 'image/jpeg'
      view = buffer_view(data)
      @json['images'] << { 'bufferView' => view, 'mimeType' => mime }
      @json['textures'] << { 'sampler' => 0, 'source' => @json['images'].size - 1 }
      @texture_cache[path] = @json['textures'].size - 1
    end
  end
end
