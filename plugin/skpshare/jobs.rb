# frozen_string_literal: true
# Background-ish jobs that keep SketchUp responsive:
#  * Compressor  – runs the bundled gltfpack binary as a child process and polls it with a timer.
#  * Gzipper     – gzips + hashes a big file a few MB per timer tick.
#  * FileHasher  – incremental SHA-256.
require 'zlib'
require 'digest'
require 'rbconfig'

module SkpShare
  # Calls the block every tick until it returns true. Uses UI timers inside SketchUp,
  # and a plain loop elsewhere (tests).
  module Ticker
    module_function

    def run(&step)
      if defined?(UI) && UI.respond_to?(:start_timer)
        id = nil
        id = UI.start_timer(0.01, true) do
          begin
            done = step.call
          rescue StandardError => e
            done = true
            puts "SkpShare: #{e.class}: #{e.message}"
          end
          UI.stop_timer(id) if done
        end
      else
        loop { break if step.call }
      end
    end
  end

  class Compressor
    PRESETS = {
      # name => [texture limit, extra simplify for preview]
      'high' => 4096, 'balanced' => 2048, 'light' => 1024
    }.freeze

    def self.binary
      dir = File.join(__dir__, 'bin')
      host = RbConfig::CONFIG['host_os']
      candidates = if host =~ /mswin|mingw|cygwin/
                     [File.join(dir, 'win', 'gltfpack.exe')]
                   elsif host =~ /darwin/
                     [File.join(dir, 'mac', 'gltfpack')]
                   else
                     [File.join(dir, 'linux', 'gltfpack')]
                   end
      candidates << ENV['SKPSHARE_GLTFPACK'] if ENV['SKPSHARE_GLTFPACK']
      bin = candidates.compact.find { |c| File.exist?(c) }
      File.chmod(0o755, bin) if bin && !File.executable?(bin) rescue nil
      bin
    end

    def self.available?
      !binary.nil?
    end

    # Argument sets, best first. If a build of gltfpack lacks a feature (e.g. texture compression)
    # we fall back to the next set.
    def self.arg_sets(input, output, preset:, preview:)
      tex = PRESETS[preset] || 2048
      tex = 512 if preview
      base = ['-i', input, '-o', output, '-cc', '-ke', '-mi']
      simplify = preview ? ['-si', '0.25', '-sa'] : []
      [
        base + simplify + ['-tc', '-tl', tex.to_s, '-tq', preview ? '5' : '8'],
        base + simplify + ['-tc'],
        base + simplify,
        ['-i', input, '-o', output, '-cc'] + simplify
      ]
    end

    # Runs asynchronously; calls on_done.(ok, message)
    def self.run(input, output, preset:, preview: false, log: nil, &on_done)
      bin = binary
      return on_done.call(false, 'gltfpack not bundled') unless bin

      sets = arg_sets(input, output, preset: preset, preview: preview)
      attempt = lambda do |i|
        return on_done.call(false, 'gltfpack failed with all option sets') if i >= sets.size

        logfile = "#{output}.log"
        File.delete(output) if File.exist?(output)
        pid = Process.spawn(bin, *sets[i], out: logfile, err: [:child, :out])
        Ticker.run do
          done = Process.wait(pid, Process::WNOHANG)
          next false unless done

          ok = $?.success? && File.exist?(output) && File.size(output).positive?
          log&.call("gltfpack #{sets[i].reject { |a| a == input || a == output }.join(' ')} → #{ok ? 'ok' : 'failed'}")
          ok ? on_done.call(true, File.read(logfile)) : attempt.call(i + 1)
          true
        end
      end
      attempt.call(0)
    rescue StandardError => e
      on_done.call(false, e.message)
    end
  end

  class Gzipper
    BLOCK = 4 * 1024 * 1024

    # Gzips `src` into `dst` incrementally; yields progress (0..1); on_done.(sha256_of_dst, size_of_src)
    def self.run(src, dst, progress: nil, &on_done)
      total = File.size(src)
      input = File.open(src, 'rb')
      out = File.open(dst, 'wb')
      gz = Zlib::GzipWriter.new(out, Zlib::BEST_COMPRESSION)
      gz.orig_name = File.basename(src)
      read = 0
      Ticker.run do
        buf = input.read(BLOCK)
        if buf
          gz.write(buf)
          read += buf.bytesize
          progress&.call(total.zero? ? 1.0 : read.to_f / total)
          false
        else
          gz.close
          input.close
          FileHasher.run(dst) { |sha| on_done.call(sha, total) }
          true
        end
      end
    end
  end

  class FileHasher
    BLOCK = 8 * 1024 * 1024

    def self.run(path, &on_done)
      d = Digest::SHA256.new
      f = File.open(path, 'rb')
      Ticker.run do
        buf = f.read(BLOCK)
        if buf
          d.update(buf)
          false
        else
          f.close
          on_done.call(d.hexdigest)
          true
        end
      end
    end
  end
end
