# encoding: UTF-8
# Banian Profile Builder - tiny 3D vector helpers on plain arrays.
# Pure Ruby (no SketchUp API) so the geometry engine is fast and testable.

module BanianStudio
  module ProfileBuilder
    module Vec
      module_function

      def add(a, b)
        [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
      end

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
      end

      def mul(a, s)
        [a[0] * s, a[1] * s, a[2] * s]
      end

      def dot(a, b)
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
      end

      def cross(a, b)
        [a[1] * b[2] - a[2] * b[1],
         a[2] * b[0] - a[0] * b[2],
         a[0] * b[1] - a[1] * b[0]]
      end

      def len(a)
        Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
      end

      def dist(a, b)
        len(sub(a, b))
      end

      # Returns nil for (near) zero vectors.
      def norm(a)
        l = len(a)
        return nil if l < 1e-12
        [a[0] / l, a[1] / l, a[2] / l]
      end

      def lerp(a, b, t)
        [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
      end

      # Point + u * r + v * w (used to place a 2D profile in a 3D frame).
      def frame_point(o, r, u, w, v)
        [o[0] + r[0] * u + w[0] * v,
         o[1] + r[1] * u + w[1] * v,
         o[2] + r[2] * u + w[2] * v]
      end
    end
  end
end
