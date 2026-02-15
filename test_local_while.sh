#!/usr/bin/env bash

set -euo pipefail

test_func() {
    local temp_file=$(mktemp)
    for i in {1..5}; do
        echo "Line $i data" >> "$temp_file"
    done

    echo "Processing $(wc -l < "$temp_file") lines"

    local count=0
    while IFS= read -r line; do
        count=$((count + 1))
        echo "Iteration $count"

        # Declare local vars inside loop (like the actual script)
        local var1 var2 var3
        var1=$(echo "$line" | awk '{print $1}')
        var2=$(echo "$line" | awk '{print $2}')
        var3=$(echo "$line" | awk '{print $3}')

        echo "Parsed: var1=$var1, var2=$var2, var3=$var3"

    done < "$temp_file"

    echo "Total: $count"
    rm -f "$temp_file"
}

test_func
