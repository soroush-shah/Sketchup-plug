# frozen_string_literal: true

module Banian
  module Stretch
    # Executes a Plan: moves the selected vertices and instances by a world
    # vector, descending through nested groups and components.
    #
    # The model is walked live (not through stored entity references) so
    # that Make Unique can replace definitions on the way down: copied
    # definitions are matched to the plan through Keys.
    class Applier
      OPERATION_NAME = 'Banian Stretch'

      attr_reader :moved_vertices, :moved_instances, :made_unique

      def initialize(model, plan, vector, make_unique: false)
        @model = model
        @plan = plan
        @vector = vector
        @make_unique = make_unique
        @moved_vertices = 0
        @moved_instances = 0
        @made_unique = 0
      end

      def run
        return false if @plan.empty? || !@vector.valid? || @vector.length.zero?

        @processed = {}
        @model.start_operation(OPERATION_NAME, true)
        begin
          apply(@plan.root, @model.active_entities, @model.edit_transform)
          @model.commit_operation
        rescue StandardError
          @model.abort_operation
          raise
        end
        true
      end

      private

      def apply(node, entities, transformation)
        local = transformation.inverse * @vector
        return if !local.valid? || local.length.zero?

        move = Geom::Transformation.translation(local)

        # Resolve everything before modifying this context.
        vertices = node.vertices.empty? ? [] : find_vertices(entities, node)
        moves = []
        descents = []
        unless node.instances.empty? && node.children.empty?
          entities.to_a.each do |e|
            next unless Geometry.instance?(e)

            key = Keys.instance(e)
            if node.instances.key?(key)
              moves << e
            elsif (child = node.children[key])
              descents << [e, child]
            end
          end
        end

        descents.each { |inst, child| descend(inst, child, transformation) }

        unless vertices.empty?
          entities.transform_entities(move, vertices)
          @moved_vertices += vertices.size
        end
        return if moves.empty?

        entities.transform_entities(move, moves)
        @moved_instances += moves.size
      end

      def find_vertices(entities, node)
        found = {}
        entities.to_a.each do |e|
          next unless e.is_a?(Sketchup::Edge)

          e.vertices.each do |v|
            next if found.key?(v.entityID)

            found[v.entityID] = v if node.vertices.key?(Keys.point(v.position))
          end
        end
        found.values
      end

      def descend(instance, child, parent_transformation)
        definition = instance.definition
        # A shared definition reached a second time is already edited.
        return if @processed[definition.entityID]

        if definition.count_used_instances > 1 &&
           (instance.is_a?(Sketchup::Group) || @make_unique)
          instance.make_unique
          definition = instance.definition
          @made_unique += 1
        end
        @processed[definition.entityID] = true

        apply(child, definition.entities, parent_transformation * instance.transformation)
      end
    end
  end
end
