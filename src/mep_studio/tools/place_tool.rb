# frozen_string_literal: true

module MEPStudio
  # Places fan coils, air terminals, sprinkler heads and light fixtures.
  #
  #   click on a ceiling (face pointing down) -> hung from that ceiling
  #   click on a floor / anywhere else        -> placed at the default elevation
  #   → / ←   rotate +90 / -90        VCB: angle (deg) | L / R (pipe hand) | e2700
  #   Tab     options (model, elevation ...)
  class PlaceTool
    def initialize(kind)
      @kind = kind # fcu | terminal | sprinkler | light
      @opts = Settings[kind == 'terminal' ? 'terminal' : kind].dup
      @angle = @opts['rotation'].to_f
      @ip = Sketchup::InputPoint.new
      @tr = nil
    end

    def activate
      refresh_definition
      update_status
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def enableVCB?
      true
    end

    def refresh_definition
      @defn = Util.operation('MEP: prepare component') do
        case @kind
        when 'fcu' then Equipment.fcu_definition(@opts['model'], @opts['hand'])
        when 'terminal' then Equipment.terminal_definition(@opts['model'])
        when 'sprinkler' then Equipment.sprinkler_definition(@opts['head'], @opts['k_factor'])
        else Equipment.light_definition(@opts['model'])
        end
      end
    end

    def ceiling_type?
      return true unless @kind == 'fcu'
      spec = Settings.fcu_catalog[@opts['model']] || {}
      spec['type'] != 'floor'
    end

    def compute_tr(view, x, y)
      @ip.pick(view, x, y)
      return nil unless @ip.valid?
      p = Util.pt_a(@ip.position)
      face = @ip.face
      down = false
      if face
        n = face.normal.transform(@ip.transformation)
        down = n.z < -0.9
      end
      z = p[2]
      if @kind == 'fcu' && ceiling_type?
        spec = Settings.fcu_catalog[@opts['model']] || {}
        z = if down
              p[2] - Util.mm(@opts['gap_to_slab'])
            else
              p[2] + Util.mm(@opts['bottom_elevation'].to_f + spec['H'].to_f + (spec['type'] == 'cassette' ? 30 : 15))
            end
      elsif @kind == 'fcu'
        z = p[2]
      elsif @kind == 'sprinkler'
        z = down ? p[2] + Util.mm(10) : p[2] + Util.mm(@opts['ceiling_height'].to_f + 10)
      else
        z = down ? p[2] : p[2] + Util.mm(@opts['ceiling_height'].to_f)
      end
      @down = down
      Geom::Transformation.translation(Geom::Point3d.new(p[0], p[1], z)) *
        Geom::Transformation.rotation(ORIGIN, Z_AXIS, @angle.degrees)
    end

    def onMouseMove(_flags, x, y, view)
      @tr = compute_tr(view, x, y)
      view.tooltip = @down ? 'Ceiling / سقف' : "Elevation #{elev_text}"
      view.invalidate
    end

    def elev_text
      case @kind
      when 'fcu' then "#{@opts['bottom_elevation'].to_i} mm (bottom)"
      else "#{@opts['ceiling_height'].to_i} mm"
      end
    end

    def onLButtonDown(_flags, x, y, view)
      tr = compute_tr(view, x, y)
      return unless tr && @defn
      local = Util.edit_tr.inverse * tr
      sys = case @kind
            when 'sprinkler' then 'SPR'
            when 'light' then 'LIGHT'
            when 'terminal' then @defn.get_attribute(DICT, 'system') || 'SA'
            else 'EQ'
            end
      extra = { 'model' => @opts['model'] || @opts['head'] }
      Util.operation("MEP: place #{@kind}") do
        Equipment.place(Util.model.active_entities, @defn, local, sys, extra)
      end
      Settings.set(@kind == 'terminal' ? 'terminal' : @kind, @opts.merge('rotation' => @angle))
      view.invalidate
    end

    def onKeyDown(key, _r, _f, view)
      right = defined?(VK_RIGHT) ? VK_RIGHT : 39
      left = defined?(VK_LEFT) ? VK_LEFT : 37
      case key
      when right then @angle = (@angle + 90) % 360
      when left then @angle = (@angle - 90) % 360
      when 9 then options_dialog
      else return false
      end
      update_status
      view.invalidate
      true
    end

    def onUserText(text, view)
      t = text.strip.downcase
      if %w[l left].include?(t) || %w[r right].include?(t)
        @opts['hand'] = t.start_with?('l') ? 'Left' : 'Right'
        refresh_definition
      elsif (m = t.match(/\Ae\s*=?\s*(-?\d+(?:\.\d+)?)\z/))
        key = @kind == 'fcu' ? 'bottom_elevation' : 'ceiling_height'
        @opts[key] = m[1].to_f
      elsif (m = t.match(/\A(-?\d+(?:\.\d+)?)\z/))
        @angle = m[1].to_f % 360
      else
        UI.messagebox('Type an angle (e.g. 45), L / R for pipe side, or e2700 for elevation')
      end
      update_status
      view.invalidate
    end

    def options_dialog
      case @kind
      when 'fcu'
        r = Util.ask('Fan coil / فن کویل', [
                       ['Model / مدل', @opts['model'], Settings.fcu_catalog.keys],
                       ['Pipe connection side / سمت لوله‌کشی', @opts['hand'], %w[Right Left]],
                       ['Bottom elevation from floor mm / تراز زیر دستگاه', @opts['bottom_elevation'].to_f],
                       ['Gap to slab when clicking on ceiling mm / فاصله تا سقف', @opts['gap_to_slab'].to_f],
                       ['Rotation deg / زاویه', @angle]
                     ])
        return unless r
        @opts['model'], @opts['hand'], @opts['bottom_elevation'], @opts['gap_to_slab'], @angle = r
      when 'terminal'
        r = Util.ask('Air terminal / دریچه', [
                       ['Model / مدل', @opts['model'], Catalog::TERMINALS.keys],
                       ['Ceiling height mm / ارتفاع سقف کاذب', @opts['ceiling_height'].to_f],
                       ['Rotation deg', @angle]
                     ])
        return unless r
        @opts['model'], @opts['ceiling_height'], @angle = r
      when 'sprinkler'
        r = Util.ask('Sprinkler head / هد اسپرینکلر', [
                       ['Head type', @opts['head'], %w[Pendent Upright Sidewall]],
                       ['K-factor (metric)', @opts['k_factor'].to_f],
                       ['Ceiling height mm', @opts['ceiling_height'].to_f]
                     ])
        return unless r
        @opts['head'], @opts['k_factor'], @opts['ceiling_height'] = r
      else
        r = Util.ask('Light / چراغ', [
                       ['Model', @opts['model'], Catalog::LIGHTS.keys],
                       ['Ceiling height mm', @opts['ceiling_height'].to_f],
                       ['Rotation deg', @angle]
                     ])
        return unless r
        @opts['model'], @opts['ceiling_height'], @angle = r
      end
      refresh_definition
    end

    def update_status
      label = @opts['model'] || @opts['head']
      Sketchup.set_status_text("MEP place #{@kind}: #{label} | rot #{@angle.to_i}° | #{elev_text} " \
                               '— Click to place, Tab options, ←/→ rotate, type angle / L / R / e2700')
      Sketchup.set_status_text('Angle / L R / e', SB_VCB_LABEL)
    end

    def draw(view)
      @ip.draw(view) if @ip.valid? && @ip.display?
      return unless @tr && @defn
      bb = @defn.bounds
      c = (0..7).map { |i| bb.corner(i).transform(@tr) }
      edges = [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
      view.line_width = 2
      view.drawing_color = 'orange'
      view.draw(GL_LINES, edges.flat_map { |a, b| [c[a], c[b]] })
      # connectors
      pts = Equipment.world_connectors(Struct.new(:definition, :transformation).new(@defn, @tr), @tr)
      view.draw_points(pts.map { |cn| Util.a_pt(cn['wpos']) }, 10, 2, 'magenta') unless pts.empty?
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@defn.bounds.corner(0).transform(@tr), @defn.bounds.corner(7).transform(@tr)) if @tr && @defn
      bb
    end
  end
end
