# frozen_string_literal: true

# Built-in catalogs (all dimensions in millimetres).
# Values are typical market values - every one of them can be overridden
# from  Extensions > MEP Studio > Settings  (stored as JSON).
module MEPStudio
  module Catalog
    # ---- Systems: code => [label, color RGB, tag name, discipline] ----
    SYSTEMS = {
      'SA'   => ['Supply Air / هوای رفت',          [96, 160, 230],  'M-DUCT-SUPPLY',  'mech'],
      'RA'   => ['Return Air / هوای برگشت',        [110, 190, 110], 'M-DUCT-RETURN',  'mech'],
      'FA'   => ['Fresh Air / هوای تازه',          [80, 210, 210],  'M-DUCT-FRESH',   'mech'],
      'EA'   => ['Exhaust Air / هوای تخلیه',       [170, 120, 80],  'M-DUCT-EXHAUST', 'mech'],
      'CHWS' => ['Chilled Water Supply / رفت آب سرد', [30, 80, 220], 'M-PIPE-CHWS', 'mech'],
      'CHWR' => ['Chilled Water Return / برگشت آب سرد', [120, 170, 255], 'M-PIPE-CHWR', 'mech'],
      'HWS'  => ['Hot Water Supply / رفت آب گرم',  [220, 40, 40],   'M-PIPE-HWS',     'mech'],
      'HWR'  => ['Hot Water Return / برگشت آب گرم', [240, 140, 60], 'M-PIPE-HWR',     'mech'],
      'CD'   => ['Condensate Drain / درین',        [150, 150, 150], 'M-PIPE-DRAIN',   'mech'],
      'DCW'  => ['Domestic Cold Water / آب سرد مصرفی', [40, 170, 90], 'P-PIPE-DCW',   'plumb'],
      'DHW'  => ['Domestic Hot Water / آب گرم مصرفی', [230, 90, 150], 'P-PIPE-DHW',   'plumb'],
      'SAN'  => ['Sanitary / فاضلاب',              [120, 85, 50],   'P-PIPE-SAN',     'plumb'],
      'SPR'  => ['Sprinkler / اسپرینکلر',          [230, 30, 30],   'F-PIPE-SPRINKLER', 'fire'],
      'FH'   => ['Fire Hose / شیلنگ آتش‌نشانی',   [150, 0, 0],     'F-PIPE-HOSE',    'fire'],
      'TRAY' => ['Cable Tray / سینی کابل',         [170, 170, 175], 'E-CABLE-TRAY',   'elec'],
      'COND' => ['Conduit / لوله برق',             [235, 200, 40],  'E-CONDUIT',      'elec'],
      'EQ'   => ['Equipment / تجهیزات',            [200, 200, 205], 'M-EQUIPMENT',    'mech'],
      'LIGHT' => ['Lighting / روشنایی',            [250, 240, 180], 'E-LIGHTING',     'elec']
    }.freeze

    DUCT_SYSTEMS = %w[SA RA FA EA].freeze
    PIPE_SYSTEMS = %w[CHWS CHWR HWS HWR CD DCW DHW SAN SPR FH COND].freeze

    # Steel pipe DN => outside diameter (mm)
    PIPE_OD = {
      15 => 21.3, 20 => 26.9, 25 => 33.7, 32 => 42.4, 40 => 48.3, 50 => 60.3,
      65 => 76.1, 80 => 88.9, 100 => 114.3, 125 => 139.7, 150 => 168.3,
      200 => 219.1, 250 => 273.0, 300 => 323.9
    }.freeze

    DN_INCH = {
      15 => '1/2"', 20 => '3/4"', 25 => '1"', 32 => '1-1/4"', 40 => '1-1/2"',
      50 => '2"', 65 => '2-1/2"', 80 => '3"', 100 => '4"', 125 => '5"',
      150 => '6"', 200 => '8"', 250 => '10"', 300 => '12"'
    }.freeze

    # Fan coil catalogue.
    #  type: ducted (concealed horizontal), cassette, exposed (ceiling), floor
    #  L = length (along outlet), D = depth (air flow direction), H = height
    #  out = supply outlet [w, h], ret = return opening [w, h]
    #  pipe = coil connection DN, drain = condensate DN
    FCU = {
      'FCU-200 Ducted'  => { 'type' => 'ducted', 'cfm' => 200,  'L' => 740,  'D' => 500, 'H' => 240, 'out' => [500, 120],  'ret' => [560, 180],  'pipe' => 20, 'drain' => 20 },
      'FCU-300 Ducted'  => { 'type' => 'ducted', 'cfm' => 300,  'L' => 840,  'D' => 500, 'H' => 240, 'out' => [600, 120],  'ret' => [660, 180],  'pipe' => 20, 'drain' => 20 },
      'FCU-400 Ducted'  => { 'type' => 'ducted', 'cfm' => 400,  'L' => 940,  'D' => 500, 'H' => 240, 'out' => [700, 120],  'ret' => [760, 180],  'pipe' => 20, 'drain' => 20 },
      'FCU-600 Ducted'  => { 'type' => 'ducted', 'cfm' => 600,  'L' => 1140, 'D' => 500, 'H' => 240, 'out' => [900, 120],  'ret' => [960, 180],  'pipe' => 20, 'drain' => 20 },
      'FCU-800 Ducted'  => { 'type' => 'ducted', 'cfm' => 800,  'L' => 1340, 'D' => 520, 'H' => 260, 'out' => [1100, 140], 'ret' => [1160, 200], 'pipe' => 25, 'drain' => 20 },
      'FCU-1000 Ducted' => { 'type' => 'ducted', 'cfm' => 1000, 'L' => 1540, 'D' => 520, 'H' => 260, 'out' => [1300, 140], 'ret' => [1360, 200], 'pipe' => 25, 'drain' => 20 },
      'FCU-1200 Ducted' => { 'type' => 'ducted', 'cfm' => 1200, 'L' => 1740, 'D' => 520, 'H' => 260, 'out' => [1500, 140], 'ret' => [1560, 200], 'pipe' => 25, 'drain' => 25 },
      'FCU-1400 Ducted' => { 'type' => 'ducted', 'cfm' => 1400, 'L' => 1940, 'D' => 540, 'H' => 280, 'out' => [1700, 150], 'ret' => [1760, 210], 'pipe' => 32, 'drain' => 25 },
      'Cassette 4-Way 600x600'  => { 'type' => 'cassette', 'cfm' => 400, 'L' => 575, 'D' => 575, 'H' => 260, 'panel' => 620, 'pipe' => 20, 'drain' => 20 },
      'Cassette 4-Way 900x900'  => { 'type' => 'cassette', 'cfm' => 800, 'L' => 840, 'D' => 840, 'H' => 300, 'panel' => 950, 'pipe' => 25, 'drain' => 25 },
      'Exposed Ceiling FCU-600' => { 'type' => 'exposed', 'cfm' => 600, 'L' => 1250, 'D' => 650, 'H' => 230, 'out' => [1000, 100], 'pipe' => 20, 'drain' => 20 },
      'Floor Standing FCU-400'  => { 'type' => 'floor', 'cfm' => 400, 'L' => 1000, 'D' => 220, 'H' => 620, 'out' => [700, 100], 'pipe' => 20, 'drain' => 20 },
      'Floor Standing FCU-800'  => { 'type' => 'floor', 'cfm' => 800, 'L' => 1400, 'D' => 220, 'H' => 620, 'out' => [1100, 100], 'pipe' => 25, 'drain' => 20 }
    }.freeze

    # Air terminals: [neck w, neck h or dia, face size]
    TERMINALS = {
      'Square Diffuser 600'    => { 'kind' => 'square',  'face' => 595, 'neck' => 250 },
      'Square Diffuser 450'    => { 'kind' => 'square',  'face' => 450, 'neck' => 200 },
      'Return Grille 600x300'  => { 'kind' => 'grille',  'face' => [600, 300], 'neck' => [550, 250] },
      'Linear Slot 1200 (2 slot)' => { 'kind' => 'linear', 'face' => [1200, 100], 'neck' => [1150, 80] },
      'Round Diffuser D300'    => { 'kind' => 'round',   'face' => 450, 'neck' => 250 }
    }.freeze

    LIGHTS = {
      'Panel 600x600'  => { 'w' => 595, 'l' => 595, 'h' => 40 },
      'Panel 300x1200' => { 'w' => 295, 'l' => 1195, 'h' => 40 },
      'Downlight D200' => { 'd' => 200, 'h' => 80 }
    }.freeze

    # NFPA 13 style density/area classes for standard-spray sprinklers.
    #   spacing = max distance between heads (mm), area = max area per head (m2)
    HAZARDS = {
      'Light'     => { 'spacing' => 4600, 'area' => 20.9, 'label' => 'Light Hazard / خطر کم (اداری، مسکونی)' },
      'Ordinary'  => { 'spacing' => 4600, 'area' => 12.1, 'label' => 'Ordinary Hazard / خطر معمولی (پارکینگ، انبار سبک)' },
      'Extra'     => { 'spacing' => 3700, 'area' => 9.3,  'label' => 'Extra Hazard / خطر زیاد' }
    }.freeze

    # Pipe schedule (number of heads allowed downstream) - steel pipe.
    SPR_SCHEDULE = {
      'Light'    => [[25, 2], [32, 3], [40, 5], [50, 10], [65, 30], [80, 60], [100, 100000]],
      'Ordinary' => [[25, 2], [32, 3], [40, 5], [50, 10], [65, 20], [80, 40], [100, 100], [125, 160], [150, 275]],
      'Extra'    => [[25, 1], [32, 2], [40, 5], [50, 8], [65, 15], [80, 27], [100, 55], [125, 90], [150, 150]]
    }.freeze

    def self.sprinkler_pipe_dn(hazard, heads)
      sched = SPR_SCHEDULE[hazard] || SPR_SCHEDULE['Light']
      sched.each { |dn, n| return dn if heads <= n }
      sched.last[0]
    end

    def self.system_label(code)
      (SYSTEMS[code] || [code])[0]
    end
  end
end
