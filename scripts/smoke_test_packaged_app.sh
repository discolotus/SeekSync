#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
version="$(tr -d '[:space:]' < "$repo_dir/VERSION")"
archive="${1:-$repo_dir/dist/release/SeekSync-$version-arm64.zip}"
smoke_root="$(mktemp -d "${RUNNER_TEMP:-/private/tmp}/seeksync-runtime-smoke.XXXXXX")"
smoke_pid=""

cleanup() {
    if [[ -n "$smoke_pid" ]] && kill -0 "$smoke_pid" 2>/dev/null; then
        kill "$smoke_pid" 2>/dev/null || true
        wait "$smoke_pid" 2>/dev/null || true
    fi
    /usr/bin/pkill -f "$smoke_root/Applications/SeekSync.app/Contents/MacOS/SeekSyncPrototype" 2>/dev/null || true
    rm -rf "$smoke_root"
}
trap cleanup EXIT INT TERM

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Packaged-app smoke requires macOS." >&2
    exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Packaged-app smoke requires the ARM64 publishing architecture." >&2
    exit 1
fi
if [[ ! -f "$archive" ]]; then
    echo "Release archive not found: $archive" >&2
    exit 1
fi

install_root="$smoke_root/Applications"
mkdir -p "$install_root"
ditto -x -k "$archive" "$install_root"

app="$install_root/SeekSync.app"
executable="$app/Contents/MacOS/SeekSyncPrototype"
info_plist="$app/Contents/Info.plist"
test -x "$executable"
test -f "$info_plist"
test "$(plutil -extract CFBundleIdentifier raw "$info_plist")" = "com.discolotus.SeekSync"
test "$(plutil -extract CFBundleShortVersionString raw "$info_plist")" = "$version"
test "$(plutil -extract LSMinimumSystemVersion raw "$info_plist")" = "14.0"
test "$(lipo -archs "$executable")" = "arm64"
codesign --verify --deep --strict "$app"

fake_sockseek="$smoke_root/sockseek"
cat > "$fake_sockseek" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    printf '3.0.5\n'
    exit 0
fi
printf 'The packaged-app smoke stub only supports --version.\n' >&2
exit 64
EOF
chmod +x "$fake_sockseek"

runtime_log="$smoke_root/runtime.log"
/usr/bin/open -n -F -W \
    --stdout "$runtime_log" \
    --stderr "$runtime_log" \
    --env "SEEKSYNC_RUNTIME_SMOKE=1" \
    --env "SEEKSYNC_STATE_PATH=$smoke_root/state.json" \
    --env "SEEKSYNC_CONFIG_PATH=$smoke_root/missing-sockseek.conf" \
    --env "SEEKSYNC_BINARY_PATH=$fake_sockseek" \
    "$app" &
smoke_pid=$!

deadline=$((SECONDS + 30))
while kill -0 "$smoke_pid" 2>/dev/null && (( SECONDS < deadline )); do
    sleep 1
done

if kill -0 "$smoke_pid" 2>/dev/null; then
    echo "SeekSync did not finish its runtime smoke within 30 seconds." >&2
    cat "$runtime_log" >&2
    exit 1
fi

set +e
wait "$smoke_pid"
exit_status=$?
set -e
smoke_pid=""
if (( exit_status != 0 )); then
    echo "SeekSync exited with status $exit_status during runtime smoke." >&2
    cat "$runtime_log" >&2
    exit 1
fi
if ! grep -Fq "SeekSync runtime smoke: root view appeared" "$runtime_log"; then
    echo "SeekSync exited before presenting its root window." >&2
    cat "$runtime_log" >&2
    exit 1
fi

echo "Packaged SeekSync $version installed and launched successfully on $(sw_vers -productVersion) arm64."
