#!/bin/sh
# dispatch.sh — wraps `agd dispatch -f` for using-wens-superpowers.
# Reads prompt from stdin; writes prompt + .out.md to
# docs/tmp/<ts>_<pid>-<slug>.{md,out.md}. Emits prompt=, out=, timeout=,
# tier= on stderr (+ retry= on retry). Exit code mirrors agd (127 if not
# on PATH, 2 if argv malformed). Override per-call via
# WENS_DISPATCH_TIMEOUT (seconds).
set -u

SLUG="${1:-}"
if [ -z "$SLUG" ]; then
  echo "dispatch.sh: missing <phase-slug> argument" >&2
  echo "usage: cat prompt.md | dispatch.sh <phase-slug>" >&2
  exit 2
fi

if ! command -v agd >/dev/null 2>&1; then
  echo "dispatch.sh: 'agd' not found on PATH." >&2
  echo "  Install from https://github.com/superyngo/agd" >&2
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

case "$SLUG" in
  spec-review*)                          TIER=spec-review;  DEFAULT=900  ;;
  plan-verify*)                          TIER=plan-verify;  DEFAULT=1200 ;;
  implement-task*)                       TIER=implement;    DEFAULT=1800 ;;
  spec-compliance-review*|code-review*)  TIER=review;       DEFAULT=900  ;;
  *)                                     TIER=review;       DEFAULT=900  ;;
esac
TIMEOUT="${WENS_DISPATCH_TIMEOUT:-$DEFAULT}"

echo "prompt=$PROMPT" >&2
echo "out=$OUT" >&2
echo "timeout=$TIMEOUT tier=$TIER" >&2

run_once() {
  agd dispatch -f "$PROMPT" --timeout "$TIMEOUT" > "$OUT" 2>>"$OUT"
}

run_once
RC=$?

# Empty-output / missing-frontmatter retry (one shot).
if [ ! -s "$OUT" ] || ! grep -qE '^(---|status:)' "$OUT"; then
  REASON=empty_output
  [ -s "$OUT" ] && REASON=no_frontmatter
  echo "retry=1 reason=$REASON" >&2
  run_once
  RC=$?
fi

exit $RC
