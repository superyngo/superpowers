#!/bin/sh
# Mock dispatch-agent: prints a canned PASS reviewer response.
# Accepts `dispatch -f <file> [--timeout N]` argv shape.
while [ $# -gt 0 ]; do
  case "$1" in
    -f) shift; PROMPT_FILE="$1"; shift ;;
    *) shift ;;
  esac
done
cat <<'OUT'
---
status: PASS
issues: []
---
OK from mock.
OUT
exit 0
