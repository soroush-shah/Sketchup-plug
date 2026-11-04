# frozen_string_literal: true

module Banian
  module Stretch
    # Catches errors raised inside tool callbacks. SketchUp otherwise only
    # prints them to the Ruby Console and the tool silently stops working.
    # Errors are written to the Ruby Console and a log file, and the first
    # occurrence of each error is shown in a message box.
    module ErrorReporter
      LOG_NAME = 'banian_stretch_log.txt'

      @shown = {}

      class << self
        def log_path
          dir = Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir : ENV.fetch('TMP', '.')
          File.join(dir, LOG_NAME)
        rescue StandardError
          LOG_NAME
        end

        def report(error, where)
          key = "#{where}|#{error.class}|#{error.message}"
          count = (@shown[key] || 0) + 1
          @shown[key] = count
          return if count > 3 # draw/mouse callbacks repeat many times a second

          trace = (error.backtrace || []).first(12)
          text = "[#{Time.now}] SketchUp #{sketchup_version} - #{where}: #{error.class}: " \
                 "#{error.message}\n  #{trace.join("\n  ")}\n"
          warn("Banian Stretch error in #{text}")
          write_log(text)
          return unless count == 1

          UI.messagebox("Banian Stretch #{VERSION} - error in #{where}:\n\n" \
                        "#{error.class}: #{error.message}\n#{trace.first}\n\n" \
                        "Details were saved to:\n#{log_path}\n\n" \
                        'Please send this message (or the log file) to the developer.')
        rescue StandardError
          nil
        end

        # Wrap the tool callbacks of `klass` so errors are reported instead of
        # breaking the tool. Only callbacks the class already responds to are
        # wrapped, so SketchUp's respond_to? checks are unchanged.
        def guard(klass, names)
          wrapper = Module.new
          names.each do |name|
            next unless klass.method_defined?(name)

            label = "#{klass.name.to_s.split('::').last}##{name}"
            wrapper.send(:define_method, name) do |*args, &block|
              super(*args, &block)
            rescue StandardError => e
              ErrorReporter.report(e, label)
              ErrorReporter.recover(self, name)
            end
          end
          klass.prepend(wrapper)
        end

        def recover(tool, name)
          case name
          when :getExtents
            Sketchup.active_model.bounds
          when :draw, :onSetCursor
            nil
          else
            tool.send(:reset) if tool.respond_to?(:reset, true)
            tool.send(:update_ui) if tool.respond_to?(:update_ui, true)
            false
          end
        rescue StandardError
          nil
        end

        private

        def sketchup_version
          Sketchup.version
        rescue StandardError
          '?'
        end

        def write_log(text)
          File.open(log_path, 'a:UTF-8') { |f| f.write(text) }
        rescue StandardError
          nil
        end
      end
    end
  end
end
