# frozen_string_literal: true

module Banian
  module Stretch
    # A selection region in world space. Subclasses answer whether a world
    # point lies inside, and whether a set of points (the corners of a
    # bounding box) is certainly outside.
    class Region
      # Classify the 8 world-space corners of an instance's bounding box.
      # Returns :inside, :outside or :partial.
      def classify(points)
        return :inside if points.all? { |pt| contains?(pt) }
        return :outside if disjoint?(points)

        :partial
      end

      def contains?(_point)
        raise NotImplementedError
      end

      # Conservative: may return false for points that are in fact outside,
      # but never returns true when the box could reach into the region.
      def disjoint?(_points)
        false
      end
    end

    # A rectangle drawn in screen space (window selection).
    class ScreenRegion < Region
      def initialize(view, corner_a, corner_b)
        super()
        @view = view
        @xmin, @xmax = [corner_a[0], corner_b[0]].minmax
        @ymin, @ymax = [corner_a[1], corner_b[1]].minmax
        camera = view.camera
        @perspective = camera.perspective?
        @eye = camera.eye
        @direction = camera.direction
      end

      def contains?(point)
        return false unless in_front?(point)

        sp = @view.screen_coords(point)
        sp.x >= @xmin && sp.x <= @xmax && sp.y >= @ymin && sp.y <= @ymax
      end

      def disjoint?(points)
        # Points behind the camera project unpredictably; be conservative.
        return false unless points.all? { |pt| in_front?(pt) }

        xs = []
        ys = []
        points.each do |pt|
          sp = @view.screen_coords(pt)
          xs << sp.x
          ys << sp.y
        end
        xs.max < @xmin || xs.min > @xmax || ys.max < @ymin || ys.min > @ymax
      end

      def screen_corners
        [[@xmin, @ymin], [@xmax, @ymin], [@xmax, @ymax], [@xmin, @ymax]]
      end

      private

      def in_front?(point)
        return true unless @perspective

        (point - @eye) % @direction > 0.0
      end
    end

    # An oriented box in world space: origin + three orthonormal axes and
    # min/max extents along each axis.
    class BoxRegion < Region
      EPSILON = 1.0e-3 # inches; SketchUp's own geometric tolerance

      attr_reader :origin, :xaxis, :yaxis, :zaxis, :min, :max

      def initialize(origin, xaxis, yaxis, zaxis, min, max)
        super()
        @origin = origin
        @xaxis = xaxis
        @yaxis = yaxis
        @zaxis = zaxis
        @min = min.map(&:to_f)
        @max = max.map(&:to_f)
      end

      def local(point)
        v = point - @origin
        [v % @xaxis, v % @yaxis, v % @zaxis]
      end

      def contains?(point)
        l = local(point)
        3.times.all? { |i| l[i] >= @min[i] - EPSILON && l[i] <= @max[i] + EPSILON }
      end

      def disjoint?(points)
        locals = points.map { |pt| local(pt) }
        3.times.any? do |i|
          values = locals.map { |l| l[i] }
          values.max < @min[i] - EPSILON || values.min > @max[i] + EPSILON
        end
      end

      # 8 world corners, ordered like Geom::BoundingBox#corner
      # (bit 0 = x, bit 1 = y, bit 2 = z).
      def corners
        (0..7).map do |i|
          x = i & 1 == 0 ? @min[0] : @max[0]
          y = i & 2 == 0 ? @min[1] : @max[1]
          z = i & 4 == 0 ? @min[2] : @max[2]
          world(x, y, z)
        end
      end

      def world(x, y, z)
        o = @origin
        a = @xaxis
        b = @yaxis
        c = @zaxis
        Geom::Point3d.new(
          o.x + a.x * x + b.x * y + c.x * z,
          o.y + a.y * x + b.y * y + c.y * z,
          o.z + a.z * x + b.z * y + c.z * z
        )
      end
    end
  end
end
