#!/usr/bin/env ruby
require 'bundler'

begin
  # Parse our generated Gemfile.lock
  lockfile_content = File.read('Gemfile.lock')
  
  # Try to parse with Bundler's lockfile parser
  lockfile = Bundler::LockfileParser.new(lockfile_content)
  
  puts "✅ Successfully parsed Gemfile.lock with Bundler!"
  puts "Found #{lockfile.specs.size} gems in lockfile"
  puts "Platforms: #{lockfile.platforms.join(', ')}"
  puts "Ruby version: #{lockfile.ruby_version}"
  puts "Bundler version: #{lockfile.bundler_version}"
  
  # Show some example gems
  puts "\nFirst 5 gems:"
  lockfile.specs.first(5).each do |spec|
    puts "  #{spec.name} (#{spec.version})"
  end
  
  puts "\n✅ Gemfile.lock is fully compatible with Bundler!"
  
rescue => e
  puts "❌ Error parsing Gemfile.lock: #{e.message}"
  exit 1
end