# frozen_string_literal: true
# Talks to the SkpShare server. Transport is pluggable:
#   * SketchupTransport – Sketchup::Http::Request (async, does not freeze SketchUp)
#   * NetHttpTransport  – Net::HTTP (blocking; used by tests / CLI)
require 'json'
require 'uri'
require 'digest'

module SkpShare
  class ApiError < StandardError
    attr_reader :status

    def initialize(status, msg)
      @status = status
      super(msg)
    end
  end

  class SketchupTransport
    METHODS = { 'GET' => :GET, 'POST' => :POST, 'PUT' => :PUT, 'DELETE' => :DELETE, 'PATCH' => :PATCH }.freeze

    def initialize
      @live = {} # keep references so requests are not garbage collected mid-flight
    end

    def request(method, url, headers, body, &cb)
      verb = Sketchup::Http.const_get(METHODS.fetch(method))
      req = Sketchup::Http::Request.new(url, verb)
      req.headers = headers
      req.body = body if body
      key = req.object_id
      @live[key] = req
      req.start do |_r, res|
        @live.delete(key)
        cb.call(res.status_code.to_i, res.body.to_s)
      end
    rescue StandardError => e
      cb.call(0, { error: e.message }.to_json)
    end
  end

  class NetHttpTransport
    def request(method, url, headers, body)
      require 'net/http'
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 300
      klass = Net::HTTP.const_get(method.capitalize)
      req = klass.new(uri.request_uri, headers)
      req.body = body if body
      res = http.request(req)
      yield res.code.to_i, res.body.to_s
    rescue StandardError => e
      yield 0, { error: e.message }.to_json
    end
  end

  class ApiClient
    MAX_RETRIES = 4

    attr_reader :base_url
    attr_accessor :transport

    def initialize(base_url, token, transport)
      @base_url = base_url.to_s.strip.sub(%r{/+\z}, '')
      @token = token.to_s.strip
      @transport = transport
    end

    def headers(extra = {})
      { 'Authorization' => "Bearer #{@token}", 'Accept' => 'application/json',
        'Content-Type' => 'application/json' }.merge(extra)
    end

    # cb.(data_hash_or_nil, error_or_nil)
    def call(method, path, payload = nil, &cb)
      body = payload.nil? ? nil : JSON.generate(payload)
      transport.request(method, "#{@base_url}#{path}", headers, body) do |status, text|
        data = begin
          text.empty? ? {} : JSON.parse(text)
        rescue JSON::ParserError
          { 'error' => "Unexpected server response (HTTP #{status}). Is the URL correct?" }
        end
        if status.between?(200, 299)
          cb.call(data, nil)
        else
          msg = data['error'] || "HTTP #{status}"
          msg = "Cannot reach server: #{msg}" if status.zero?
          cb.call(data, ApiError.new(status, msg))
        end
      end
    end

    # Upload one file in chunks with resume + retries.
    # opts: version_id, kind, filename, sha256, gzipped, original_size, progress: proc(bytes_sent, total)
    def upload_file(path, opts, &done)
      size = File.size(path)
      init = { version_id: opts[:version_id], kind: opts[:kind], filename: opts[:filename] || File.basename(path),
               size: size, sha256: opts[:sha256], gzipped: opts[:gzipped] || false,
               original_size: opts[:original_size] || size }
      call('POST', '/api/uploads', init) do |sess, err|
        next done.call(nil, err) if err

        chunk = sess['chunk_size'].to_i
        total_chunks = sess['total_chunks'].to_i
        pending = (0...total_chunks).to_a - sess['received'].to_a
        sent = (total_chunks - pending.size) * chunk
        send_next = nil
        retries = 0
        send_next = lambda do
          if pending.empty?
            call('POST', "/api/uploads/#{sess['id']}/complete") { |res, e| done.call(res, e) }
            next
          end
          n = pending.first
          data = File.binread(path, chunk, n * chunk)
          hdr = headers('Content-Type' => 'application/octet-stream', 'X-Chunk-Sha256' => Digest::SHA256.hexdigest(data))
          transport.request('POST', "#{@base_url}/api/uploads/#{sess['id']}/chunks/#{n}", hdr, data) do |status, text|
            if status.between?(200, 299)
              pending.shift
              retries = 0
              sent = [sent + data.bytesize, size].min
              opts[:progress]&.call(sent, size)
              send_next.call
            elsif retries < MAX_RETRIES && (status.zero? || status >= 500 || status == 408 || status == 429)
              retries += 1
              delay = 2**retries
              if defined?(UI) && UI.respond_to?(:start_timer)
                UI.start_timer(delay, false) { send_next.call }
              else
                sleep(delay * 0.01)
                send_next.call
              end
            else
              msg = (JSON.parse(text)['error'] rescue nil) || "HTTP #{status}"
              done.call(nil, ApiError.new(status, "Chunk #{n} failed: #{msg}"))
            end
          end
        end
        send_next.call
      end
    end
  end
end
