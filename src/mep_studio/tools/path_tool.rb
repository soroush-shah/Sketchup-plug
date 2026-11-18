# frozen_string_literal: true

module MEPStudio
  # Interactive tool for drawing ducts, pipes, cable trays and conduits.
  #
  #   click            add a point (at the current elevation)
  #   double-click /
  #   Enter            finish the run
  #   Backspace        remove last point
  #   Esc              cancel
  #   Tab              options dialog (system, size, elevation ...)
  #   Right / Left     lock X / Y axis     Down = unlock
  #   VCB:  1200       length along mouse direction
  #         400x250    width x height (mm)      d300 = round diameter
  #         dn80       pipe size               r1.5 = elbow radius factor
  #         e3200      elevation (mm) above the first picked floor point
  #         z+1500     vertical riser / drop from the last point
  class PathTool
    SNAP_PX = 22
    LEAD = 200.0 # mm straight lead out of an equipment connector

    def initialize(kind)
      @kind = kind # 'duct' | 'pipe' | 'tray'
      section = kind == 'tray' ? 'tray' : kind
      @opts = Settings[section].dup
      @opts['kind'] = kind
      @opts['system'] = 'TRAY' if kind == 'tray'
      @opts['shape'] = 'rect' if kind == 'tray'
      @opts['show_insulation'] ||= false
      reset
    end

    def reset
      @pts = []
      @base_z = nil
      @ip = Sketchup::InputPoint.new
      @cursor = nil
      @lock = nil
      @snap = nil
    end

    # ------------------------------------------------------------ lifecycle
    def activate
      reset
      update_status
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def onCancel(_reason, view)
      reset
      update_status
      view.invalidate
    end

    def enableVCB?
      true
    end

    # ------------------------------------------------------------ geometry
    def size_mm
      if @kind == 'pipe'
        od = Catalog::PIPE_OD[@opts['dn'].to_i] || 50
        [od, od]
      elsif @opts['shape'] == 'round'
        [@opts['diameter'].to_f, @opts['diameter'].to_f]
      else
        [@opts['width'].to_f, @opts['height'].to_f]
      end
    end

    # Height of the centerline above the floor point.
    def center_offset
      h = size_mm[1]
      e = @opts['elevation'].to_f
      case @opts['elev_ref']
      when 'bottom' then Util.mm(e + h / 2.0)
      when 'top' then Util.mm(e - h / 2.0)
      else Util.mm(e)
      end
    end

    def level_z
      (@base_z || 0.0) + center_offset
    end

    def candidate(view, x, y)
      @snap = find_connector(view, x, y)
      return @snap['wpos'] if @snap

      prev = @pts.empty? ? nil : Sketchup::InputPoint.new(Util.a_pt(@pts.last))
      prev ? @ip.pick(view, x, y, prev) : @ip.pick(view, x, y)
      return nil unless @ip.valid?
      p = Util.pt_a(@ip.position)
      z = @base_z.nil? ? p[2] + center_offset : level_z
      q = [p[0], p[1], z]
      if @lock && !@pts.empty?
        last = @pts.last
        q = @lock == :x ? [q[0], last[1], last[2]] : [last[0], q[1], last[2]]
      end
      q
    end

    # Snap to equipment connectors / open ends of existing runs.
    def find_connector(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      best = nil
      best_d = SNAP_PX
      ph.count.times do |i|
        path = ph.path_at(i) || []
        tr = Geom::Transformation.new
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
          tr *= ent.transformation
          conns = connectors_for(ent, tr)
          conns.each do |c|
            sp = view.screen_coords(Util.a_pt(c['wpos']))
            d = Math.hypot(sp.x - x, sp.y - y)
            if d < best_d
              best_d = d
              best = c
            end
          end
        end
      end
      best
    end

    def connectors_for(ent, tr)
      type = Util.mep_type(ent)
      return [] unless type
      if ent.is_a?(Sketchup::ComponentInstance)
        Equipment.world_connectors(ent, tr)
      elsif %w[duct pipe tray].include?(type)
        path = RunBuilder.path_from(ent)
        return [] if path.size < 2
        a = Util.attrs(ent)
        [[path.first, path[1]], [path.last, path[-2]]].map do |end_pt, nxt|
          wp = Util.pt_a(Util.a_pt(end_pt).transform(tr))
          wn = Util.pt_a(Util.a_pt(nxt).transform(tr))
          size = a['shape'] == 'round' ? [a['type'] == 'pipe' ? a['dn'] : a['diameter']] : [a['width'], a['height']]
          { 'name' => 'End', 'system' => a['system'], 'wpos' => wp, 'wdir' => Geo.norm(Geo.sub(wp, wn)),
            'size' => size, 'shape' => a['shape'], 'run_end' => true }
        end
      else
        []
      end
    end

    def compatible?(c)
      sys = c['system']
      case @kind
      when 'duct' then Catalog::DUCT_SYSTEMS.include?(sys)
      when 'pipe' then Catalog::PIPE_SYSTEMS.include?(sys)
      else sys == 'TRAY'
      end
    end

    # Adopt size/system of the connector when starting from it.
    def adopt(c)
      return unless compatible?(c)
      @opts['system'] = c['system']
      s = c['size'] || []
      if @kind == 'pipe'
        @opts['dn'] = s[0].to_i if s[0]
      elsif @kind == 'duct'
        if s.size >= 2 && c['shape'] != 'round'
          @opts['shape'] = 'rect'
          @opts['width'] = s[0].to_f.round
          @opts['height'] = s[1].to_f.round
        elsif s[0]
          @opts['shape'] = 'round'
          @opts['diameter'] = s[0].to_f.round
        end
      end
    end

    def lead_point(c)
      Geo.add(c['wpos'], Geo.mul(c['wdir'], Util.mm(LEAD)))
    end

    # ------------------------------------------------------------ events
    def onMouseMove(_flags, x, y, view)
      @cursor = candidate(view, x, y)
      view.tooltip = @snap ? "#{@snap['name']} (#{@snap['system']})" : (@ip.valid? ? @ip.tooltip : '')
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      p = candidate(view, x, y)
      return unless p
      add_point(p, @snap, view)
    end

    def onLButtonDoubleClick(_flags, _x, _y, view)
      finish(view)
    end

    def onReturn(view)
      finish(view)
    end

    def onKeyDown(key, _repeat, _flags, view)
      right = defined?(VK_RIGHT) ? VK_RIGHT : 39
      left = defined?(VK_LEFT) ? VK_LEFT : 37
      down = defined?(VK_DOWN) ? VK_DOWN : 40
      case key
      when right then @lock = @lock == :x ? nil : :x
      when left then @lock = @lock == :y ? nil : :y
      when down then @lock = nil
      when 8, 127
        @pts.pop
        @base_z = nil if @pts.empty?
      when 9
        options_dialog
      else
        return false
      end
      update_status
      view.invalidate
      true
    end

    def onUserText(text, view)
      t = text.strip.downcase.tr('×*', 'xx')
      if (m = t.match(/\A(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\z/))
        @opts['shape'] = 'rect' if @kind == 'duct'
        @opts['width'] = m[1].to_f
        @opts['height'] = m[2].to_f
      elsif (m = t.match(/\Adn\s*(\d+)\z/))
        @opts['dn'] = m[1].to_i
      elsif (m = t.match(/\Ad\s*(\d+(?:\.\d+)?)\z/))
        @opts['shape'] = 'round'
        @opts['diameter'] = m[1].to_f
      elsif (m = t.match(/\Ar\s*(\d+(?:\.\d+)?)\z/))
        @opts['elbow_radius'] = m[1].to_f
      elsif (m = t.match(/\Ae\s*=?\s*(-?\d+(?:\.\d+)?)\z/))
        @opts['elevation'] = m[1].to_f
        if !@pts.empty?
          last = @pts.last
          @pts << [last[0], last[1], level_z]
        end
      elsif (m = t.match(/\Az\s*([+-]?\d+(?:\.\d+)?)\z/))
        return UI.beep if @pts.empty?
        last = @pts.last
        dz = Util.mm(m[1].to_f)
        @pts << [last[0], last[1], last[2] + dz]
        @base_z = last[2] + dz - center_offset
      elsif (m = t.match(/\A(\d+(?:\.\d+)?)\z/))
        return UI.beep if @pts.empty? || @cursor.nil?
        dir = Geo.norm(Geo.sub(@cursor, @pts.last))
        return UI.beep if Geo.len(dir) < 0.5
        @pts << Geo.add(@pts.last, Geo.mul(dir, Util.mm(m[1].to_f)))
      else
        UI.messagebox("Unknown input: #{text}\nExamples: 1200 | 400x250 | d300 | dn80 | r1.5 | e3200 | z+1500")
      end
      update_status
      view.invalidate
    end

    def add_point(p, snap, view)
      if snap && @pts.empty?
        adopt(snap)
        @pts << snap['wpos']
        lp = lead_point(snap)
        @pts << lp unless snap['run_end']
        @base_z = (@pts.last[2] - center_offset)
        # bring the run to the working elevation if the connector is horizontal
      elsif snap
        lp = snap['run_end'] ? nil : lead_point(snap)
        last = @pts.last
        if lp
          if snap['wdir'][2].abs > 0.7
            @pts << [lp[0], lp[1], last[2]]
          else
            @pts << [lp[0], lp[1], last[2]] if (lp[2] - last[2]).abs > 1.0e-3
            @pts << lp
          end
        end
        @pts << snap['wpos']
        finish(view)
        return
      else
        @base_z = p[2] - center_offset if @base_z.nil?
        @pts << p
      end
      update_status
      view.invalidate
    end

    def finish(view)
      pts = Geo.clean_path(@pts)
      if pts.size < 2
        reset
        view.invalidate
        return
      end
      tr = Util.edit_tr.inverse
      local = pts.map { |p| Util.pt_a(Util.a_pt(p).transform(tr)) }
      Util.operation("MEP: #{@kind}") do
        RunBuilder.build(Util.model.active_entities, local, @opts)
      end
      section = @kind == 'tray' ? 'tray' : @kind
      keep = @opts.reject { |k, _| %w[kind].include?(k) }
      Settings.set(section, keep)
      reset
      update_status
      view.invalidate
    end

    def options_dialog
      if @kind == 'duct'
        r = Util.ask('Duct options / تنظیمات داکت', [
                       ['System / سیستم', @opts['system'], Catalog::DUCT_SYSTEMS],
                       ['Shape (rect / round)', @opts['shape'], %w[rect round]],
                       ['Width mm / عرض', @opts['width'].to_f],
                       ['Height mm / ارتفاع', @opts['height'].to_f],
                       ['Diameter mm (round) / قطر', @opts['diameter'].to_f],
                       ['Elevation mm / تراز', @opts['elevation'].to_f],
                       ['Elevation reference / مرجع تراز', @opts['elev_ref'], %w[bottom center top]],
                       ['Elbow radius (x width, 0 = mitred)', @opts['elbow_radius'].to_f],
                       ['Insulation mm / عایق', @opts['insulation'].to_f],
                       ['Show insulation / نمایش عایق', Util.yes?(@opts['show_insulation']) ? 'Yes' : 'No', Util.bool_list]
                     ])
        return unless r
        keys = %w[system shape width height diameter elevation elev_ref elbow_radius insulation show_insulation]
        keys.each_with_index { |k, i| @opts[k] = r[i] }
        @opts['show_insulation'] = Util.yes?(r[9])
      elsif @kind == 'pipe'
        r = Util.ask('Pipe options / تنظیمات لوله', [
                       ['System / سیستم', @opts['system'], Catalog::PIPE_SYSTEMS],
                       ['Size DN / سایز', @opts['dn'].to_i.to_s, Catalog::PIPE_OD.keys.map(&:to_s)],
                       ['Elevation mm / تراز', @opts['elevation'].to_f],
                       ['Elevation reference', @opts['elev_ref'], %w[center bottom top]],
                       ['Elbow radius (x OD, 0 = mitred)', @opts['elbow_radius'].to_f],
                       ['Insulation mm / عایق', @opts['insulation'].to_f]
                     ])
        return unless r
        @opts['system'], dn, @opts['elevation'], @opts['elev_ref'], @opts['elbow_radius'], @opts['insulation'] = r
        @opts['dn'] = dn.to_i
      else
        r = Util.ask('Cable tray / سینی کابل', [
                       ['Width mm', @opts['width'].to_f], ['Height mm', @opts['height'].to_f],
                       ['Elevation mm', @opts['elevation'].to_f],
                       ['Elevation reference', @opts['elev_ref'], %w[bottom center top]]
                     ])
        return unless r
        @opts['width'], @opts['height'], @opts['elevation'], @opts['elev_ref'] = r
      end
      @opts['elbow_radius'] ||= 0
    end

    def update_status
      w, h = size_mm
      size = @kind == 'pipe' ? "DN#{@opts['dn']}" : (@opts['shape'] == 'round' ? "Ø#{w.to_i}" : "#{w.to_i}x#{h.to_i}")
      lock = @lock ? " | Lock #{@lock.to_s.upcase}" : ''
      Sketchup.set_status_text("MEP #{@kind} #{@opts['system']} #{size} @ #{@opts['elevation'].to_i} mm (#{@opts['elev_ref']})#{lock}  " \
                               '— Click points, Enter/double-click finish, Tab options, Backspace undo point, ←/→ lock axis')
      Sketchup.set_status_text('Length / Size / e / z', SB_VCB_LABEL)
      Sketchup.set_status_text('', SB_VCB_VALUE)
    end

    # ------------------------------------------------------------ drawing
    def draw(view)
      @ip.draw(view) if @ip.valid? && @ip.display? && !@snap
      pts = @pts.dup
      pts << @cursor if @cursor
      color = Catalog::SYSTEMS[@opts['system']] ? Sketchup::Color.new(*Catalog::SYSTEMS[@opts['system']][1]) : 'blue'
      if pts.size >= 2
        wpts = pts.map { |p| Util.a_pt(p) }
        view.line_width = 3
        view.drawing_color = color
        view.draw(GL_LINE_STRIP, wpts)
        # width outline
        w = Util.mm(size_mm[0]) / 2.0
        view.line_width = 1
        view.line_stipple = '-'
        [-1, 1].each do |s|
          side = []
          (0...pts.size - 1).each do |i|
            d = Geo.sub(pts[i + 1], pts[i])
            next if Geo.len(d) < 1.0e-6
            wa, = Geo.section_axes(d)
            side << Util.a_pt(Geo.add(pts[i], Geo.mul(wa, s * w)))
            side << Util.a_pt(Geo.add(pts[i + 1], Geo.mul(wa, s * w)))
          end
          view.draw(GL_LINES, side) if side.size >= 2
        end
        view.line_stipple = ''
      end
      if @cursor && @base_z
        # vertical helper from floor to run level
        view.line_width = 1
        view.drawing_color = 'gray'
        view.line_stipple = '.'
        view.draw(GL_LINES, [Util.a_pt([@cursor[0], @cursor[1], @base_z]), Util.a_pt(@cursor)])
        view.line_stipple = ''
      end
      if @snap
        view.draw_points([Util.a_pt(@snap['wpos'])], 14, 4, 'magenta')
      end
    end

    def getExtents
      bb = Geom::BoundingBox.new
      @pts.each { |p| bb.add(Util.a_pt(p)) }
      bb.add(Util.a_pt(@cursor)) if @cursor
      bb
    end
  end
end
