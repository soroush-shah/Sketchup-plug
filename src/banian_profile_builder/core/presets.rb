# encoding: UTF-8
# Banian Profile Builder - ready-made assemblies. Each preset turns a few
# friendly numbers into assembly rows (all mm).

module BanianStudio
  module ProfileBuilder
    module Presets
      Entry = Struct.new(:id, :name_en, :name_fa, :params, :generator, :category)
      LIST = []
      INDEX = {}

      CATEGORIES = %w[railing fence wall trim structure].freeze

      def self.define(id, en, fa, params, category = 'structure', &gen)
        e = Entry.new(id, en, fa, params, gen, category)
        LIST << e
        INDEX[id] = e
      end

      P = Profiles::P

      def self.layer(name, profile, params, extra = {})
        { 'type' => 'layer', 'name' => name, 'profile' => profile, 'params' => params,
          'anchor' => 'bc', 'offset_u' => 0, 'offset_v' => 0, 'rotation' => 0, 'flip' => false,
          'material' => '', 'visible' => true }.merge(extra)
      end

      def self.repeat(name, profile, params, extra = {})
        { 'type' => 'repeat', 'name' => name, 'profile' => profile, 'params' => params,
          'anchor' => 'mc', 'offset_u' => 0, 'rotation' => 0, 'flip' => false,
          'v0' => 0, 'length' => 1000, 'spacing' => 400, 'setback_start' => 0, 'setback_end' => 0,
          'mode' => 'even', 'at_corners' => false, 'jambs' => false,
          'material' => '', 'visible' => true }.merge(extra)
      end

      def self.n(p, k)
        p[k].to_f
      end

      define('stud_wall', 'Stud Wall Frame', 'دیوار اسکلت چوبی / سبک',
             [P.call('height', 'Wall height', 'ارتفاع دیوار', 2400),
              P.call('stud_w', 'Stud width', 'عرض استاد', 38),
              P.call('stud_d', 'Stud depth', 'عمق استاد', 89),
              P.call('spacing', 'Spacing', 'فاصله استادها', 400)], 'wall') do |p|
        h = n(p, 'height'); w = n(p, 'stud_w'); d = n(p, 'stud_d')
        plate = { 'w' => d, 'h' => w }
        [layer('Bottom plate', 'rect', plate, 'material' => 'BPB Wood'),
         layer('Top plate', 'rect', plate, 'offset_v' => h - 2 * w, 'material' => 'BPB Wood'),
         layer('Top plate 2', 'rect', plate, 'offset_v' => h - w, 'material' => 'BPB Wood'),
         repeat('Stud', 'rect', { 'w' => d, 'h' => w },
                'v0' => w, 'length' => h - 3 * w, 'spacing' => n(p, 'spacing'),
                'setback_start' => w / 2, 'setback_end' => w / 2, 'mode' => 'fixed',
                'at_corners' => true, 'jambs' => true, 'material' => 'BPB Wood')]
      end

      define('fence', 'Fence', 'نرده / فنس حیاط',
             [P.call('height', 'Height', 'ارتفاع', 1500),
              P.call('post', 'Post size', 'سایز ستون', 90),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 2000),
              P.call('picket_w', 'Picket width', 'عرض تخته', 90),
              P.call('picket_gap', 'Picket gap', 'فاصله تخته‌ها', 30)], 'fence') do |p|
        h = n(p, 'height'); ps = n(p, 'post'); pw = n(p, 'picket_w')
        rail_t = 38; rail_h = 89; pk_t = 19
        ru = ps / 2.0 + rail_t / 2.0
        pu = ps / 2.0 + rail_t + pk_t / 2.0
        [repeat('Post', 'rect', { 'w' => ps, 'h' => ps },
                'length' => h + 100, 'spacing' => n(p, 'post_spacing'), 'at_corners' => true,
                'jambs' => true, 'material' => 'BPB Wood'),
         layer('Rail bottom', 'rect', { 'w' => rail_t, 'h' => rail_h },
               'offset_u' => ru, 'offset_v' => 250, 'material' => 'BPB Wood'),
         layer('Rail top', 'rect', { 'w' => rail_t, 'h' => rail_h },
               'offset_u' => ru, 'offset_v' => h - 250 - rail_h, 'material' => 'BPB Wood'),
         repeat('Picket', 'rect', { 'w' => pk_t, 'h' => pw },
                'offset_u' => pu, 'v0' => 50, 'length' => h - 50,
                'spacing' => pw + n(p, 'picket_gap'), 'setback_start' => pw / 2,
                'setback_end' => pw / 2, 'material' => 'BPB Wood')]
      end

      define('railing', 'Metal Baluster Railing', 'نرده میله‌ای فلزی',
             [P.call('height', 'Height', 'ارتفاع', 1000),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 1500),
              P.call('baluster', 'Baluster diameter', 'قطر میله', 16),
              P.call('baluster_spacing', 'Baluster spacing', 'فاصله میله‌ها', 110),
              P.call('handrail', 'Handrail diameter', 'قطر دست‌انداز', 50)], 'railing') do |p|
        h = n(p, 'height'); hr = n(p, 'handrail')
        [repeat('Post', 'square_tube', { 'w' => 50, 'h' => 50, 't' => 2 },
                'length' => h - hr / 2, 'spacing' => n(p, 'post_spacing'), 'at_corners' => true,
                'material' => 'BPB Metal'),
         layer('Handrail', 'round_tube', { 'd' => hr, 't' => 2 },
               'offset_v' => h - hr, 'material' => 'BPB Metal'),
         layer('Bottom rail', 'square_tube', { 'w' => 30, 'h' => 30, 't' => 2 },
               'offset_v' => 100, 'material' => 'BPB Metal'),
         repeat('Baluster', 'round_bar', { 'd' => n(p, 'baluster') },
                'v0' => 130, 'length' => h - hr - 130, 'spacing' => n(p, 'baluster_spacing'),
                'setback_start' => 60, 'setback_end' => 60, 'material' => 'BPB Metal')]
      end

      define('glass_partition', 'Glass Partition', 'پارتیشن شیشه‌ای',
             [P.call('height', 'Height', 'ارتفاع', 2700),
              P.call('mullion_spacing', 'Mullion spacing', 'فاصله مولیون', 1200),
              P.call('frame', 'Frame size', 'سایز فریم', 50),
              P.call('glass', 'Glass thickness', 'ضخامت شیشه', 10)], 'wall') do |p|
        h = n(p, 'height'); f = n(p, 'frame')
        [layer('Bottom track', 'square_tube', { 'w' => f, 'h' => f, 't' => 2 }, 'material' => 'BPB Metal'),
         layer('Top track', 'square_tube', { 'w' => f, 'h' => f, 't' => 2 },
               'offset_v' => h - f, 'material' => 'BPB Metal'),
         layer('Glass', 'rect', { 'w' => n(p, 'glass'), 'h' => h - 2 * f },
               'offset_v' => f, 'material' => 'BPB Glass'),
         repeat('Mullion', 'square_tube', { 'w' => f, 'h' => f, 't' => 2 },
                'v0' => f, 'length' => h - 2 * f, 'spacing' => n(p, 'mullion_spacing'),
                'at_corners' => true, 'jambs' => true, 'material' => 'BPB Metal')]
      end

      define('wall_trim', 'Interior Wall Trim', 'ابزار و قرنیز دیوار',
             [P.call('height', 'Ceiling height', 'ارتفاع سقف', 2800),
              P.call('base_h', 'Baseboard height', 'ارتفاع قرنیز', 100),
              P.call('chair_h', 'Chair rail height (0 = none)', 'ارتفاع ابزار میانی (۰ = ندارد)', 900),
              P.call('crown', 'Crown size (0 = none)', 'سایز ابزار سقفی (۰ = ندارد)', 90)], 'trim') do |p|
        rows = [layer('Baseboard', 'baseboard', { 'h' => n(p, 'base_h'), 't' => 16 },
                      'anchor' => 'br', 'flip' => true, 'material' => 'BPB White')]
        if n(p, 'chair_h') > 0
          rows << layer('Chair rail', 'chair_rail', { 'h' => 60, 't' => 22 },
                        'anchor' => 'br', 'flip' => true, 'offset_v' => n(p, 'chair_h') - 30,
                        'material' => 'BPB White')
        end
        if n(p, 'crown') > 0
          c = n(p, 'crown')
          rows << layer('Crown', 'crown', { 'w' => c, 'h' => c, 't' => 14 },
                        'anchor' => 'tr', 'flip' => true, 'offset_v' => n(p, 'height'),
                        'material' => 'BPB White')
        end
        rows
      end

      define('pergola_beam', 'Pergola / Canopy Frame', 'آلاچیق و سایبان',
             [P.call('height', 'Height', 'ارتفاع', 2600),
              P.call('post', 'Post size', 'سایز ستون', 120),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 3000),
              P.call('beam_h', 'Beam depth', 'ارتفاع تیر', 200)], 'structure') do |p|
        h = n(p, 'height'); ps = n(p, 'post'); bh = n(p, 'beam_h')
        [repeat('Post', 'rect', { 'w' => ps, 'h' => ps },
                'length' => h - bh, 'spacing' => n(p, 'post_spacing'), 'at_corners' => true,
                'material' => 'BPB Wood'),
         layer('Beam', 'rect', { 'w' => ps, 'h' => bh },
               'offset_v' => h - bh, 'material' => 'BPB Wood')]
      end


      # ---------- more railings & fences ----------------------------------

      define('glass_railing', 'Glass Railing with Posts', 'نرده شیشه‌ای با ستون',
             [P.call('height', 'Height', 'ارتفاع', 1000),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 1200),
              P.call('glass', 'Glass thickness', 'ضخامت شیشه', 12),
              P.call('handrail', 'Handrail diameter', 'قطر دست‌انداز', 50)], 'railing') do |p|
        h = n(p, 'height'); hr = n(p, 'handrail')
        [repeat('Post', 'square_tube', { 'w' => 50, 'h' => 50, 't' => 2 },
                'length' => h - hr, 'spacing' => n(p, 'post_spacing'), 'at_corners' => true,
                'jambs' => true, 'material' => 'BPB Metal'),
         layer('Handrail', 'round_tube', { 'd' => hr, 't' => 2 }, 'offset_v' => h - hr, 'material' => 'BPB Metal'),
         layer('Glass', 'rect', { 'w' => n(p, 'glass'), 'h' => h - hr - 150 },
               'offset_v' => 100, 'material' => 'BPB Glass')]
      end

      define('frameless_glass', 'Frameless Glass (Base Shoe)', 'نرده شیشه‌ای بدون ستون',
             [P.call('height', 'Height', 'ارتفاع', 1050),
              P.call('glass', 'Glass thickness', 'ضخامت شیشه', 15),
              P.call('cap', 'Top cap diameter', 'قطر درپوش بالا', 42)], 'railing') do |p|
        h = n(p, 'height'); cap = n(p, 'cap')
        [layer('Base shoe', 'rect', { 'w' => 60, 'h' => 110 }, 'material' => 'BPB Dark Metal'),
         layer('Glass', 'rect', { 'w' => n(p, 'glass'), 'h' => h - 40 - cap / 2 },
               'offset_v' => 40, 'material' => 'BPB Glass'),
         layer('Top cap', 'round_tube', { 'd' => cap, 't' => 2 }, 'offset_v' => h - cap, 'material' => 'BPB Metal')]
      end

      define('cable_railing', 'Cable Railing', 'نرده کابلی',
             [P.call('height', 'Height', 'ارتفاع', 1000),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 1500),
              P.call('cable_gap', 'Cable spacing', 'فاصله کابل‌ها', 80),
              P.call('cable_d', 'Cable diameter', 'قطر کابل', 5)], 'railing') do |p|
        h = n(p, 'height'); gap = [n(p, 'cable_gap'), 20].max
        rows = [repeat('Post', 'rect', { 'w' => 50, 'h' => 50 },
                       'length' => h - 40, 'spacing' => n(p, 'post_spacing'), 'at_corners' => true,
                       'material' => 'BPB Dark Metal'),
                layer('Top rail', 'rect', { 'w' => 90, 'h' => 40 }, 'offset_v' => h - 40, 'material' => 'BPB Wood')]
        z = 100.0
        i = 1
        while z < h - 40 - gap / 2.0
          rows << layer("Cable #{i}", 'round_bar', { 'd' => n(p, 'cable_d') }, 'offset_v' => z, 'material' => 'BPB Metal')
          z += gap
          i += 1
        end
        rows
      end

      define('horizontal_bars', 'Modern Horizontal Bars', 'نرده مدرن افقی',
             [P.call('height', 'Height', 'ارتفاع', 1000),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 1500),
              P.call('bar_h', 'Bar height', 'ارتفاع تسمه', 40),
              P.call('bar_gap', 'Gap between bars', 'فاصله تسمه‌ها', 90)], 'railing') do |p|
        h = n(p, 'height'); bh = n(p, 'bar_h'); gap = [n(p, 'bar_gap'), 10].max
        rows = [repeat('Post', 'square_tube', { 'w' => 60, 'h' => 60, 't' => 3 },
                       'length' => h - 40, 'spacing' => n(p, 'post_spacing'), 'at_corners' => true,
                       'material' => 'BPB Dark Metal'),
                layer('Top rail', 'square_tube', { 'w' => 80, 'h' => 40, 't' => 2 },
                      'offset_v' => h - 40, 'material' => 'BPB Dark Metal')]
        z = 100.0
        i = 1
        while z + bh < h - 40 - 30
          rows << layer("Bar #{i}", 'rect', { 'w' => 12, 'h' => bh }, 'offset_u' => 36,
                        'offset_v' => z, 'material' => 'BPB Dark Metal')
          z += bh + gap
          i += 1
        end
        rows
      end

      define('wood_deck_railing', 'Wood Deck Railing', 'نرده چوبی تراس',
             [P.call('height', 'Height', 'ارتفاع', 1000),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 1800),
              P.call('baluster', 'Baluster size', 'سایز نرده', 38),
              P.call('baluster_gap', 'Baluster gap', 'فاصله نرده‌ها', 90)], 'railing') do |p|
        h = n(p, 'height'); b = n(p, 'baluster'); cap = 38
        top = h - cap - 89
        [repeat('Post', 'rect', { 'w' => 90, 'h' => 90 }, 'length' => h - cap, 'spacing' => n(p, 'post_spacing'),
                'at_corners' => true, 'jambs' => true, 'material' => 'BPB Wood'),
         layer('Cap', 'rect', { 'w' => 140, 'h' => cap }, 'offset_v' => h - cap, 'material' => 'BPB Wood'),
         layer('Top rail', 'rect', { 'w' => 38, 'h' => 89 }, 'offset_v' => top, 'material' => 'BPB Wood'),
         layer('Bottom rail', 'rect', { 'w' => 38, 'h' => 89 }, 'offset_v' => 80, 'material' => 'BPB Wood'),
         repeat('Baluster', 'rect', { 'w' => b, 'h' => b }, 'v0' => 169, 'length' => top - 169,
                'spacing' => b + n(p, 'baluster_gap'), 'setback_start' => 80, 'setback_end' => 80,
                'material' => 'BPB Wood')]
      end

      define('wood_slats', 'Vertical Wood Slats', 'نرده تخته‌ای عمودی',
             [P.call('height', 'Height', 'ارتفاع', 1000),
              P.call('slat_w', 'Slat width', 'عرض تخته', 70),
              P.call('slat_gap', 'Slat gap', 'فاصله تخته‌ها', 25)], 'railing') do |p|
        h = n(p, 'height'); sw = n(p, 'slat_w')
        [layer('Bottom rail', 'rect', { 'w' => 60, 'h' => 40 }, 'offset_v' => 50, 'material' => 'BPB Dark Metal'),
         layer('Top cap', 'rect', { 'w' => 100, 'h' => 30 }, 'offset_v' => h - 30, 'material' => 'BPB Wood'),
         repeat('Slat', 'rect', { 'w' => 20, 'h' => sw }, 'v0' => 50, 'length' => h - 80,
                'spacing' => sw + n(p, 'slat_gap'), 'setback_start' => sw / 2, 'setback_end' => sw / 2,
                'material' => 'BPB Wood')]
      end

      define('classic_iron', 'Classic Iron Railing', 'نرده فرفورژه کلاسیک',
             [P.call('height', 'Height', 'ارتفاع', 1000),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 1500),
              P.call('bar', 'Bar size', 'سایز میله', 14),
              P.call('bar_spacing', 'Bar spacing', 'فاصله میله‌ها', 110)], 'railing') do |p|
        h = n(p, 'height'); bar = n(p, 'bar'); sp = n(p, 'bar_spacing')
        band = h - 160
        [repeat('Post', 'rect', { 'w' => 40, 'h' => 40 }, 'length' => h - 50, 'spacing' => n(p, 'post_spacing'),
                'at_corners' => true, 'material' => 'BPB Dark Metal'),
         layer('Handrail', 'half_round', { 'd' => 50 }, 'offset_v' => h - 25, 'material' => 'BPB Dark Metal'),
         layer('Top rail', 'rect', { 'w' => 40, 'h' => 25 }, 'offset_v' => h - 50, 'material' => 'BPB Dark Metal'),
         layer('Band rail', 'rect', { 'w' => 20, 'h' => 20 }, 'offset_v' => band, 'material' => 'BPB Dark Metal'),
         layer('Bottom rail', 'rect', { 'w' => 20, 'h' => 20 }, 'offset_v' => 80, 'material' => 'BPB Dark Metal'),
         repeat('Bar', 'rect', { 'w' => bar, 'h' => bar }, 'v0' => 100, 'length' => h - 150,
                'spacing' => sp, 'setback_start' => 60, 'setback_end' => 60, 'material' => 'BPB Dark Metal'),
         repeat('Collar bar', 'round_bar', { 'd' => bar - 2 }, 'v0' => band + 20, 'length' => h - 70 - band,
                'spacing' => sp, 'setback_start' => 60 + sp / 2, 'setback_end' => 60 + sp / 2,
                'material' => 'BPB Dark Metal')]
      end

      define('panel_railing', 'Solid Panel Railing', 'نرده پنلی (ورق)',
             [P.call('height', 'Height', 'ارتفاع', 1000),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 1200),
              P.call('gap', 'Panel bottom gap', 'فاصله پنل از کف', 100)], 'railing') do |p|
        h = n(p, 'height'); g = n(p, 'gap')
        [repeat('Post', 'square_tube', { 'w' => 50, 'h' => 50, 't' => 2 }, 'length' => h - 50,
                'spacing' => n(p, 'post_spacing'), 'at_corners' => true, 'material' => 'BPB Dark Metal'),
         layer('Handrail', 'round_tube', { 'd' => 50, 't' => 2 }, 'offset_v' => h - 50, 'material' => 'BPB Metal'),
         layer('Panel', 'rect', { 'w' => 6, 'h' => h - 100 - g }, 'offset_u' => 28, 'offset_v' => g,
               'material' => 'BPB Concrete')]
      end

      define('horizontal_fence', 'Horizontal Slat Fence', 'فنس تخته‌ای افقی',
             [P.call('height', 'Height', 'ارتفاع', 1800),
              P.call('post_spacing', 'Post spacing', 'فاصله ستون‌ها', 1800),
              P.call('slat_h', 'Slat height', 'ارتفاع تخته', 90),
              P.call('slat_gap', 'Slat gap', 'فاصله تخته‌ها', 15)], 'fence') do |p|
        h = n(p, 'height'); sh = n(p, 'slat_h'); gap = [n(p, 'slat_gap'), 0].max
        rows = [repeat('Post', 'rect', { 'w' => 90, 'h' => 90 }, 'length' => h, 'spacing' => n(p, 'post_spacing'),
                       'at_corners' => true, 'jambs' => true, 'material' => 'BPB Dark Metal')]
        z = 50.0
        i = 1
        while z + sh <= h + 0.1
          rows << layer("Slat #{i}", 'rect', { 'w' => 20, 'h' => sh }, 'offset_u' => 55, 'offset_v' => z,
                        'material' => 'BPB Wood')
          z += sh + gap
          i += 1
        end
        rows
      end

      def self.defaults(id)
        e = INDEX[id]
        return {} unless e
        h = {}
        e.params.each { |pp| h[pp['key']] = pp['default'] }
        h
      end

      def self.rows_for(id, params)
        e = INDEX[id]
        return [] unless e
        e.generator.call(defaults(id).merge(params || {}))
      end

      def self.json
        LIST.map do |e|
          { 'id' => e.id, 'en' => e.name_en, 'fa' => e.name_fa, 'params' => e.params, 'category' => e.category,
            'thumb' => Assembly.elevation('rows' => rows_for(e.id, {}), 'openings' => []) }
        end
      end
    end
  end
end
