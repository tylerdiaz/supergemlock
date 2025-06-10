#!/bin/bash

echo "Simple Gemfile Parser Test"
echo "=========================="
echo ""

# Create test directory
mkdir -p simple_test

# Test 1: Basic Gemfile
cat > simple_test/test1_Gemfile << 'EOF'
source 'https://rubygems.org'

gem 'rails', '~> 7.0.0'
gem 'pg', '>= 1.0', '< 2.0'
gem 'puma', '~> 6.0'
gem 'redis', '~> 5.0'
EOF

echo "Test 1: Basic gems"
cp simple_test/test1_Gemfile Gemfile
./zig-out/bin/supergemlock > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Parsed successfully"
    echo "  Generated $(wc -l < Gemfile.lock) lines"
else
    echo "✗ Failed to parse"
fi

# Test 2: With require: false
cat > simple_test/test2_Gemfile << 'EOF'
source 'https://rubygems.org'

gem 'rails', '~> 7.0.0'
gem 'rspec', require: false
gem 'capybara', '>= 3.0', require: false
EOF

echo ""
echo "Test 2: With require: false"
cp simple_test/test2_Gemfile Gemfile
./zig-out/bin/supergemlock > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Parsed successfully"
else
    echo "✗ Failed to parse"
fi

# Test 3: With groups (should skip)
cat > simple_test/test3_Gemfile << 'EOF'
source 'https://rubygems.org'

gem 'rails', '~> 7.0.0'

group :test do
  gem 'rspec'
  gem 'factory_bot'
end

gem 'pg', '~> 1.0'
EOF

echo ""
echo "Test 3: With groups"
cp simple_test/test3_Gemfile Gemfile
./zig-out/bin/supergemlock > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Parsed successfully"
    gems=$(grep -c "^    " Gemfile.lock)
    echo "  Found $gems gems (groups skipped)"
else
    echo "✗ Failed to parse"
fi

# Test 4: Complex constraints
cat > simple_test/test4_Gemfile << 'EOF'
source 'https://rubygems.org'

gem 'rails', '>= 7.0', '< 8.0'
gem 'nokogiri', '!= 1.13.0'
gem 'rack', '>= 2.2.6', '< 3.0.0'
EOF

echo ""
echo "Test 4: Complex constraints"
cp simple_test/test4_Gemfile Gemfile
./zig-out/bin/supergemlock > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Parsed successfully"
else
    echo "✗ Failed to parse"
fi

# Performance test
echo ""
echo "Performance Comparison"
echo "---------------------"

# Use test1 for performance
cp simple_test/test1_Gemfile Gemfile

# Test supergemlock
rm -f Gemfile.lock*
start=$(date +%s%N)
./zig-out/bin/supergemlock > /dev/null 2>&1
end=$(date +%s%N)
supergemlock_time=$(( (end - start) / 1000000 ))

# Test bundler
rm -f Gemfile.lock*
start=$(date +%s%N)
bundle lock --quiet > /dev/null 2>&1
end=$(date +%s%N)
bundler_time=$(( (end - start) / 1000000 ))

echo "supergemlock: ${supergemlock_time}ms"
echo "bundler:      ${bundler_time}ms"
echo "Speedup:      $(( bundler_time / supergemlock_time ))x"

# Cleanup
rm -rf simple_test
rm -f Gemfile Gemfile.lock*