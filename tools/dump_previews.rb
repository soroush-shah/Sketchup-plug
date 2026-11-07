# Dumps preview payloads for every pattern (used by the UI screenshot harness).
require 'tmpdir'
require 'json'
require_relative '../tests/mock_sketchup'
ROOT = File.expand_path('../src/banian_floor_studio', __dir__)
module BanianStudio; module FloorStudio; PATH = ROOT; VERSION = '1.0.0'; end; end
%w[core/geom2d core/patterns core/params core/region core/surface core/materials core/builder ui/dialog].each { |f| require File.join(ROOT, f) }
FS = BanianStudio::FloorStudio
class D; attr_reader :m; def initialize; @m = []; end; def execute_script(s); @m << JSON.parse(s[8..-2]); end; def visible?; true; end; end
d = D.new
FS::Studio.instance_variable_set(:@dlg, d)
model = Sketchup.active_model
%w[Oak\ Natural Walnut Grey\ Stone].zip([[196, 160, 112], [110, 78, 52], [150, 150, 146]]).each do |n, c|
  m = model.materials.add(n); m.color = Sketchup::Color.new(*c)
end
FS::Studio.on_ready
init = d.m.find { |x| x['type'] == 'init' }
out = { 'init' => init, 'previews' => {} }
pd = { 'grid' => { 'length' => 600, 'width' => 600, 'gap' => 3 }, 'brick' => { 'length' => 600, 'width' => 300, 'gap' => 3 },
       'wood' => { 'width' => 190, 'wood_min' => 600, 'wood_max' => 1800, 'gap' => 1 }, 'herringbone' => { 'length' => 600, 'width' => 100, 'gap' => 1 },
       'chevron' => { 'length' => 600, 'width' => 100, 'gap' => 1 }, 'basket' => { 'length' => 300, 'gap' => 2 },
       'hexagon' => { 'length' => 200, 'gap' => 3 }, 'hopscotch' => { 'length' => 600, 'small' => 300, 'gap' => 3 },
       'voronoi' => { 'length' => 500, 'gap' => 15 }, 'siding' => { 'length' => 3000, 'width' => 150, 'gap' => 0 } }
pd.each do |pat, v|
  d.m.clear
  FS::Studio.on_preview(v.merge('pattern' => pat, 'materials' => ['Oak Natural', 'Walnut'], 'weights' => [3, 1], 'shades' => 3))
  out['previews'][pat] = d.m.last
end
File.write(ARGV[0], JSON.generate(out))
