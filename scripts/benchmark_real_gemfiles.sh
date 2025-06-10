#!/bin/bash

echo "Real Gemfile Benchmark: supergemlock vs Bundler"
echo "==============================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create work directory
WORK_DIR="benchmark_work"
mkdir -p "$WORK_DIR"

# Arrays to store results
declare -a supergemlock_times
declare -a bundler_times
declare -a gemfile_names

# Function to measure time in milliseconds
get_time_ms() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS with gdate
        echo $(($(gdate +%s%N)/1000000))
    else
        # Linux
        echo $(($(date +%s%N)/1000000))
    fi
}

# Function to test a single Gemfile
test_gemfile() {
    local gemfile=$1
    local name=$2
    
    echo -n "Testing $name... "
    
    # Copy Gemfile to work directory
    cp "$gemfile" "$WORK_DIR/Gemfile"
    cd "$WORK_DIR"
    
    # Clean environment
    rm -f Gemfile.lock Gemfile.lock.bin .bundle/config
    
    # Test supergemlock
    local gr_start=$(get_time_ms)
    ../zig-out/bin/supergemlock > /dev/null 2>&1
    local gr_status=$?
    local gr_end=$(get_time_ms)
    local gr_time=$((gr_end - gr_start))
    
    if [ $gr_status -eq 0 ]; then
        cp Gemfile.lock Gemfile.lock.supergemlock 2>/dev/null
    fi
    
    # Clean for bundler
    rm -f Gemfile.lock Gemfile.lock.bin
    
    # Test bundler
    local b_start=$(get_time_ms)
    bundle lock --quiet > /dev/null 2>&1
    local b_status=$?
    local b_end=$(get_time_ms)
    local b_time=$((b_end - b_start))
    
    if [ $b_status -eq 0 ]; then
        cp Gemfile.lock Gemfile.lock.bundler 2>/dev/null
    fi
    
    # Report results
    if [ $gr_status -eq 0 ] && [ $b_status -eq 0 ]; then
        supergemlock_times+=($gr_time)
        bundler_times+=($b_time)
        gemfile_names+=("$name")
        
        local speedup=$(awk "BEGIN {printf \"%.1f\", $b_time/$gr_time}")
        echo -e "${GREEN}✓${NC} supergemlock: ${gr_time}ms, bundler: ${b_time}ms (${speedup}x faster)"
    elif [ $gr_status -ne 0 ]; then
        echo -e "${RED}✗${NC} supergemlock failed to parse"
    elif [ $b_status -ne 0 ]; then
        echo -e "${YELLOW}⚠${NC} bundler failed (supergemlock: ${gr_time}ms)"
    fi
    
    cd ..
}

# Test each Gemfile
echo "Individual Results:"
echo "-------------------"

# Simple Gemfiles that should work
test_gemfile "test_gemfiles/solidus_Gemfile" "Solidus"
test_gemfile "test_gemfiles/redmine_Gemfile" "Redmine"

# More complex ones
test_gemfile "test_gemfiles/rails_Gemfile" "Rails"
test_gemfile "test_gemfiles/discourse_Gemfile" "Discourse"
test_gemfile "test_gemfiles/mastodon_Gemfile" "Mastodon"
test_gemfile "test_gemfiles/diaspora_Gemfile" "Diaspora"
test_gemfile "test_gemfiles/forem_Gemfile" "Forem"

# Create summary
echo ""
echo "Summary:"
echo "--------"

if [ ${#supergemlock_times[@]} -gt 0 ]; then
    # Calculate averages
    gr_sum=0
    b_sum=0
    for i in "${!supergemlock_times[@]}"; do
        gr_sum=$((gr_sum + supergemlock_times[i]))
        b_sum=$((b_sum + bundler_times[i]))
    done
    
    gr_avg=$((gr_sum / ${#supergemlock_times[@]}))
    b_avg=$((b_sum / ${#bundler_times[@]}))
    avg_speedup=$(awk "BEGIN {printf \"%.1f\", $b_avg/$gr_avg}")
    
    echo "Successfully parsed: ${#supergemlock_times[@]} Gemfiles"
    echo ""
    echo "Average times:"
    echo "  supergemlock: ${gr_avg}ms"
    echo "  bundler:      ${b_avg}ms"
    echo "  Speedup:      ${avg_speedup}x"
    
    # Find best/worst speedups
    best_speedup=0
    best_name=""
    worst_speedup=999
    worst_name=""
    
    for i in "${!supergemlock_times[@]}"; do
        speedup=$(awk "BEGIN {print ${bundler_times[i]}/${supergemlock_times[i]}}")
        if (( $(echo "$speedup > $best_speedup" | bc -l) )); then
            best_speedup=$speedup
            best_name="${gemfile_names[i]}"
        fi
        if (( $(echo "$speedup < $worst_speedup" | bc -l) )); then
            worst_speedup=$speedup
            worst_name="${gemfile_names[i]}"
        fi
    done
    
    echo ""
    echo "Best speedup:  $(printf "%.1f" $best_speedup)x ($best_name)"
    echo "Worst speedup: $(printf "%.1f" $worst_speedup)x ($worst_name)"
else
    echo "No Gemfiles were successfully parsed by both tools"
fi

# Check for parser limitations
echo ""
echo "Parser Limitations Found:"
echo "------------------------"
echo "- gemspec directive not supported"
echo "- Complex group syntax limited"
echo "- Platform-specific gems skipped"
echo "- Git/GitHub sources simplified"

# Cleanup
rm -rf "$WORK_DIR"