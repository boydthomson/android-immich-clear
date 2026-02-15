#!/usr/bin/env bash

DCIM_PATH="/sdcard/DCIM/Camera"
EXTENSIONS=("jpg" "jpeg" "png" "heic" "heif" "mp4" "mov" "webp" "gif")

# Build find command with extensions
find_expr=""
for ext in "${EXTENSIONS[@]}"; do
    if [[ -n "$find_expr" ]]; then
        find_expr="$find_expr -o"
    fi
    find_expr="$find_expr -iname '*.$ext'"
done

echo "Find expression: $find_expr"
echo ""
echo "Running command..."
timeout 60 adb shell "find '$DCIM_PATH' -maxdepth 1 -type f \\( $find_expr \\) -printf '%T@ %p\\n'" 2>&1 | tr -d '\r' | head -10
echo ""
echo "Exit code: $?"
