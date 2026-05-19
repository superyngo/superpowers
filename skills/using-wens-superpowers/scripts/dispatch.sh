#!/bin/sh
# dispatch.sh — wraps `dispatch-agent dispatch -f` for using-wens-superpowers.
# Reads prompt from stdin; writes prompt + .out.md to docs/tmp/<ts>_<pid>-<slug>.
# Emits `prompt=...` and `out=...` on stderr. Exit code mirrors dispatch-agent
# (127 if not on PATH, 2 if argv malformed). $WENS_DISPATCH_TIMEOUT (default 600).

set -u

SLUG="${1:-}"
if [ -z "$SLUG" ]; then
  echo "dispatch.sh: missing <phase-slug> argument" >&2
  echo "usage: cat prompt.md | dispatch.sh <phase-slug>" >&2
  exit 2
fi

if ! command -v dispatch-agent >/dev/null 2>&1; then
  echo "dispatch.sh: 'dispatch-agent' not found on PATH." >&2
  echo "  Install it (https://github.com/superyngo/dispatch-agent or equivalent)" >&2
  echo "  and ensure it is on \$PATH before re-running." >&2
  exit 127
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TMPDIR_ABS="$REPO_ROOT/docs/tmp"
mkdir -p "$TMPDIR_ABS"

SLUG=$(printf '%s' "$SLUG" | sed 's/[^A-Za-z0-9._-]/-/g')
TS=$(date -u +%Y%m%dT%H%M%SZ)
BASE="${TS}_$$-${SLUG}"
PROMPT="$TMPDIR_ABS/${BASE}.md"
OUT="$TMPDIR_ABS/${BASE}.out.md"

cat > "$PROMPT"
echo "prompt=$PROMPT" >&2
echo "out=$OUT" >&2

TIMEOUT="${WENS_DISPATCH_TIMEOUT:-600}"
dispatch-agent dispatch -f "$PROMPT" --timeout "$TIMEOUT" > "$OUT" 2>>"$OUT"
exit $?
