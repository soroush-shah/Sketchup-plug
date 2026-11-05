# UI (mm / degrees, string keys) -> engine params (inches / radians, symbols).
module BanianStudio
  module FloorStudio
    module Params
      LENGTHS = %w[length width gap wood_min wood_max length_step stagger small
                   offset_x offset_y thickness grout_depth profile_size min_piece
                   imp_height].freeze
      ANGLES = %w[angle chevron_angle tilt imp_angle].freeze
      DEFAULTS = {
        'mode' => '3d', 'pattern' => 'grid',
        'length' => 600, 'width' => 600, 'gap' => 3, 'offset' => 0.5,
        'wood_min' => 600, 'wood_max' => 1800, 'length_step' => 0, 'stagger' => 200,
        'chevron_angle' => 45, 'basket_n' => 3, 'small' => 300, 'jitter' => 0.8, 'tilt' => 4,
        'angle' => 0, 'anchor' => 'corner', 'anchor_pt' => nil, 'anchor_center' => false, 'align' => 'edge', 'offset_x' => 0, 'offset_y' => 0, 'flip' => false,
        'thickness' => 10, 'grout_depth' => 2, 'profile' => 'chamfer', 'profile_size' => 1.5,
        'materials' => [], 'weights' => [], 'mat_mode' => 'random', 'shades' => 1, 'shade_amount' => 0.08,
        'grout_mat' => '', 'grout_color' => '#8a8580',
        'tex_random' => true, 'tex_variants' => 6, 'tex_rot' => '180',
        'imp_angle' => 0, 'imp_height' => 0, 'min_piece' => 0, 'seed' => 1,
        'paint' => false, 'paint_grout' => false, 'keep_face' => true, 'tex_ppm' => 2
      }.freeze

      module_function

      def from_ui(h)
        src = DEFAULTS.merge(h || {})
        p = {}
        src.each do |k, v|
          sym = k.to_sym
          if LENGTHS.include?(k)
            p[sym] = v.to_f / 25.4
          elsif ANGLES.include?(k)
            p[sym] = v.to_f * Math::PI / 180.0
          else
            p[sym] = v
          end
        end
        p[:seed] = p[:seed].to_i
        p[:basket_n] = p[:basket_n].to_i
        p[:shades] = p[:shades].to_i
        p[:tex_variants] = p[:tex_variants].to_i
        p[:offset] = p[:offset].to_f
        p[:jitter] = p[:jitter].to_f
        p[:shade_amount] = p[:shade_amount].to_f
        p[:flip] = truthy(p[:flip])
        p[:anchor_center] = truthy(p[:anchor_center])
        ap = p[:anchor_pt]
        p[:anchor_pt] = ap.is_a?(Array) && ap.length >= 2 ? [ap[0].to_f / 25.4, ap[1].to_f / 25.4, ap[2].to_f / 25.4] : nil
        %i[tex_random paint paint_grout keep_face].each { |k| p[k] = truthy(p[k]) }
        p[:materials] = Array(p[:materials]).map(&:to_s)
        p[:weights] = Array(p[:weights]).map(&:to_f)
        p
      end

      def truthy(v)
        v == true || v.to_s == 'true' || v.to_s == '1'
      end
    end
  end
end
