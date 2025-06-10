#!/usr/bin/env ruby

require 'fileutils'
require 'benchmark'
require 'open3'

# Test script to compare supergemlock with bundler on real Gemfiles

class GemfileTest
  attr_reader :name, :path, :results
  
  def initialize(name, path)
    @name = name
    @path = path
    @results = {}
  end
  
  def run_test(work_dir)
    puts "\n=== Testing #{@name} ==="
    
    # Copy Gemfile to work directory
    FileUtils.cp(@path, File.join(work_dir, 'Gemfile'))
    
    # Test bundler
    test_bundler(work_dir)
    
    # Test supergemlock
    test_supergemlock(work_dir)
    
    # Compare lockfiles
    compare_lockfiles(work_dir)
    
    # Report results
    report_results
  end
  
  private
  
  def test_bundler(work_dir)
    Dir.chdir(work_dir) do
      FileUtils.rm_f('Gemfile.lock')
      FileUtils.rm_rf('.bundle')
      FileUtils.rm_rf('vendor')
      
      start_time = Time.now
      stdout, stderr, status = Open3.capture3('bundle lock --quiet')
      end_time = Time.now
      
      @results[:bundler_time] = ((end_time - start_time) * 1000).round
      @results[:bundler_success] = status.success?
      @results[:bundler_error] = stderr unless status.success?
      
      if status.success?
        @results[:bundler_gems] = File.read('Gemfile.lock').scan(/^    \w/).count
        FileUtils.cp('Gemfile.lock', 'Gemfile.lock.bundler')
      end
    end
  rescue => e
    @results[:bundler_error] = e.message
  end
  
  def test_supergemlock(work_dir)
    Dir.chdir(work_dir) do
      FileUtils.rm_f('Gemfile.lock')
      FileUtils.rm_f('Gemfile.lock.bin')
      
      start_time = Time.now
      stdout, stderr, status = Open3.capture3('../zig-out/bin/supergemlock')
      end_time = Time.now
      
      @results[:supergemlock_time] = ((end_time - start_time) * 1000).round
      @results[:supergemlock_success] = status.success?
      @results[:supergemlock_error] = stderr unless status.success?
      
      if status.success?
        @results[:supergemlock_gems] = File.read('Gemfile.lock').scan(/^    \w/).count rescue 0
        FileUtils.cp('Gemfile.lock', 'Gemfile.lock.supergemlock')
      end
    end
  rescue => e
    @results[:supergemlock_error] = e.message
  end
  
  def compare_lockfiles(work_dir)
    Dir.chdir(work_dir) do
      if File.exist?('Gemfile.lock.bundler') && File.exist?('Gemfile.lock.supergemlock')
        bundler_lock = File.read('Gemfile.lock.bundler')
        resolver_lock = File.read('Gemfile.lock.supergemlock')
        
        # Compare gem sections
        bundler_gems = extract_gem_section(bundler_lock)
        resolver_gems = extract_gem_section(resolver_lock)
        
        @results[:gems_match] = (bundler_gems == resolver_gems)
        @results[:gem_diff] = (bundler_gems - resolver_gems) + (resolver_gems - bundler_gems) if !@results[:gems_match]
      end
    end
  end
  
  def extract_gem_section(lockfile)
    in_gem_section = false
    gems = []
    
    lockfile.each_line do |line|
      if line.strip == "GEM"
        in_gem_section = true
      elsif line.strip == "" && in_gem_section
        break
      elsif in_gem_section && line =~ /^    (\w+) \((.+)\)$/
        gems << "#{$1} #{$2}"
      end
    end
    
    gems.sort
  end
  
  def report_results
    puts "  Bundler:      #{@results[:bundler_time]}ms (#{@results[:bundler_success] ? 'success' : 'failed'})"
    puts "  supergemlock: #{@results[:supergemlock_time]}ms (#{@results[:supergemlock_success] ? 'success' : 'failed'})"
    
    if @results[:bundler_success] && @results[:supergemlock_success]
      speedup = @results[:bundler_time].to_f / @results[:supergemlock_time].to_f
      puts "  Speedup:      #{speedup.round(1)}x"
      puts "  Gems match:   #{@results[:gems_match] ? 'YES' : 'NO'}"
      
      if !@results[:gems_match] && @results[:gem_diff]
        puts "  Differences:  #{@results[:gem_diff].take(5).join(', ')}#{@results[:gem_diff].size > 5 ? '...' : ''}"
      end
    end
    
    puts "  Bundler error: #{@results[:bundler_error]}" if @results[:bundler_error]
    puts "  Resolver error: #{@results[:supergemlock_error]}" if @results[:supergemlock_error]
  end
end

# Main test runner
def main
  puts "Real Gemfile Compatibility Test"
  puts "==============================="
  
  # Create work directory
  work_dir = 'test_work'
  FileUtils.mkdir_p(work_dir)
  
  # Find all test Gemfiles
  gemfiles = Dir.glob('test_gemfiles/*_Gemfile').sort
  
  puts "\nFound #{gemfiles.size} Gemfiles to test"
  
  # Run tests
  results = []
  gemfiles.each do |path|
    name = File.basename(path).sub('_Gemfile', '')
    test = GemfileTest.new(name, path)
    test.run_test(work_dir)
    results << test
  end
  
  # Summary
  puts "\n\nSUMMARY"
  puts "======="
  
  successful = results.count { |r| r.results[:supergemlock_success] }
  matching = results.count { |r| r.results[:gems_match] }
  
  puts "Parsing success: #{successful}/#{results.size}"
  puts "Lockfile match:  #{matching}/#{successful}"
  
  # Performance summary
  bundler_times = results.map { |r| r.results[:bundler_time] }.compact
  resolver_times = results.map { |r| r.results[:supergemlock_time] }.compact
  
  if bundler_times.any? && resolver_times.any?
    avg_bundler = bundler_times.sum.to_f / bundler_times.size
    avg_resolver = resolver_times.sum.to_f / resolver_times.size
    
    puts "\nPerformance:"
    puts "  Bundler average:      #{avg_bundler.round}ms"
    puts "  supergemlock average: #{avg_resolver.round}ms"
    puts "  Average speedup:      #{(avg_bundler / avg_resolver).round(1)}x"
  end
  
  # Cleanup
  FileUtils.rm_rf(work_dir)
end

if __FILE__ == $0
  main
end