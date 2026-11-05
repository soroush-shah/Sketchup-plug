# encoding: UTF-8
# Banian Profile Builder - user settings and personal library (custom
# profiles and saved assemblies), stored as JSON in the user's app folder.

require 'json'
require 'fileutils'

module BanianStudio
  module ProfileBuilder
    module Library
      module_function

      def folder
        base = if ENV['APPDATA'] && !ENV['APPDATA'].empty?
                 ENV['APPDATA']
               elsif RUBY_PLATFORM =~ /darwin/
                 File.join(Dir.home, 'Library', 'Application Support')
               else
                 Dir.home
               end
        dir = File.join(base.dup.force_encoding('UTF-8'), 'BanianProfileBuilder')
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        dir
      end

      def file
        File.join(folder, 'library.json')
      end

      def data
        @data ||= begin
          raw = File.exist?(file) ? File.read(file, encoding: 'UTF-8') : '{}'
          h = JSON.parse(raw)
          h['profiles'] ||= []
          h['assemblies'] ||= []
          h
        rescue StandardError
          { 'profiles' => [], 'assemblies' => [] }
        end
      end

      def save
        File.write(file, JSON.pretty_generate(data), encoding: 'UTF-8')
      rescue StandardError => e
        puts "Banian Profile Builder: cannot save library (#{e.message})"
      end

      def add_profile(name, loops)
        id = "custom_#{Time.now.to_i}_#{rand(1000)}"
        data['profiles'] << { 'id' => id, 'name' => name, 'loops' => loops }
        save
        id
      end

      def add_assembly(name, spec)
        id = "user_#{Time.now.to_i}_#{rand(1000)}"
        data['assemblies'] << { 'id' => id, 'name' => name, 'rows' => spec['rows'] || [],
                                'openings' => spec['openings'] || [] }
        save
        id
      end

      def remove(id)
        data['profiles'].reject! { |p| p['id'] == id }
        data['assemblies'].reject! { |p| p['id'] == id }
        save
      end

      def profile(id)
        data['profiles'].find { |p| p['id'] == id }
      end

      # ---------- small settings (settings.json next to the library) ------
      # A file is used instead of Sketchup.write_default because long JSON
      # strings with quotes are not stored reliably in the registry/plist.

      def settings_file
        File.join(folder, 'settings.json')
      end

      def settings
        @settings ||= begin
          File.exist?(settings_file) ? JSON.parse(File.read(settings_file, encoding: 'UTF-8')) : {}
        rescue StandardError
          {}
        end
      end

      def get(key, default = nil)
        settings.key?(key) ? settings[key] : default
      end

      def set(key, value)
        settings[key] = value
        File.write(settings_file, JSON.generate(settings), encoding: 'UTF-8')
      rescue StandardError => e
        puts "Banian Profile Builder: cannot save settings (#{e.message})"
      end
    end
  end
end
