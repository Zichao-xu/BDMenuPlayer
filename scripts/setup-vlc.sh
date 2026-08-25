#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
destination="$project_dir/Dependencies/VLC"
source_path="${1:-}"

if [[ -z "$source_path" ]]; then
    temp_dir="$(mktemp -d)"
    trap 'hdiutil detach "$temp_dir/mount" -quiet 2>/dev/null || true; rm -rf "$temp_dir"' EXIT
    mkdir -p "$temp_dir/mount"
    echo "Downloading VLC 3.0.23 for Apple Silicon…"
    curl -fL "https://get.videolan.org/vlc/3.0.23/macosx/vlc-3.0.23-arm64.dmg" -o "$temp_dir/vlc.dmg"
    expected_sha256="fc6fac08d87f538517d44aca0c5e7a244b67c8c4cb589bf478363a7315fd5e0d"
    printf "%s  %s\n" "$expected_sha256" "$temp_dir/vlc.dmg" | shasum -a 256 -c -
    hdiutil attach "$temp_dir/vlc.dmg" -mountpoint "$temp_dir/mount" -nobrowse -quiet
    source_path="$temp_dir/mount/VLC.app/Contents/MacOS"
elif [[ -d "$source_path/Contents/MacOS" ]]; then
    source_path="$source_path/Contents/MacOS"
fi

if [[ ! -f "$source_path/lib/libvlc.dylib" ]]; then
    echo "The selected path does not contain an Apple Silicon VLC runtime." >&2
    exit 1
fi

mkdir -p "$project_dir/Dependencies"
rm -rf "$destination"
ditto "$source_path" "$destination"
echo "VLC runtime prepared at $destination"
