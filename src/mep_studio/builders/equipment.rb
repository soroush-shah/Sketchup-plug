# frozen_string_literal: true

require 'json'

module MEPStudio
  # Parametric component definitions: fan coils, air terminals, sprinkler
  # heads, light fixtures. Every definition carries a JSON list of
  # "connectors" ({name, pos[mm], dir, size, system}) used for snapping
  # ducts / pipes and for the bill of quantities.
  module Equipment
    module_function

    # ------------------------------------------------------------ helpers
    def box(ents, x0, y0, z0, x1, y1, z1, mat = nil)
      g = ents.add_group
      e = g.entities
      pts = [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0]].map { |p| Util.a_pt(p.map { |c| Util.mm(c) }) }
      f = e.add_face(pts)
      hgt = Util.mm(z1 - z0)
      f.pushpull(f.normal.z < 0 ? -hgt : hgt)
      g.material = mat if mat
      g
    end

    def cylinder(ents, center_mm, dir, dia_mm, len_mm, mat = nil, segs = 16)
      g = ents.add_group
      e = g.entities
      c = Util.a_pt(center_mm.map { |v| Util.mm(v) })
      dv = Util.a_vec(dir)
      edges = e.add_circle(c, dv, Util.mm(dia_mm) / 2.0, segs)
      f = e.add_face(edges)
      dist = Util.mm(len_mm)
      f.pushpull(f.normal.dot(dv) < 0 ? -dist : dist)
      Util.soften(e)
      g.material = mat if mat
      g
    end

    def mats
      {
        casing: Util.plain_material('MEP_Casing', [215, 218, 222]),
        dark: Util.plain_material('MEP_Grille', [70, 72, 78]),
        copper: Util.plain_material('MEP_Copper', [190, 110, 60]),
        white: Util.plain_material('MEP_White', [245, 245, 245]),
        chrome: Util.plain_material('MEP_Chrome', [200, 200, 210]),
        red: Util.plain_material('MEP_SprinklerBulb', [230, 30, 30]),
        light: Util.plain_material('MEP_LightPanel', [255, 252, 225])
      }
    end

    def find_definition(name, sig)
      defs = Util.model.definitions
      defs.each do |d|
        return d if d.get_attribute(DICT, 'sig') == sig && d.entities.size > 0
      end
      nil
    end

    def new_definition(name, sig, attrs)
      d = Util.model.definitions.add(name)
      Util.set_attrs(d, attrs.merge('sig' => sig))
      d
    end

    def connectors(defn)
      raw = defn.get_attribute(DICT, 'connectors')
      raw ? JSON.parse(raw) : []
    end

    # Connectors of an instance in world (or given) coordinates (inches).
    def world_connectors(inst, tr = nil)
      tr ||= inst.transformation
      connectors(inst.definition).map do |c|
        pos = Util.a_pt(c['pos'].map { |v| Util.mm(v) }).transform(tr)
        dir = Util.a_vec(c['dir']).transform(tr)
        dir.normalize! if dir.length > 0
        c.merge('wpos' => Util.pt_a(pos), 'wdir' => Util.pt_a(dir))
      end
    end

    # ------------------------------------------------------------ fan coil
    def fcu_definition(model_name, hand = 'Right')
      spec = Settings.fcu_catalog[model_name]
      raise "Unknown fan coil model: #{model_name}" unless spec
      sig = JSON.generate(['fcu', model_name, hand, spec])
      d = find_definition(model_name, sig)
      return d if d

      d = new_definition("MEP #{model_name} (#{hand[0]})", sig,
                         'type' => 'fcu', 'model' => model_name, 'hand' => hand,
                         'cfm' => spec['cfm'], 'fcu_type' => spec['type'])
      cons = case spec['type']
             when 'cassette' then build_cassette(d.entities, spec, hand)
             when 'floor' then build_floor_fcu(d.entities, spec, hand)
             else build_ducted(d.entities, spec, hand)
             end
      d.set_attribute(DICT, 'connectors', JSON.generate(cons))
      d.description = "Fan coil #{model_name} - #{spec['cfm']} CFM"
      d
    end

    # Origin: top centre of casing (hanging point). +Y = supply side.
    def build_ducted(ents, s, hand)
      m = mats
      l = s['L'].to_f
      dd = s['D'].to_f
      h = s['H'].to_f
      box(ents, -l / 2, -dd / 2, -h, l / 2, dd / 2, 0, m[:casing])
      cons = []
      if s['out']
        ow, oh = s['out'].map(&:to_f)
        ow = [ow, l - 40].min
        zc = s['type'] == 'exposed' ? -h + 10 : -h / 2
        if s['type'] == 'exposed'
          # Front grille on the underside / front face.
          box(ents, -ow / 2, dd / 2 - 120, -h - 5, ow / 2, dd / 2 - 20, -h, m[:dark])
          box(ents, -ow / 2, -dd / 2 + 20, -h - 5, ow / 2, -dd / 2 + 140, -h, m[:dark])
        else
          box(ents, -ow / 2, dd / 2, zc - oh / 2, ow / 2, dd / 2 + 100, zc + oh / 2, m[:casing])
          cons << { 'name' => 'Supply', 'system' => 'SA', 'pos' => [0, dd / 2 + 100, zc], 'dir' => [0, 1, 0], 'size' => [ow, oh] }
        end
      end
      if s['ret']
        rw, rh = s['ret'].map(&:to_f)
        rw = [rw, l - 20].min
        box(ents, -rw / 2, -dd / 2 - 30, -h + 15, rw / 2, -dd / 2, -h + 15 + rh, m[:dark])
        cons << { 'name' => 'Return', 'system' => 'RA', 'pos' => [0, -dd / 2 - 30, -h + 15 + rh / 2], 'dir' => [0, -1, 0], 'size' => [rw, rh] }
      end
      # Drain pan lip under the coil.
      box(ents, -l / 2 + 10, -dd / 2 + 40, -h - 15, l / 2 - 10, dd / 2 - 40, -h, m[:casing])
      cons + pipe_stubs(ents, s, hand, l / 2, [-dd / 2 + 120, -dd / 2 + 200], [-h / 2 + 30, -h / 2 - 30], -h + 20, m)
    end

    # Coil connections leaving the hand side (+X right, -X left).
    def pipe_stubs(ents, s, hand, half_l, ys, zs, z_drain, m)
      sx = hand.to_s.start_with?('L') ? -1 : 1
      od = Catalog::PIPE_OD[s['pipe'].to_i] || 26.9
      odd = Catalog::PIPE_OD[s['drain'].to_i] || 26.9
      len = 120.0
      x0 = sx * half_l
      cons = []
      [['CHWS', ys[0], zs[0]], ['CHWR', ys[1], zs[1]]].each do |sys, y, z|
        cylinder(ents, [x0, y, z], [sx, 0, 0], od, len, m[:copper])
        cons << { 'name' => sys, 'system' => sys, 'pos' => [x0 + sx * len, y, z], 'dir' => [sx, 0, 0], 'size' => [s['pipe'].to_i] }
      end
      yd = ys[1] + 120
      cylinder(ents, [x0, yd, z_drain], [sx, 0, 0], odd, len, m[:white])
      cons << { 'name' => 'Drain', 'system' => 'CD', 'pos' => [x0 + sx * len, yd, z_drain], 'dir' => [sx, 0, 0], 'size' => [s['drain'].to_i] }
      cons
    end

    def build_cassette(ents, s, hand)
      m = mats
      l = s['L'].to_f
      h = s['H'].to_f
      pn = (s['panel'] || l + 50).to_f
      box(ents, -l / 2, -l / 2, -h, l / 2, l / 2, 0, m[:casing])
      box(ents, -pn / 2, -pn / 2, -h - 30, pn / 2, pn / 2, -h, m[:white])
      # four supply slots + central return grille
      sl = pn * 0.6
      g = 60.0
      off = pn / 2 - 80
      box(ents, -sl / 2, off - g, -h - 32, sl / 2, off, -h - 30, m[:dark])
      box(ents, -sl / 2, -off, -h - 32, sl / 2, -off + g, -h - 30, m[:dark])
      box(ents, off - g, -sl / 2, -h - 32, off, sl / 2, -h - 30, m[:dark])
      box(ents, -off, -sl / 2, -h - 32, -off + g, sl / 2, -h - 30, m[:dark])
      r = pn * 0.22
      box(ents, -r, -r, -h - 32, r, r, -h - 30, m[:dark])
      pipe_stubs(ents, s, hand, l / 2, [-l / 2 + 100, -l / 2 + 170], [-60, -60], -h + 40, m)
    end

    # Origin: bottom, back, centre. Front = +Y. Outlet on top.
    def build_floor_fcu(ents, s, hand)
      m = mats
      l = s['L'].to_f
      dd = s['D'].to_f
      h = s['H'].to_f
      box(ents, -l / 2, 0, 0, l / 2, dd, h, m[:white])
      ow, oh = (s['out'] || [l - 300, 100]).map(&:to_f)
      box(ents, -ow / 2, dd - 20 - oh, h, ow / 2, dd - 20, h + 3, m[:dark])
      box(ents, -ow / 2, dd, 60, ow / 2, dd + 3, 260, m[:dark])
      sx = hand.to_s.start_with?('L') ? -1 : 1
      od = Catalog::PIPE_OD[s['pipe'].to_i] || 26.9
      cons = []
      [['CHWS', 60], ['CHWR', 130]].each do |sys, x|
        cylinder(ents, [sx * (l / 2 - x), 60, 0], [0, 0, -1], od, 100, m[:copper])
        cons << { 'name' => sys, 'system' => sys, 'pos' => [sx * (l / 2 - x), 60, -100], 'dir' => [0, 0, -1], 'size' => [s['pipe'].to_i] }
      end
      cylinder(ents, [sx * (l / 2 - 200), 60, 0], [0, 0, -1], Catalog::PIPE_OD[s['drain'].to_i] || 26.9, 100, m[:white])
      cons << { 'name' => 'Drain', 'system' => 'CD', 'pos' => [sx * (l / 2 - 200), 60, -100], 'dir' => [0, 0, -1], 'size' => [s['drain'].to_i] }
      cons
    end

    # ------------------------------------------------------ air terminals
    # Origin: centre of ceiling plane. Face is flush with z=0, neck goes up.
    def terminal_definition(model_name)
      spec = Catalog::TERMINALS[model_name]
      raise "Unknown terminal #{model_name}" unless spec
      sig = JSON.generate(['terminal', model_name, spec])
      d = find_definition(model_name, sig)
      return d if d
      sys = spec['kind'] == 'grille' ? 'RA' : 'SA'
      d = new_definition("MEP #{model_name}", sig, 'type' => 'terminal', 'model' => model_name, 'system' => sys)
      m = mats
      e = d.entities
      neck_h = 150.0
      cons = []
      case spec['kind']
      when 'square', 'round'
        f = spec['face'].to_f
        if spec['kind'] == 'round'
          cylinder(e, [0, 0, -15], [0, 0, 1], f, 15, m[:white], 32)
        else
          box(e, -f / 2, -f / 2, -15, f / 2, f / 2, 0, m[:white])
          box(e, -f * 0.3, -f * 0.3, -17, f * 0.3, f * 0.3, -15, m[:dark])
        end
        cylinder(e, [0, 0, 0], [0, 0, 1], spec['neck'].to_f, neck_h, m[:casing], 24)
        cons << { 'name' => 'Neck', 'system' => sys, 'pos' => [0, 0, neck_h], 'dir' => [0, 0, 1], 'size' => [spec['neck'].to_f], 'shape' => 'round' }
      else
        fw, fh = spec['face'].map(&:to_f)
        nw, nh = spec['neck'].map(&:to_f)
        box(e, -fw / 2, -fh / 2, -15, fw / 2, fh / 2, 0, m[:white])
        box(e, -nw / 2 + 10, -nh / 2 + 10, -17, nw / 2 - 10, nh / 2 - 10, -15, m[:dark])
        box(e, -nw / 2, -nh / 2, 0, nw / 2, nh / 2, neck_h, m[:casing])
        cons << { 'name' => 'Neck', 'system' => sys, 'pos' => [0, 0, neck_h], 'dir' => [0, 0, 1], 'size' => [nw, nh], 'shape' => 'rect' }
      end
      d.set_attribute(DICT, 'connectors', JSON.generate(cons))
      d
    end

    # ---------------------------------------------------- sprinkler head
    # Origin: pipe connection (1/2" thread).
    def sprinkler_definition(head = 'Pendent', k_factor = 80)
      sig = JSON.generate(['sprinkler', head, k_factor])
      d = find_definition(head, sig)
      return d if d
      d = new_definition("MEP Sprinkler #{head} K#{k_factor.to_i}", sig,
                         'type' => 'sprinkler', 'head' => head, 'k_factor' => k_factor, 'system' => 'SPR')
      m = mats
      e = d.entities
      dir = case head
            when 'Upright' then [0, 0, 1]
            when 'Sidewall' then [0, 1, 0]
            else [0, 0, -1]
            end
      p = ->(t) { dir.map { |c| c * t } }
      cylinder(e, [0, 0, 0], dir, 22, 20, m[:chrome], 12)
      cylinder(e, p.call(20), dir, 8, 25, m[:red], 8)
      cylinder(e, p.call(45), dir, 32, 3, m[:chrome], 16)
      if head == 'Pendent'
        # escutcheon (sits at the ceiling)
        cylinder(e, [0, 0, -10], [0, 0, -1], 70, 4, m[:white], 24)
      end
      d.set_attribute(DICT, 'connectors',
                      JSON.generate([{ 'name' => 'Inlet', 'system' => 'SPR', 'pos' => [0, 0, 0], 'dir' => dir.map(&:-@), 'size' => [15] }]))
      d
    end

    # ------------------------------------------------------- light fixture
    def light_definition(model_name)
      spec = Catalog::LIGHTS[model_name]
      raise "Unknown light #{model_name}" unless spec
      sig = JSON.generate(['light', model_name, spec])
      d = find_definition(model_name, sig)
      return d if d
      d = new_definition("MEP Light #{model_name}", sig, 'type' => 'light', 'model' => model_name, 'system' => 'LIGHT')
      m = mats
      e = d.entities
      if spec['d']
        cylinder(e, [0, 0, -5], [0, 0, 1], spec['d'].to_f + 20, 5, m[:white], 24)
        cylinder(e, [0, 0, -6], [0, 0, 1], spec['d'].to_f - 20, 1, m[:light], 24)
        cylinder(e, [0, 0, 0], [0, 0, 1], spec['d'].to_f - 10, spec['h'].to_f, m[:casing], 24)
      else
        w = spec['w'].to_f
        l = spec['l'].to_f
        box(e, -l / 2, -w / 2, -5, l / 2, w / 2, spec['h'].to_f, m[:white])
        box(e, -l / 2 + 15, -w / 2 + 15, -7, l / 2 - 15, w / 2 - 15, -5, m[:light])
      end
      d.set_attribute(DICT, 'connectors', '[]')
      d
    end

    # Insert + tag an instance.
    def place(entities, defn, tr, system = 'EQ', extra = {})
      inst = entities.add_instance(defn, tr)
      inst.layer = Util.system_tag(system)
      Util.set_attrs(inst, { 'type' => defn.get_attribute(DICT, 'type'), 'system' => system }.merge(extra))
      inst
    end
  end
end
