#!/bin/zsh
set -euo pipefail

version=""
sha256=""
output=""

while (( $# > 0 )); do
    case "$1" in
        --version) version="$2"; shift 2 ;;
        --sha256) sha256="$2"; shift 2 ;;
        --output) output="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$' ]]; then
    echo "Invalid version: $version" >&2
    exit 1
fi
if [[ ! "$sha256" =~ '^[0-9a-f]{64}$' ]]; then
    echo "Invalid SHA-256: $sha256" >&2
    exit 1
fi
if [[ -z "$output" ]]; then
    echo "--output is required" >&2
    exit 1
fi

mkdir -p "${output:h}"
{
    print -r -- 'cask "seeksync" do'
    print -r -- "  version \"$version\""
    print -r -- "  sha256 \"$sha256\""
    print -r -- ''
    print -r -- '  url "https://github.com/discolotus/SeekSync/releases/download/v#{version}/SeekSync-#{version}-arm64.zip"'
    print -r -- '  name "SeekSync"'
    print -r -- '  desc "Keep Spotify playlists synchronized locally with Sockseek"'
    print -r -- '  homepage "https://github.com/discolotus/SeekSync"'
    print -r -- ''
    print -r -- '  depends_on arch: :arm64'
    print -r -- '  depends_on macos: :sonoma'
    print -r -- ''
    print -r -- '  app "SeekSync.app"'
    print -r -- ''
    print -r -- '  zap trash: ['
    print -r -- '    "~/Library/Application Support/SeekSyncPrototype",'
    print -r -- '    "~/Library/Caches/com.discolotus.SeekSync",'
    print -r -- '    "~/Library/Preferences/com.discolotus.SeekSync.plist",'
    print -r -- '  ]'
    print -r -- ''
    print -r -- '  caveats <<~EOS'
    print -r -- '    SeekSync is ad-hoc signed and is not Apple-notarized. On first launch,'
    print -r -- '    macOS may require Open Anyway approval in Privacy & Security.'
    print -r -- '  EOS'
    print -r -- 'end'
} > "$output"
