#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
version="${1:-0.1.0}"
output_dir="$project_dir/dist"

"$project_dir/scripts/build-app.sh"
mkdir -p "$output_dir"
archive="$output_dir/BDMenuPlayer-v${version}-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$project_dir/.build/BDMenuPlayer.app" "$archive"
shasum -a 256 "$archive"
echo "$archive"
