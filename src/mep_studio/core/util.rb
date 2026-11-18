# frozen_string_literal: true

module MEPStudio
  DICT = 'MEPStudio'

  module Util
    MM = 1.0 / 25.4 # inches per millimetre

    module_function

    def mm(x)
      x.to_f * MM
    end

    def to_mm(inch)
      inch.to_f * 25.4
    end

    def pt_a(p)
      [p.x.to_f, p.y.to_f, p.z.to_f]
    end

    def a_pt(a)
      Geom::Point3d.new(a[0], a[1], a[2])
    end

    def a_vec(a)
      Geom::Vector3d.new(a[0], a[1], a[2])
    end

    def model
      Sketchup.active_model
    end

    # Transformation from active editing context to world.
    def edit_tr
      model.edit_transform || Geom::Transformation.new
    end

    # World point (from InputPoint) => coordinates of the active context.
    def world_to_active(p)
      p.transform(edit_tr.inverse)
    end

    def tag(name)
      layers = model.layers
      layers[name] || layers.add(name)
    end

    def material(code)
      sys = Catalog::SYSTEMS[code]
      name = "MEP_#{code}"
      mats = model.materials
      mat = mats[name]
      return mat if mat
      mat = mats.add(name)
      mat.color = Sketchup::Color.new(*(sys ? sys[1] : [200, 200, 200]))
      mat
    end

    def plain_material(name, rgb, alpha = 1.0)
      mats = model.materials
      mat = mats[name]
      return mat if mat
      mat = mats.add(name)
      mat.color = Sketchup::Color.new(*rgb)
      mat.alpha = alpha
      mat
    end

    def system_tag(code)
      sys = Catalog::SYSTEMS[code]
      tag(sys ? sys[2] : "MEP-#{code}")
    end

    def mep?(ent)
      (ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)) &&
        !ent.get_attribute(DICT, 'type').nil?
    end

    def mep_type(ent)
      return nil unless ent.respond_to?(:get_attribute)
      ent.get_attribute(DICT, 'type')
    end

    def set_attrs(ent, hash)
      hash.each { |k, val| ent.set_attribute(DICT, k.to_s, val) }
    end

    def attrs(ent)
      d = ent.attribute_dictionary(DICT)
      return {} unless d
      h = {}
      d.each_pair { |k, val| h[k] = val }
      h
    end

    # Soften edges between nearly coplanar faces (smooth elbows / round pipes).
    def soften(entities, max_angle_deg = 25.0)
      lim = max_angle_deg * Math::PI / 180.0
      entities.grep(Sketchup::Edge).each do |e|
        f = e.faces
        next unless f.size == 2
        if f[0].normal.angle_between(f[1].normal) < lim
          e.soft = true
          e.smooth = true
        end
      end
    end

    def fmt(x, dec = 0)
      format("%.#{dec}f", x)
    end

    def ui_error(e)
      msg = "MEP Studio error:\n#{e.message}"
      puts "#{msg}\n#{e.backtrace.first(8).join("\n")}"
      UI.messagebox(msg)
    end

    # Run block inside an undoable operation, abort on error.
    def operation(name)
      m = model
      m.start_operation(name, true)
      res = yield
      m.commit_operation
      res
    rescue StandardError => e
      m.abort_operation
      ui_error(e)
      nil
    end

    # Ask values with UI.inputbox. fields: [[label, default, list_or_nil], ...]
    # Returns array of values (numbers converted) or nil if cancelled.
    def ask(title, fields)
      prompts = fields.map { |f| f[0] }
      defaults = fields.map { |f| f[1].is_a?(Numeric) ? f[1].to_s : f[1].to_s }
      lists = fields.map { |f| f[2] ? f[2].join('|') : '' }
      res = UI.inputbox(prompts, defaults, lists, title)
      return nil unless res
      res.each_with_index.map do |val, i|
        if fields[i][1].is_a?(Numeric)
          val.to_s.tr('٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789').to_f
        else
          val
        end
      end
    end

    def bool_list
      %w[Yes No]
    end

    def yes?(v)
      v == true || v.to_s.downcase.start_with?('y')
    end
  end
end
