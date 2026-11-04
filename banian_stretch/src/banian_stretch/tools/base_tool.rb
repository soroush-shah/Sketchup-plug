# frozen_string_literal: true

module Banian
  module Stretch
    module Colors
      SELECTION = Sketchup::Color.new(0, 122, 255)
      SHARED = Sketchup::Color.new(230, 40, 40)
      PRESELECTION = Sketchup::Color.new(0, 165, 80)
      REGION = Sketchup::Color.new(0, 122, 255)
      REGION_FILL = Sketchup::Color.new(0, 122, 255, 35)
      HOVER = Sketchup::Color.new(255, 150, 0)
      GHOST = Sketchup::Color.new(140, 140, 140)
      GUIDE = Sketchup::Color.new(40, 40, 40)
      AXIS_X = Sketchup::Color.new(220, 0, 0)
      AXIS_Y = Sketchup::Color.new(0, 170, 0)
      AXIS_Z = Sketchup::Color.new(0, 0, 230)
    end

    # Shared behaviour of the three stretch tools: the selection plan, the
    # move phase (start point -> end point, inference, axis locks, VCB),
    # drawing of the preview and the status bar.
    #
    # Subclasses implement the selection phase.
    class BaseTool
      CLICK_TOLERANCE = 4 # pixels before a press becomes a drag
      TAB_KEY = 9
      # SketchUp callbacks wrapped by ErrorReporter.guard in each tool class.
      CALLBACKS = %i[
        activate deactivate resume suspend onCancel onKeyDown onKeyUp onUserText
        getExtents draw onMouseMove onLButtonDown onLButtonUp
      ].freeze
      MAC = Sketchup.platform == :platform_osx
      ADD_KEY = MAC ? 'Option' : 'Ctrl'

      def initialize
        @ip = Sketchup::InputPoint.new
        @ip_start = Sketchup::InputPoint.new
        @axis_lock = nil
        @state = nil
      end

      # --- SketchUp tool interface ------------------------------------------

      def activate
        @model = Sketchup.active_model
        capture_preselection
        reset
        update_ui
        @model.active_view.invalidate
      end

      def deactivate(view)
        view.lock_inference if view.inference_locked?
        view.invalidate
      end

      def resume(view)
        update_ui
        view.invalidate
      end

      def suspend(view)
        view.invalidate
      end

      def onCancel(reason, view)
        if reason == 2 # undo: stored references may be stale
          capture_preselection
          reset
        elsif @state == :move
          cancel_move(view)
        else
          step_back
        end
        update_ui
        view.invalidate
      end

      def onKeyDown(key, repeat, flags, view)
        if @state == :move
          move_key_down(key, repeat, view)
        else
          selection_key_down(key, repeat, flags, view)
        end
        false
      end

      def onKeyUp(key, _repeat, _flags, view)
        return false unless @state == :move && key == CONSTRAIN_MODIFIER_KEY

        view.lock_inference if view.inference_locked?
        view.invalidate
        false
      end

      def onUserText(text, view)
        if @state == :move
          typed_distance(text, view)
        else
          selection_text(text, view)
        end
        update_ui
        view.invalidate
      end

      def enableVCB?
        true
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(@model.bounds) unless @model.bounds.empty?
        if @preview
          vector = moving_vector
          @preview.points.each do |pt|
            bb.add(pt)
            bb.add(pt + vector) if vector
          end
        end
        extra_points.each { |pt| bb.add(pt) }
        @preselection_corners&.each { |pt| bb.add(pt) }
        bb
      end

      def draw(view)
        draw_preselection(view)
        draw_overlay(view)
        draw_preview(view, moving_vector)
        return unless @state == :move

        draw_move_guide(view)
        @ip.draw(view) if @ip.display?
      end

      # --- Hooks for subclasses ---------------------------------------------

      def reset
        @plan = new_plan
        @preview = Preview.new(nil)
        @axis_lock = nil
        @vector = nil
      end

      def step_back
        reset
      end

      def selection_key_down(_key, _repeat, _flags, _view); end

      def selection_text(_text, _view)
        UI.beep
      end

      def draw_overlay(_view); end

      def extra_points
        []
      end

      def selection_status
        ''
      end

      def selection_vcb
        ['', '']
      end

      protected

      # --- Plan --------------------------------------------------------------

      def new_plan
        Plan.new(@model, @preselection)
      end

      def plan_changed
        @preview = Preview.new(@plan)
        update_ui
      end

      def capture_preselection
        @preselection = Preselection.capture(@model)
        @preselection_corners = @preselection&.corners
      end

      def selection_mode(flags)
        return :remove if flags & CONSTRAIN_MODIFIER_MASK != 0
        return :add if flags & COPY_MODIFIER_MASK != 0

        :replace
      end

      # Ctrl/Option-click adds and Shift-click removes the picked edge/face.
      def toggle_pick(view, x, y, mode)
        hit = pick_entity(view, x, y)
        return UI.beep unless hit

        @plan.apply_pick(hit[0], hit[1], mode == :remove ? :remove : :add)
        plan_changed
      end

      # Pick an edge or face, at any depth. Returns
      # [instances_from_active_context, entity, world_transformation] or nil.
      def pick_entity(view, x, y, faces_only: false, respect_filters: true)
        ph = view.pick_helper
        ph.do_pick(x, y)
        filters = Settings.filters
        target = nil
        if !faces_only && (!respect_filters || filters[:edges] || filters[:vertices])
          target = ph.picked_edge
        end
        target ||= ph.picked_face if !respect_filters || filters[:faces]
        return nil unless target

        index = (0...ph.count).find { |i| ph.leaf_at(i) == target }
        return nil unless index

        # The pick path lists the instances down to the leaf (the leaf itself
        # may or may not be included, so keep only groups/components).
        instances = ph.path_at(index).to_a.select { |e| Geometry.instance?(e) }
        active = (@model.active_path || []).to_a
        if !active.empty? && instances.first(active.size) == active
          instances = instances.drop(active.size)
        end
        return nil if instances.any?(&:locked?)

        root = instances.first || target
        active_parent = active.empty? ? @model : active.last.definition
        return nil unless root.parent == active_parent

        tr = instances.inject(Geometry.context_transformation(@model)) { |t, i| t * i.transformation }
        [instances, target, tr]
      end

      # --- Move phase --------------------------------------------------------

      def start_move(view, x, y)
        @ip_start.pick(view, x, y)
        return UI.beep unless @ip_start.valid?

        @start = @ip_start.position
        @ip.copy!(@ip_start)
        @state_before_move = @state
        @state = :move
        @vector = nil
        @axis_lock = nil
        update_ui
      end

      def move_mouse(view, x, y)
        @ip.pick(view, x, y, @ip_start)
        view.tooltip = @ip.tooltip if @ip.valid?
        target = move_target(view, x, y)
        @vector = target ? target - @start : nil
        Sketchup.vcb_value = Sketchup.format_length(@vector ? @vector.length : 0)
      end

      def finish_move(view)
        unless @vector&.valid? && !@vector.length.zero?
          cancel_move(view)
          return
        end
        commit(@vector, view)
      end

      def cancel_move(view)
        view.lock_inference if view.inference_locked?
        @state = @state_before_move
        @vector = nil
        @axis_lock = nil
        update_ui
      end

      def commit(vector, view)
        view.lock_inference if view.inference_locked?
        Applier.new(@model, @plan, vector, make_unique: Settings.make_unique?).run
      rescue StandardError => e
        warn("Banian Stretch: #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
        UI.messagebox("#{I18n.t(:error_apply)}\n#{e.message}")
      ensure
        capture_preselection
        reset
        update_ui
        view.invalidate
      end

      def moving_vector
        return nil unless @state == :move && @vector&.valid?

        @vector
      end

      private

      def move_target(view, x, y)
        return (@ip.valid? ? @ip.position : nil) unless @axis_lock

        line = [@start, @axis_lock]
        if @ip.valid? && @ip.degrees_of_freedom.zero?
          @ip.position.project_to_line(line)
        else
          Geom.closest_points(line, view.pickray(x, y)).first
        end
      end

      def move_key_down(key, repeat, view)
        if key == CONSTRAIN_MODIFIER_KEY && repeat == 1
          if view.inference_locked?
            view.lock_inference
          elsif @ip.valid?
            view.lock_inference(@ip, @ip_start)
          end
        else
          axes = @model.axes
          axis = { VK_RIGHT => axes.xaxis, VK_LEFT => axes.yaxis, VK_UP => axes.zaxis }[key]
          if axis
            @axis_lock = @axis_lock&.parallel?(axis) ? nil : axis
          elsif key == VK_DOWN
            @axis_lock = nil
          end
        end
        view.invalidate
      end

      def typed_distance(text, view)
        length = parse_length(text)
        return unless length

        direction = @vector&.valid? && !@vector.length.zero? ? @vector : @axis_lock
        return UI.beep unless direction && !length.zero?

        vector = direction.normalize
        vector = vector.reverse if length.negative?
        vector.length = length.abs
        commit(vector, view)
      end

      def parse_length(text)
        text.to_s.strip.to_l
      rescue ArgumentError
        UI.beep
        Sketchup.set_status_text("Invalid length: #{text}", SB_PROMPT)
        nil
      end

      # --- UI ----------------------------------------------------------------

      def update_ui
        Sketchup.status_text = status_text
        if @state == :move
          Sketchup.vcb_label = 'Distance'
          Sketchup.vcb_value = Sketchup.format_length(@vector ? @vector.length : 0)
        else
          label, value = selection_vcb
          Sketchup.vcb_label = label
          Sketchup.vcb_value = value
        end
      end

      def status_text
        text =
          if @state == :move
            'Click the end point or type a distance (negative = reverse). ' \
              'Arrows lock the X/Y/Z axis, hold Shift to lock inference, Esc cancels.'
          else
            selection_status
          end
        info = plan_summary
        info.empty? ? text : "#{text}   |   #{info}"
      end

      def plan_summary
        return '' if @plan.nil? || @plan.empty?

        parts = []
        vertices = @plan.vertex_count
        instances = @plan.instance_count
        parts << "#{vertices} vertices" if vertices.positive?
        parts << "#{instances} objects" if instances.positive?
        text = "Selected: #{parts.join(', ')}"
        if @plan.shared? && !Settings.make_unique?
          text += '   |   WARNING: red geometry is in shared components and ' \
                  'will change in every copy (Make Unique is off)'
        end
        text
      end

      # --- Drawing -----------------------------------------------------------
      #
      # Everything is projected to the screen and drawn with draw2d so the
      # highlight is always on top. 3D lines drawn exactly over the model's
      # own edges are hidden by the depth test, which made the selection look
      # empty.

      MARKER_SIZE = 4 # half size in pixels

      # Draw 3D points on top of the model. GL_LINES takes point pairs; other
      # modes take one polygon/loop.
      def draw_on_top(view, mode, points)
        return if points.nil? || points.empty?

        camera = view.camera
        eye = camera.perspective? ? camera.eye : nil
        dir = camera.direction
        front = ->(pt) { eye.nil? || (pt - eye) % dir > 0.0 }
        screen = lambda do |pt|
          sp = view.screen_coords(pt)
          Geom::Point3d.new(sp.x, sp.y, 0)
        end

        pts =
          if mode == GL_LINES
            out = []
            points.each_slice(2) do |a, b|
              next unless b && front.call(a) && front.call(b)

              out << screen.call(a) << screen.call(b)
            end
            out
          else
            return unless points.all? { |pt| front.call(pt) }

            points.map { |pt| screen.call(pt) }
          end
        view.draw2d(mode, pts) unless pts.empty?
      end

      def draw_squares(view, points, color, size = MARKER_SIZE)
        return if points.empty?

        camera = view.camera
        eye = camera.perspective? ? camera.eye : nil
        dir = camera.direction
        quads = []
        points.each do |pt|
          next unless eye.nil? || (pt - eye) % dir > 0.0

          sp = view.screen_coords(pt)
          x = sp.x
          y = sp.y
          quads << Geom::Point3d.new(x - size, y - size, 0) << Geom::Point3d.new(x + size, y - size, 0) <<
            Geom::Point3d.new(x + size, y + size, 0) << Geom::Point3d.new(x - size, y + size, 0)
        end
        return if quads.empty?

        view.drawing_color = color
        view.draw2d(GL_QUADS, quads)
      end

      def draw_preselection(view)
        return unless @preselection_corners

        view.drawing_color = Colors::PRESELECTION
        view.line_width = 1
        view.line_stipple = '-'
        draw_on_top(view, GL_LINES, Geometry.box_segments(@preselection_corners))
        view.line_stipple = ''
      end

      def draw_preview(view, vector)
        return if @preview.nil? || @preview.empty?

        warn_shared = !Settings.make_unique?
        normal = []
        shared = []
        ghost = []
        @preview.segments.each do |s|
          a = vector && s.a_moves ? s.a + vector : s.a
          b = vector && s.b_moves ? s.b + vector : s.b
          (s.shared && warn_shared ? shared : normal) << a << b
          ghost << s.a << s.b if vector && (s.a_moves || s.b_moves)
        end

        unless ghost.empty?
          view.drawing_color = Colors::GHOST
          view.line_width = 1
          view.line_stipple = '-'
          draw_on_top(view, GL_LINES, ghost)
        end

        view.line_stipple = ''
        view.line_width = 3
        draw_lines(view, normal, Colors::SELECTION)
        draw_lines(view, shared, Colors::SHARED)

        unless @preview.boxes.empty?
          view.line_width = 2
          view.line_stipple = '-'
          boxes = []
          @preview.boxes.each do |box|
            corners = vector ? box.corners.map { |c| c + vector } : box.corners
            boxes.concat(Geometry.box_segments(corners))
          end
          draw_lines(view, boxes, Colors::SELECTION)
          view.line_stipple = ''
        end

        draw_markers(view, vector, warn_shared)
        view.line_width = 1
      end

      def draw_markers(view, vector, warn_shared)
        normal = []
        shared = []
        @preview.markers.each do |m|
          pt = vector ? m.point + vector : m.point
          (m.shared && warn_shared ? shared : normal) << pt
        end
        draw_squares(view, normal, Colors::SELECTION)
        draw_squares(view, shared, Colors::SHARED)
      end

      def draw_lines(view, points, color)
        return if points.empty?

        view.drawing_color = color
        draw_on_top(view, GL_LINES, points)
      end

      def draw_move_guide(view)
        return unless @vector&.valid?

        target = @start + @vector
        color = Colors::GUIDE
        if @axis_lock
          axes = @model.axes
          color = if @axis_lock.parallel?(axes.xaxis) then Colors::AXIS_X
                  elsif @axis_lock.parallel?(axes.yaxis) then Colors::AXIS_Y
                  else Colors::AXIS_Z
                  end
        end
        view.drawing_color = color
        view.line_width = @axis_lock ? 2 : 1
        view.line_stipple = '_'
        draw_on_top(view, GL_LINES, [@start, target])
        view.line_stipple = ''
        view.line_width = 1
        draw_squares(view, [@start], Colors::GUIDE, 3)
      end

      # Highlight the edge/face that a click would pick.
      def draw_hover(view, hit)
        return unless hit

        _path, entity, tr = hit
        return unless entity.valid?

        view.drawing_color = Colors::HOVER
        view.line_width = 3
        view.line_stipple = ''
        if entity.is_a?(Sketchup::Edge)
          draw_on_top(view, GL_LINES, [tr * entity.start.position, tr * entity.end.position])
        else
          draw_on_top(view, GL_LINE_LOOP, entity.outer_loop.vertices.map { |v| tr * v.position })
        end
        view.line_width = 1
      end
    end
  end
end
