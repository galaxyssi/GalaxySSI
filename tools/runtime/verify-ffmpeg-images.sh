#!/usr/bin/env bash
set -euo pipefail

ffmpeg="${1:?FFmpeg binary required}"
ffprobe="${2:?FFprobe binary required}"
runner=()
if [[ -n "${3:-}" ]]; then runner=("$3"); fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Execute the cross-compiled binary, not a host codec inventory or a version check.
"${runner[@]}" "$ffmpeg" -hide_banner -loglevel error -y \
  -f lavfi -i 'color=c=green:s=64x64:d=1' -frames:v 1 -c:v png "$work/image.png"
"${runner[@]}" "$ffmpeg" -hide_banner -loglevel error -y \
  -i "$work/image.png" -frames:v 1 -c:v mjpeg "$work/image.jpg"
"${runner[@]}" "$ffmpeg" -hide_banner -loglevel error -y \
  -i "$work/image.jpg" -frames:v 1 -c:v png "$work/roundtrip.png"
for file in "$work/image.png" "$work/image.jpg" "$work/roundtrip.png"; do
  test -s "$file"
  dimensions="$("${runner[@]}" "$ffprobe" -v error -select_streams v:0 \
    -show_entries stream=width,height -of csv=p=0:s=x "$file")"
  test "$dimensions" = '64x64'
done
echo 'FFmpeg PNG/JPEG encode, decode and round-trip checks passed.'
