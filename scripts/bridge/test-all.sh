#!/usr/bin/env bash
# Run every bridge test in one go and fail on the first thing that fails:
#   test.bash / test.zsh / test.fish  — the per-shell suites (headless)
#   test-pgrp.py                      — the real-terminal properties for all three shells (menu process group, the trigger's apply path, and no shell errors in the session)
# Requires the engine binaries under module/PSCompletions/bin/<platform>-<arch> (built by CI, shipped in the module package) and python3.
# Usage: scripts/bridge/test-all.sh [root]
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(dirname -- "$(dirname -- "$HERE")")}"
fail=0

run() {
    local name="$1"; shift
    echo "=== $name ==="
    "$@" || fail=1
}

run "bash suite" env -u BASH_ENV bash --norc "$HERE/test.bash" "$ROOT"
run "zsh suite" zsh -f "$HERE/test.zsh" "$ROOT"
if command -v fish >/dev/null 2>&1; then
    run "fish suite" fish --no-config "$HERE/test.fish" "$ROOT"
else
    echo "=== fish suite ==="
    echo "(skip: fish not installed)"
fi
run "pty tests" python3 "$HERE/test-pgrp.py" "$ROOT"

# Layout: every *shipped* bridge file carries its interpreter shebang — a missing one is the kind of slip no other check sees.
echo "=== layout checks ==="
for f in "$ROOT"/module/PSCompletions/PSCompletions{.bash,.zsh,.fish}; do
    if [[ "$(head -c 2 -- "$f")" == "#!" ]]; then
        echo "ok   shebang $(basename -- "$f")"
    else
        echo "FAIL shebang missing in $(basename -- "$f")"
        fail=1
    fi
done

echo
if (( fail )); then
    echo "BRIDGE TESTS FAILED"
    exit 1
fi
echo "all bridge tests passed"
