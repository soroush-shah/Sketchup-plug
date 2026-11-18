# frozen_string_literal: true
# Orchestrates "Publish to SkpShare":
#   export GLB → thumbnails + manifest → gltfpack (full + preview) → gzip .skp → create version → chunked uploads → finalize
require 'fileutils'
require 'json'

module SkpShare
  class Publisher
    ATTR_DICT = 'skpshare'

    # target: { model_id:, project_id:, new_project_name:, new_model_name:, note: }
    # options: { preset: 'balanced', edges: true, include_skp: true, preview: true, scene_thumbs: true, hidden_tags: true }
    # ui: object responding to progress(stage, fraction, message), log(msg), done(url, summary), failed(msg)
    def initialize(model, client, target, options, ui)
      @model = model
      @client = client
      @target = target
      @opt = { preset: 'balanced', edges: true, include_skp: true, preview: true, scene_thumbs: true, hidden_tags: true }
             .merge(options.transform_keys(&:to_sym))
      @ui = ui
      @dir = File.join(Sketchup.temp_dir, "skpshare_#{Time.now.strftime('%Y%m%d%H%M%S')}")
      FileUtils.mkdir_p(@dir)
      @files = [] # [{path:, kind:, filename:, gzipped:, original_size:, sha256:}]
      @summary = {}
      @cancelled = false
    end

    def cancel
      @cancelled = true
    end

    def start
      steps = %i[export_glb capture_images compress_full compress_preview pack_skp resolve_target create_version
                 hash_files upload_files finalize]
      run_steps(steps)
    end

    private

    def run_steps(steps)
      return fail!('Cancelled') if @cancelled
      return if steps.empty?

      step = steps.first
      begin
        send(step) { run_steps(steps.drop(1)) }
      rescue StandardError => e
        fail!("#{e.message} (#{step})")
        puts e.backtrace.first(8).join("\n")
      end
    end

    def fail!(msg)
      @ui.failed(msg)
      cleanup
    end

    def cleanup
      FileUtils.rm_rf(@dir)
    rescue StandardError
      nil
    end

    def human(bytes)
      return '0 B' if bytes.nil? || bytes.zero?

      e = (Math.log(bytes) / Math.log(1024)).floor.clamp(0, 4)
      format('%.1f %s', bytes.to_f / (1024**e), %w[B KB MB GB TB][e])
    end

    # ------------------------------------------------------------------ steps

    def export_glb
      @ui.progress('export', 0.02, 'Converting geometry to GLB…')
      @raw = File.join(@dir, 'raw.glb')
      t = Time.now
      exporter = Exporter.new(@model, edges: @opt[:edges], hidden_tags: @opt[:hidden_tags],
                                      progress: ->(m) { Sketchup.status_text = m })
      @stats = exporter.export(@raw)
      @ui.log("GLB export: #{human(File.size(@raw))}, #{@stats[:faces]} faces, #{@stats[:instances]} instances in #{(Time.now - t).round(1)}s")
      @ui.progress('export', 0.15, 'Geometry exported')
      UI.start_timer(0.05, false) { yield }
    end

    def capture_images
      @ui.progress('images', 0.17, 'Capturing thumbnails…')
      thumb = File.join(@dir, 'thumb.jpg')
      view = @model.active_view
      @files << { path: thumb, kind: 'thumb', filename: 'thumb.jpg' } if view.write_image(filename: thumb, width: 800, height: 500, antialias: true, compression: 0.85)
      scene_thumbs = @opt[:scene_thumbs] ? Manifest.capture_scene_thumbs(@model, @dir) : {}
      manifest = Manifest.build(@model, @stats, scene_thumbs)
      manifest['original_skp_bytes'] = File.size(@model.path) if !@model.path.to_s.empty? && File.exist?(@model.path)
      @manifest_path = File.join(@dir, 'manifest.json')
      File.write(@manifest_path, JSON.generate(manifest))
      @files << { path: @manifest_path, kind: 'manifest', filename: 'manifest.json' }
      @ui.progress('images', 0.2, "#{manifest['scenes'].size} scenes, #{manifest['section_planes'].size} section planes, #{manifest['bom'].size} components")
      UI.start_timer(0.05, false) { yield }
    end

    def compress_full(&nxt)
      full = File.join(@dir, 'full.glb')
      unless Compressor.available?
        @ui.log('gltfpack not found – uploading uncompressed GLB (still instanced).')
        @files << { path: @raw, kind: 'full', filename: 'model.glb' }
        return nxt.call
      end
      @ui.progress('compress', 0.22, "Compressing (#{@opt[:preset]})… this can take a while for big models")
      Compressor.run(@raw, full, preset: @opt[:preset], log: ->(m) { @ui.log(m) }) do |ok, msg|
        if ok
          @summary[:raw] = File.size(@raw)
          @summary[:full] = File.size(full)
          @ui.log("Compressed GLB: #{human(@summary[:raw])} → #{human(@summary[:full])}")
          @files << { path: full, kind: 'full', filename: 'model.glb' }
        else
          @ui.log("Compression failed (#{msg.to_s[0, 300]}) – using uncompressed GLB")
          @files << { path: @raw, kind: 'full', filename: 'model.glb' }
        end
        @ui.progress('compress', 0.4, 'Compressed')
        nxt.call
      end
    end

    def compress_preview(&nxt)
      return nxt.call unless @opt[:preview] && Compressor.available?

      prev = File.join(@dir, 'preview.glb')
      @ui.progress('compress', 0.42, 'Building quick-open preview…')
      Compressor.run(@raw, prev, preset: 'light', preview: true, log: ->(m) { @ui.log(m) }) do |ok, _msg|
        full = @files.find { |f| f[:kind] == 'full' }
        # A preview only helps when it is clearly smaller than the full model.
        if ok && File.size(prev) < File.size(full[:path]) * 0.6
          @files << { path: prev, kind: 'preview', filename: 'preview.glb' }
          @ui.log("Preview GLB: #{human(File.size(prev))}")
        end
        @ui.progress('compress', 0.5, 'Preview ready')
        nxt.call
      end
    end

    def pack_skp(&nxt)
      return nxt.call unless @opt[:include_skp]

      @ui.progress('skp', 0.5, 'Saving a copy of the .skp…')
      name = @model.title.to_s.empty? ? 'model' : @model.title
      copy = File.join(@dir, "#{name.gsub(/[^\w\- ]/, '_')}.skp")
      @model.save_copy(copy)
      gz = "#{copy}.gz"
      Gzipper.run(copy, gz, progress: ->(f) { @ui.progress('skp', 0.5 + f * 0.1, "Compressing .skp #{(f * 100).round}%") }) do |sha, orig|
        @summary[:skp] = orig
        @summary[:skp_gz] = File.size(gz)
        @ui.log("SKP: #{human(orig)} → #{human(File.size(gz))} (gzip)")
        File.delete(copy)
        @files << { path: gz, kind: 'skp', filename: File.basename(copy), gzipped: true, original_size: orig, sha256: sha }
        nxt.call
      end
    end

    def resolve_target(&nxt)
      @ui.progress('server', 0.61, 'Contacting server…')
      return nxt.call if @target[:model_id]

      with_project = lambda do |pid|
        @client.call('POST', '/api/models', { project_id: pid, name: @target[:new_model_name] || @model.title }) do |res, err|
          next fail!(err.message) if err

          @target[:model_id] = res['id']
          nxt.call
        end
      end
      if @target[:project_id]
        with_project.call(@target[:project_id])
      else
        @client.call('POST', '/api/projects', { name: @target[:new_project_name] || 'SketchUp uploads' }) do |res, err|
          next fail!(err.message) if err

          with_project.call(res['id'])
        end
      end
    end

    def create_version(&nxt)
      stats = @stats.reject { |k, _| k == :tags }.merge(@summary)
      @client.call('POST', "/api/models/#{@target[:model_id]}/versions", { note: @target[:note], stats: stats, source: 'plugin' }) do |res, err|
        next fail!(err.message) if err

        @version_id = res['id']
        @ui.log("Creating version #{res['version_no']}")
        nxt.call
      end
    end

    def hash_files(&nxt)
      todo = @files.reject { |f| f[:sha256] }
      return nxt.call if todo.empty?

      f = todo.first
      FileHasher.run(f[:path]) do |sha|
        f[:sha256] = sha
        hash_files(&nxt)
      end
    end

    def upload_files(&nxt)
      # Small files first so the model becomes viewable as early as possible.
      order = %w[manifest thumb preview full skp]
      queue = @files.sort_by { |f| order.index(f[:kind]) || 99 }
      total = queue.sum { |f| File.size(f[:path]) }
      done_bytes = 0
      upload_next = nil
      upload_next = lambda do
        return nxt.call if queue.empty?
        return fail!('Cancelled') if @cancelled

        f = queue.first
        size = File.size(f[:path])
        @ui.progress('upload', 0.62 + 0.36 * done_bytes / total, "Uploading #{f[:kind]} (#{human(size)})…")
        @client.upload_file(f[:path], version_id: @version_id, kind: f[:kind], filename: f[:filename], sha256: f[:sha256],
                                      gzipped: f[:gzipped], original_size: f[:original_size],
                                      progress: lambda { |sent, _t|
                                        frac = (done_bytes + sent).to_f / total
                                        @ui.progress('upload', 0.62 + 0.36 * frac, "Uploading #{f[:kind]} #{human(sent)} / #{human(size)}")
                                      }) do |_res, err|
          if err && err.message =~ /checksum mismatch/i && !@client.transport.is_a?(NetHttpTransport)
            @ui.log('Switching upload engine to Ruby Net::HTTP and resuming…')
            @client.transport = NetHttpTransport.new
            next upload_next.call
          end
          next fail!(err.message) if err

          done_bytes += size
          queue.shift
          upload_next.call
        end
      end
      upload_next.call
    end

    def finalize
      @client.call('POST', "/api/versions/#{@version_id}/finalize") do |res, err|
        next fail!(err.message) if err

        @model.set_attribute(ATTR_DICT, 'model_id', @target[:model_id])
        @model.set_attribute(ATTR_DICT, 'server', @client.base_url)
        url = "#{@client.base_url}/m/#{@target[:model_id]}"
        @ui.progress('done', 1.0, 'Published!')
        @ui.done(url, @summary.merge(view_bytes: @files.select { |f| %w[full preview].include?(f[:kind]) }.sum { |f| File.size(f[:path]) }))
        cleanup
      end
    end
  end
end
