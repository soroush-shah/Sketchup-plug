# frozen_string_literal: true

module Banian
  module Stretch
    # Stable keys that identify geometry independently of Ruby object
    # identity. They survive Make Unique: a copied definition contains copies
    # of the same vertices (same local positions) and the same child
    # instances (same definition + same transformation).
    module Keys
      POINT_PRECISION = 6
      TRANSFORM_PRECISION = 7

      def self.point(pt)
        [pt.x.to_f.round(POINT_PRECISION), pt.y.to_f.round(POINT_PRECISION), pt.z.to_f.round(POINT_PRECISION)]
      end

      def self.instance(instance)
        values = instance.transformation.to_a.map { |c| c.to_f.round(TRANSFORM_PRECISION) }
        "#{instance.definition.entityID}|#{values.join(',')}"
      end
    end

    # Small geometry helpers shared by the plan, preview and tools.
    module Geometry
      module_function

      # World transformation of the active editing context.
      #
      # While the user has a group/component open for editing, SketchUp's Ruby
      # API reports the positions (and child transformations) of the entities
      # in that open context in WORLD coordinates, not local ones. So the
      # active context is always treated as world space (identity).
      def context_transformation(_model)
        Geom::Transformation.new
      end

      def instance?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def tag_visible?(entity)
        layer = entity.respond_to?(:layer) ? entity.layer : nil
        return true if layer.nil?
        return false if layer.respond_to?(:visible?) && !layer.visible?

        folder = layer.respond_to?(:folder) ? layer.folder : nil
        while folder
          return false if folder.respond_to?(:visible?) && !folder.visible?

          folder = folder.respond_to?(:folder) ? folder.folder : nil
        end
        true
      end

      # Instances the user can see and is allowed to edit.
      def selectable_instance?(entity)
        return false unless instance?(entity)
        return false if entity.respond_to?(:hidden?) && entity.hidden?
        return false if entity.respond_to?(:locked?) && entity.locked?

        tag_visible?(entity)
      end

      # World-space corners of an instance's bounding box, or nil if empty.
      def instance_corners(instance, parent_transformation)
        bounds = instance.definition.bounds
        return nil if bounds.empty?

        tr = parent_transformation * instance.transformation
        (0..7).map { |i| tr * bounds.corner(i) }
      end

      # Unit normal of a polygon (Newell's method); nil when degenerate.
      def polygon_normal(points)
        nx = ny = nz = 0.0
        count = points.size
        count.times do |i|
          a = points[i]
          b = points[(i + 1) % count]
          nx += (a.y - b.y) * (a.z + b.z)
          ny += (a.z - b.z) * (a.x + b.x)
          nz += (a.x - b.x) * (a.y + b.y)
        end
        normal = Geom::Vector3d.new(nx, ny, nz)
        return nil if normal.length < 1.0e-9

        normal.normalize
      end

      # Pairs of corner indices forming the 12 edges of a box.
      BOX_EDGES = [[0, 1], [2, 3], [4, 5], [6, 7],
                   [0, 2], [1, 3], [4, 6], [5, 7],
                   [0, 4], [1, 5], [2, 6], [3, 7]].freeze

      def box_segments(corners)
        BOX_EDGES.flat_map { |a, b| [corners[a], corners[b]] }
      end
    end

    # The entities the user pre-selected before activating a tool. Only
    # these (and everything nested inside them) can be stretched.
    class Preselection
      def self.capture(model)
        entities = model.selection.to_a
        return nil if entities.empty?

        new(model, entities)
      end

      attr_reader :entities

      def initialize(model, entities)
        @model = model
        @entities = entities
        @ids = {}
        @vertex_ids = {}
        entities.each do |e|
          @ids[e.entityID] = true
          next unless e.is_a?(Sketchup::Edge) || e.is_a?(Sketchup::Face)

          e.vertices.each { |v| @vertex_ids[v.entityID] = true }
        end
      end

      def entity?(entity)
        @ids.key?(entity.entityID)
      end

      def vertex?(vertex)
        @vertex_ids.key?(vertex.entityID)
      end

      def valid?
        @entities.any?(&:valid?)
      end

      # World corners of the preselection bounding box, or nil.
      def corners
        bb = Geom::BoundingBox.new
        @entities.each { |e| bb.add(e.bounds) if e.valid? && e.respond_to?(:bounds) }
        return nil if bb.empty?

        tr = Geometry.context_transformation(@model)
        (0..7).map { |i| tr * bb.corner(i) }
      end
    end

    # One editing context of the plan: the active entities (root) or the
    # entities of a nested instance's definition.
    class Node
      attr_reader :entities, :transformation, :path, :vertices, :instances, :children

      # entities       - Sketchup::Entities of this context
      # transformation - world transformation of this context
      # path           - live instances leading from the active context here
      def initialize(entities, transformation, path)
        @entities = entities
        @transformation = transformation
        @path = path
        @vertices = {}   # Keys.point(local position) => Sketchup::Vertex
        @instances = {}  # Keys.instance => instance moved as a whole
        @children = {}   # Keys.instance => Node (instance edited inside)
      end

      def child(instance)
        key = Keys.instance(instance)
        @children[key] ||= Node.new(
          instance.definition.entities,
          @transformation * instance.transformation,
          @path + [instance]
        )
      end

      def existing_child(instance)
        @children[Keys.instance(instance)]
      end

      def empty?
        @vertices.empty? && @instances.empty? && @children.empty?
      end

      # Remove empty child nodes; returns self.
      def prune!
        @children.delete_if do |_key, node|
          node.prune!
          node.empty?
        end
        self
      end

      # True when editing this context changes other copies too (a component
      # definition used more than once, and Make Unique is off).
      def shared?
        @path.any? do |inst|
          inst.valid? && inst.is_a?(Sketchup::ComponentInstance) &&
            inst.definition.count_used_instances > 1
        end
      end
    end

    # What will be stretched. Built from region and pick selections.
    class Plan
      attr_reader :root

      def initialize(model, preselection = nil)
        @model = model
        @preselection = preselection
        @root = Node.new(model.active_entities, Geometry.context_transformation(model), [])
      end

      def empty?
        @root.empty?
      end

      def each_node(node = @root, &block)
        yield node
        node.children.each_value { |c| each_node(c, &block) }
      end

      def vertex_count
        count = 0
        each_node { |n| count += n.vertices.size }
        count
      end

      def instance_count
        count = 0
        each_node { |n| count += n.instances.size }
        count
      end

      def shared?
        found = false
        each_node { |n| found ||= (!n.vertices.empty? || !n.instances.empty?) && n.shared? }
        found
      end

      # mode: :add or :remove. filters: hash from Settings.filters.
      def apply_region(region, filters, mode)
        walk_region(@root, region, filters, mode, true)
        @root.prune!
        self
      end

      # Add or remove the vertices of a picked edge or face.
      # path - instances from the active context down to the entity's parent.
      def apply_pick(path, entity, mode)
        return self unless pick_allowed?(path, entity)

        node = @root
        path.each do |inst|
          if mode == :add
            node.instances.delete(Keys.instance(inst))
            node = node.child(inst)
          else
            node = node.existing_child(inst)
            return self unless node
          end
        end
        entity.vertices.each do |v|
          key = Keys.point(v.position)
          if mode == :add
            node.vertices[key] = v
          else
            node.vertices.delete(key)
          end
        end
        @root.prune!
        self
      end

      private

      def pick_allowed?(path, entity)
        return true unless @preselection

        if path.empty?
          @preselection.entity?(entity) || entity.vertices.all? { |v| @preselection.vertex?(v) }
        else
          @preselection.entity?(path.first)
        end
      end

      def walk_region(node, region, filters, mode, root)
        tr = node.transformation
        presel = root ? @preselection : nil
        cache = {}
        inside = lambda do |v|
          id = v.entityID
          cache.fetch(id) do
            ok = (presel.nil? || presel.vertex?(v)) && region.contains?(tr * v.position)
            cache[id] = ok
          end
        end

        picked = {}
        node.entities.each do |e|
          case e
          when Sketchup::Edge
            vs = e.vertices
            if filters[:vertices]
              vs.each { |v| picked[v.entityID] = v if inside.call(v) }
            elsif filters[:edges] && vs.all? { |v| inside.call(v) }
              vs.each { |v| picked[v.entityID] = v }
            end
          when Sketchup::Face
            next unless filters[:faces]

            vs = e.vertices
            vs.each { |v| picked[v.entityID] = v } if vs.all? { |v| inside.call(v) }
          else
            next unless Geometry.selectable_instance?(e)
            next if presel && !presel.entity?(e)

            walk_instance(node, e, region, filters, mode)
          end
        end

        picked.each_value do |v|
          key = Keys.point(v.position)
          if mode == :add
            node.vertices[key] = v
          else
            node.vertices.delete(key)
          end
        end
      end

      def walk_instance(node, inst, region, filters, mode)
        corners = Geometry.instance_corners(inst, node.transformation)
        return unless corners

        case region.classify(corners)
        when :inside
          return unless filters[:instances]

          key = Keys.instance(inst)
          node.children.delete(key)
          if mode == :add
            node.instances[key] = inst
          else
            node.instances.delete(key)
          end
        when :partial
          key = Keys.instance(inst)
          if mode == :add
            return if node.instances.key?(key) # already moving as a whole

            walk_region(node.child(inst), region, filters, mode, false)
          else
            node.instances.delete(key)
            child = node.existing_child(inst)
            walk_region(child, region, filters, mode, false) if child
          end
        end
      end
    end

    # Pre-computed drawing data for a plan (world space, before the move).
    class Preview
      Segment = Struct.new(:a, :a_moves, :b, :b_moves, :shared)
      Box = Struct.new(:corners, :shared)
      Marker = Struct.new(:point, :shared)

      MAX_SEGMENTS = 40_000

      attr_reader :segments, :markers, :boxes

      def initialize(plan)
        @segments = []
        @markers = []
        @boxes = []
        build(plan) if plan
      end

      def empty?
        @segments.empty? && @markers.empty? && @boxes.empty?
      end

      def shared?
        @segments.any?(&:shared) || @markers.any?(&:shared)
      end

      # All world points (for View#getExtents).
      def points
        pts = @markers.map(&:point)
        @segments.each { |s| pts << s.a << s.b }
        @boxes.each { |b| pts.concat(b.corners) }
        pts
      end

      private

      def build(plan)
        plan.each_node do |node|
          tr = node.transformation
          shared = node.shared?
          selected = {}
          node.vertices.each_value { |v| selected[v.entityID] = v if v.valid? }
          edges = {}
          selected.each_value do |v|
            @markers << Marker.new(tr * v.position, shared)
            v.edges.each { |e| edges[e.entityID] = e }
          end
          edges.each_value do |e|
            break if @segments.size >= MAX_SEGMENTS

            a = e.start
            b = e.end
            @segments << Segment.new(tr * a.position, selected.key?(a.entityID),
                                     tr * b.position, selected.key?(b.entityID), shared)
          end
          node.instances.each_value do |inst|
            next unless inst.valid?

            corners = Geometry.instance_corners(inst, tr)
            @boxes << Box.new(corners, false) if corners
          end
        end
      end
    end
  end
end
