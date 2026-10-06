#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/.build/BDMenuPlayer.app"
vlc_dir="$project_dir/Dependencies/VLC"

if [[ ! -f "$vlc_dir/lib/libvlc.dylib" ]]; then
    echo "VLC runtime not found. Run scripts/setup-vlc.sh first." >&2
    exit 1
fi

cd "$project_dir"
swift build -c release

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"

cp "$project_dir/.build/out/Products/Release/BDMenuPlayer" "$app_dir/Contents/MacOS/BDMenuPlayer"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"

# SwiftPM embeds local build paths in symbols and adds a development rpath.
# Neither is needed by the self-contained application bundle.
strip -S -x "$app_dir/Contents/MacOS/BDMenuPlayer"
install_name_tool -delete_rpath "$project_dir/Dependencies/VLC/lib" \
    "$app_dir/Contents/MacOS/BDMenuPlayer" 2>/dev/null || true

ditto "$vlc_dir" "$app_dir/Contents/Resources/VLC"

# Bundle libbluray and its Homebrew dependency tree so the released app does
# not require users to install Homebrew packages.
frameworks_dir="$app_dir/Contents/Frameworks"
rm -rf "$frameworks_dir"
mkdir -p "$frameworks_dir"

homebrew_deps() {
    otool -L "$1" | awk 'NR > 1 { print $1 }' | grep '^/opt/homebrew/' || true
}

bundle_dylib() {
    local source="$1"
    local name="${source:t}"
    local target="$frameworks_dir/$name"
    [[ -f "$target" ]] && return
    cp -L "$source" "$target"
    chmod u+w "$target"
    install_name_tool -id "@rpath/$name" "$target" 2>/dev/null
    local dep
    for dep in $(homebrew_deps "$source"); do
        [[ "${dep:t}" == "$name" ]] && continue
        install_name_tool -change "$dep" "@rpath/${dep:t}" "$target" 2>/dev/null
        bundle_dylib "$dep"
    done
}

executable="$app_dir/Contents/MacOS/BDMenuPlayer"
for dep in $(homebrew_deps "$executable"); do
    install_name_tool -change "$dep" "@rpath/${dep:t}" "$executable"
    bundle_dylib "$dep"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$executable" 2>/dev/null || true

if otool -L "$executable" "$frameworks_dir"/*.dylib | grep -q '/opt/homebrew/'; then
    echo "Unbundled Homebrew dependency remains:" >&2
    otool -L "$executable" "$frameworks_dir"/*.dylib | grep '/opt/homebrew/' >&2
    exit 1
fi

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
