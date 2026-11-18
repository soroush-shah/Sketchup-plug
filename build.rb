# frozen_string_literal: true

# Builds dist/mep_studio_v<VERSION>.rbz (a zip with mep_studio.rb + mep_studio/).
version = File.read('src/mep_studio.rb')[/VERSION = '([^']+)'/, 1]
Dir.mkdir('dist') unless Dir.exist?('dist')
out = File.expand_path("dist/mep_studio_v#{version}.rbz")
File.delete(out) if File.exist?(out)
Dir.chdir('src') { system('zip', '-qr', '-X', out, 'mep_studio.rb', 'mep_studio') || abort('zip failed') }
puts out
