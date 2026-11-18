# frozen_string_literal: true

require 'json'

module MEPStudio
  # User defaults, persisted with Sketchup.write_default as JSON.
  # All lengths are millimetres.
  module Settings
    DEFAULTS = {
      'duct' => {
        'system' => 'SA', 'shape' => 'rect', 'width' => 400, 'height' => 250,
        'diameter' => 250, 'elevation' => 2900, 'elev_ref' => 'bottom',
        'elbow_radius' => 1.0, 'insulation' => 25, 'show_insulation' => false
      },
      'pipe' => {
        'system' => 'CHWS', 'dn' => 50, 'elevation' => 3000, 'elev_ref' => 'center',
        'elbow_radius' => 1.5, 'insulation' => 0
      },
      'tray' => { 'width' => 300, 'height' => 100, 'elevation' => 3100, 'elev_ref' => 'bottom' },
      'fcu' => {
        'model' => 'FCU-400 Ducted', 'mount' => 'ceiling', 'gap_to_slab' => 100,
        'bottom_elevation' => 2700, 'hand' => 'Right', 'rotation' => 0
      },
      'terminal' => { 'model' => 'Square Diffuser 600', 'ceiling_height' => 2700 },
      'sprinkler' => {
        'hazard' => 'Light', 'head' => 'Pendent', 'spacing' => 0, 'wall_min' => 100,
        'ceiling_height' => 2700, 'deflector' => 50, 'branch_above' => 250,
        'main_side' => 'Auto', 'k_factor' => 80
      },
      'light' => { 'model' => 'Panel 600x600', 'spacing' => 2400, 'ceiling_height' => 2700 },
      'clash' => {
        'clearance' => 25, 'check_arch' => true, 'check_mep' => true,
        'ignore_tags' => '', 'only_visible' => true, 'markers' => true
      },
      'fcu_catalog' => {}
    }.freeze

    @data = nil

    module_function

    def deep_merge(base, over)
      return base unless over.is_a?(Hash)
      res = base.dup
      over.each do |k, val|
        res[k] = res[k].is_a?(Hash) && val.is_a?(Hash) ? deep_merge(res[k], val) : val
      end
      res
    end

    def load
      raw = nil
      raw = Sketchup.read_default('MEPStudio', 'settings_json', nil) if defined?(Sketchup)
      user = raw ? (JSON.parse(raw) rescue {}) : {}
      @data = deep_merge(JSON.parse(JSON.generate(DEFAULTS)), user)
    end

    def data
      @data || load
    end

    def [](section)
      data[section]
    end

    def set(section, values)
      data[section] = (data[section] || {}).merge(values)
      save
    end

    def save
      Sketchup.write_default('MEPStudio', 'settings_json', JSON.generate(data)) if defined?(Sketchup)
    end

    def reset!
      @data = JSON.parse(JSON.generate(DEFAULTS))
      save
    end

    # Built-in fan coils + user added/overridden models.
    def fcu_catalog
      Catalog::FCU.merge(data['fcu_catalog'] || {})
    end
  end
end
