#!/usr/bin/env bash

set -euo pipefail

# Create a temp file with 10 lines
temp_file=$(mktemp)
for i in {1..10}; do
    echo "Line $i" >> "$temp_file"
done

echo "Temp file created with $(wc -l < "$temp_file") lines"

# Process with while loop
count=0
while IFS= read -r line; do
    count=$((count + 1))
    echo "Processing: $line (count=$count)"

    # Simulate some processing
    result=$((count * 2))
    echo "Result: $result"

done < "$temp_file"

echo "Total processed: $count"

rm -f "$temp_file"
