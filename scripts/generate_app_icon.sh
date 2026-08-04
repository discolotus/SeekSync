#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
source_image="$repo_dir/Resources/AppIconSource.png"
iconset_dir="$repo_dir/Resources/AppIcon.iconset"
icns_file="$repo_dir/Resources/AppIcon.icns"

if [[ ! -f "$source_image" ]]; then
    echo "Missing canonical icon source: $source_image" >&2
    exit 1
fi

rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"

function render_icon() {
    local pixels="$1"
    local filename="$2"
    sips -z "$pixels" "$pixels" "$source_image" --out "$iconset_dir/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$iconset_dir" -o "$icns_file"
echo "$icns_file"
