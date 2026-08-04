#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
version_file="${RELEASE_VERSION_FILE:-$repo_dir/VERSION}"
version="${RELEASE_VERSION:-$(tr -d '[:space:]' < "$version_file")}"
release_dir="$repo_dir/dist/release"
app_dir="$repo_dir/dist/SeekSync.app"
archive="$release_dir/SeekSync-$version-arm64.zip"
cask="$release_dir/seeksync.rb"

cd "$repo_dir"
RELEASE_VERSION="$version" "$repo_dir/scripts/package_app.sh"
mkdir -p "$release_dir"
rm -f "$archive" "$archive.sha256" "$cask"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive"
(
    cd "$release_dir"
    shasum -a 256 "${archive:t}" > "${archive:t}.sha256"
)
sha256=$(cut -d ' ' -f 1 < "$archive.sha256")
"$repo_dir/scripts/generate_homebrew_cask.sh" \
    --version "$version" \
    --sha256 "$sha256" \
    --output "$cask"

codesign --verify --deep --strict "$app_dir"
test "$(lipo -archs "$app_dir/Contents/MacOS/SeekSyncPrototype")" = arm64
echo "$archive"
echo "$archive.sha256"
echo "$cask"
