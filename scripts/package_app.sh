#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
version_file="${RELEASE_VERSION_FILE:-$repo_dir/VERSION}"
version="${RELEASE_VERSION:-$(tr -d '[:space:]' < "$version_file")}"
app_dir="$repo_dir/dist/SeekSync.app"

if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$' ]]; then
    echo "Invalid release version: $version" >&2
    exit 1
fi

cd "$repo_dir"
mkdir -p "$repo_dir/.build/module-cache"
CLANG_MODULE_CACHE_PATH="$repo_dir/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$repo_dir/.build/module-cache" \
swift build -c release --disable-sandbox
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp -f ".build/release/SeekSyncPrototype" "$app_dir/Contents/MacOS/SeekSyncPrototype"
cp -f "Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp -f "Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp -f "THIRD_PARTY_NOTICES.md" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
