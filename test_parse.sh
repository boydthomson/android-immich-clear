#!/usr/bin/env bash

line="1738803331.994588980 /sdcard/DCIM/Camera/PXL_20250206_005529658.jpg"
echo "Line: $line"
echo "Testing awk..."
file_epoch=$(echo "$line" | awk '{print int($1)}')
echo "Epoch: $file_epoch"
echo "Testing cut..."
file_path=$(echo "$line" | cut -d' ' -f2-)
echo "Path: $file_path"
echo "Testing basename..."
filename=$(basename "$file_path")
echo "Filename: $filename"
echo "All commands completed successfully"
