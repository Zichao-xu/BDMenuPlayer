#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
version="${1:?usage: package-release.sh <version>}"
output_dir="$project_dir/dist"

bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")
if [[ "$version" != "$bundle_version" ]]; then
    echo "Release version $version does not match app version $bundle_version." >&2
    exit 1
fi

"$project_dir/scripts/build-app.sh"
codesign --verify --deep --strict "$project_dir/.build/BDMenuPlayer.app"
mkdir -p "$output_dir"
archive="$output_dir/BDMenuPlayer-v${version}-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$project_dir/.build/BDMenuPlayer.app" "$archive"
shasum -a 256 "$archive"
echo "$archive"
