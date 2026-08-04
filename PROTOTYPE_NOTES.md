# SeekSync prototype notes

Question: What should a lightweight macOS front end for browsing Spotify playlists and driving recurring Sockseek syncs feel like?

The original prototype compared three interface directions. The responsive
Library + Inspector direction is now the sole application interface because
playlist discovery is the natural starting point and it remains usable at the
supported minimum window size.

Prototype state is stored under `~/Library/Application Support/SeekSyncPrototype/prototype-state.json`. The real Sockseek config is only changed after the user explicitly presses **Save config**, and a sibling `.seeksync-backup` is created first.

Before treating SeekSync as a fully productionized application, add
production-grade OAuth, Keychain storage, launch-agent scheduling, durable job
recovery, Developer ID signing/notarization, and long-running soak tests. The
application already owns process cancellation, parses Sockseek 3 JSON progress,
and verifies bounded live acceptance runs.
