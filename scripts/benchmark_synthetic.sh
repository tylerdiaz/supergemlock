#!/bin/bash

echo "Synthetic Gemfile Benchmark: supergemlock vs Bundler"
echo "===================================================="
echo ""

# Create work directory
WORK_DIR="benchmark_work"
mkdir -p "$WORK_DIR"

# Function to measure time in milliseconds
get_time_ms() {
    python3 -c "import time; print(int(time.time() * 1000))"
}

# Arrays for results
declare -a names
declare -a gr_times
declare -a b_times
declare -a speedups

# Test function
test_gemfile() {
    local file=$1
    local name=$2
    
    printf "%-20s" "$name:"
    
    cp "$file" "$WORK_DIR/Gemfile"
    cd "$WORK_DIR"
    
    # Clean
    rm -f Gemfile.lock Gemfile.lock.bin
    
    # Test supergemlock
    gr_start=$(get_time_ms)
    if ../zig-out/bin/supergemlock > /dev/null 2>&1; then
        gr_end=$(get_time_ms)
        gr_time=$((gr_end - gr_start))
        gr_gems=$(grep -c "^    " Gemfile.lock 2>/dev/null || echo 0)
    else
        echo "supergemlock failed"
        cd ..
        return
    fi
    
    # Clean
    rm -f Gemfile.lock
    
    # Test bundler
    b_start=$(get_time_ms)
    if bundle lock --quiet > /dev/null 2>&1; then
        b_end=$(get_time_ms)
        b_time=$((b_end - b_start))
        b_gems=$(grep -c "^    " Gemfile.lock 2>/dev/null || echo 0)
    else
        echo "bundler failed"
        cd ..
        return
    fi
    
    speedup=$(awk "BEGIN {printf \"%.1f\", $b_time/$gr_time}")
    
    printf "supergemlock: %4dms (%2d gems) | bundler: %4dms (%2d gems) | %4.1fx faster\n" \
        "$gr_time" "$gr_gems" "$b_time" "$b_gems" "$speedup"
    
    names+=("$name")
    gr_times+=("$gr_time")
    b_times+=("$b_time")
    speedups+=("$speedup")
    
    cd ..
}

# Run tests
echo "Individual Results:"
echo "-------------------"

test_gemfile "synthetic_gemfiles/minimal_Gemfile" "Minimal"
test_gemfile "synthetic_gemfiles/sinatra_Gemfile" "Sinatra"
test_gemfile "synthetic_gemfiles/rails_app_Gemfile" "Rails App"
test_gemfile "synthetic_gemfiles/api_app_Gemfile" "API App"
test_gemfile "synthetic_gemfiles/ecommerce_Gemfile" "E-commerce"
test_gemfile "synthetic_gemfiles/blog_Gemfile" "Blog/CMS"
test_gemfile "synthetic_gemfiles/data_app_Gemfile" "Data Processing"
test_gemfile "synthetic_gemfiles/devops_Gemfile" "DevOps Tools"
test_gemfile "synthetic_gemfiles/testing_Gemfile" "Testing Suite"
test_gemfile "synthetic_gemfiles/ml_app_Gemfile" "ML App"

# Calculate summary
echo ""
echo "Summary Statistics:"
echo "-------------------"

if [ ${#gr_times[@]} -gt 0 ]; then
    # Calculate totals and averages
    gr_total=0
    b_total=0
    
    for i in "${!gr_times[@]}"; do
        gr_total=$((gr_total + gr_times[i]))
        b_total=$((b_total + b_times[i]))
    done
    
    gr_avg=$((gr_total / ${#gr_times[@]}))
    b_avg=$((b_total / ${#b_times[@]}))
    overall_speedup=$(awk "BEGIN {printf \"%.1f\", $b_avg/$gr_avg}")
    
    echo "Successfully tested: ${#gr_times[@]}/10 Gemfiles"
    echo ""
    echo "Average Performance:"
    echo "  supergemlock: ${gr_avg}ms"
    echo "  bundler:      ${b_avg}ms"
    echo "  Speedup:      ${overall_speedup}x"
    
    # Find min/max
    min_speedup=${speedups[0]}
    max_speedup=${speedups[0]}
    min_name=${names[0]}
    max_name=${names[0]}
    
    for i in "${!speedups[@]}"; do
        if (( $(echo "${speedups[i]} < $min_speedup" | bc -l) )); then
            min_speedup=${speedups[i]}
            min_name=${names[i]}
        fi
        if (( $(echo "${speedups[i]} > $max_speedup" | bc -l) )); then
            max_speedup=${speedups[i]}
            max_name=${names[i]}
        fi
    done
    
    echo ""
    echo "Performance Range:"
    echo "  Best case:  ${max_speedup}x ($max_name)"
    echo "  Worst case: ${min_speedup}x ($min_name)"
    
    # Total time saved
    total_saved=$((b_total - gr_total))
    echo ""
    echo "Total time for all Gemfiles:"
    echo "  supergemlock: ${gr_total}ms"
    echo "  bundler:      ${b_total}ms"
    echo "  Time saved:   ${total_saved}ms ($(awk "BEGIN {printf \"%.0f\", $total_saved/$b_total*100}")%)"
fi

# Cleanup
rm -rf "$WORK_DIR"