#!/usr/bin/env bash

temp_file="/tmp/tmp.gwa5WKTqxV"
count=0

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    count=$((count + 1))
    if [[ $count -le 5 ]] || [[ $count -gt 2766 ]]; then
        echo "Line $count: $line"
    fi
done < "$temp_file"

echo "Total lines read: $count"
