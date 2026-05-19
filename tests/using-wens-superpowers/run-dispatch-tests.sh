#!/bin/sh
# Test runner for skills/using-wens-superpowers/scripts/dispatch.sh
# Uses a mock dispatch-agent on PATH for each test case.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISPATCH="$REPO_ROOT/skills/using-wens-superpowers/scripts/dispatch.sh"
TMPDIR_TEST="$(mktemp -d)"
PASS=0
FAIL=0

assert() {
  desc="$1"; shift
  if "$@"; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc"; FAIL=$((FAIL+1))
  fi
}

cleanup() {
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

# --- Test 1: missing dispatch-agent prints install hint and exits 127
run_test_missing_path() {
  cd "$TMPDIR_TEST" || return 1
  out=$(PATH="/usr/bin:/bin" sh "$DISPATCH" test-slug <<< "hello" 2>&1)
  rc=$?
  [ "$rc" = "127" ] && echo "$out" | grep -qi "dispatch-agent"
}
assert "missing dispatch-agent → exit 127 with hint" run_test_missing_path

# --- Test 2: success path writes prompt + .out.md, exit 0
run_test_success() {
  workdir="$TMPDIR_TEST/repo1"
  mkdir -p "$workdir" && cd "$workdir" || return 1
  git init -q .
  bindir="$TMPDIR_TEST/bin1"
  mkdir -p "$bindir"
  cp "$SCRIPT_DIR/fixtures/mock-dispatch-agent-success.sh" "$bindir/dispatch-agent"
  PATH="$bindir:$PATH" sh "$DISPATCH" spec-review-r1 <<< "the prompt body" > /dev/null 2>"$workdir/stderr.log"
  rc=$?
  [ "$rc" = "0" ] || return 1
  prompt_file=$(grep -o 'prompt=[^ ]*' "$workdir/stderr.log" | head -1 | cut -d= -f2)
  out_file=$(grep -o 'out=[^ ]*' "$workdir/stderr.log" | head -1 | cut -d= -f2)
  [ -f "$prompt_file" ] && [ -f "$out_file" ] \
    && grep -q "the prompt body" "$prompt_file" \
    && grep -q "status: PASS" "$out_file"
}
assert "success → prompt + out files created, exit 0" run_test_success

# --- Test 3: dispatch-agent failure propagates exit code, partial output captured
run_test_failure() {
  workdir="$TMPDIR_TEST/repo2"
  mkdir -p "$workdir" && cd "$workdir" || return 1
  git init -q .
  bindir="$TMPDIR_TEST/bin2"
  mkdir -p "$bindir"
  cp "$SCRIPT_DIR/fixtures/mock-dispatch-agent-fail.sh" "$bindir/dispatch-agent"
  PATH="$bindir:$PATH" sh "$DISPATCH" plan-verify <<< "anything" > /dev/null 2>"$workdir/stderr.log"
  rc=$?
  [ "$rc" = "42" ] || return 1
  out_file=$(grep -o 'out=[^ ]*' "$workdir/stderr.log" | head -1 | cut -d= -f2)
  [ -f "$out_file" ] && grep -q "partial output line" "$out_file"
}
assert "failure → exit code propagates, partial out captured" run_test_failure

# --- Test 4: timeout flag is passed through
run_test_timeout_flag() {
  workdir="$TMPDIR_TEST/repo3"
  mkdir -p "$workdir" && cd "$workdir" || return 1
  git init -q .
  bindir="$TMPDIR_TEST/bin3"
  mkdir -p "$bindir"
  # Mock that records its argv to a file then prints PASS
  cat > "$bindir/dispatch-agent" <<EOF
#!/bin/sh
echo "ARGV: \$*" > "$workdir/argv.log"
echo "---"
echo "status: PASS"
echo "issues: []"
echo "---"
EOF
  chmod +x "$bindir/dispatch-agent"
  WENS_DISPATCH_TIMEOUT=42 PATH="$bindir:$PATH" sh "$DISPATCH" spec-review-r1 <<< "x" > /dev/null 2>"$workdir/stderr.log"
  grep -q -- "--timeout 42" "$workdir/argv.log"
}
assert "WENS_DISPATCH_TIMEOUT → passed as --timeout to dispatch-agent" run_test_timeout_flag

# --- Test 5: docs/tmp/ created lazily
run_test_lazy_mkdir() {
  workdir="$TMPDIR_TEST/repo4"
  mkdir -p "$workdir" && cd "$workdir" || return 1
  git init -q .
  bindir="$TMPDIR_TEST/bin4"
  mkdir -p "$bindir"
  cp "$SCRIPT_DIR/fixtures/mock-dispatch-agent-success.sh" "$bindir/dispatch-agent"
  [ -d "$workdir/docs/tmp" ] && return 1  # must not exist yet
  PATH="$bindir:$PATH" sh "$DISPATCH" plan-verify <<< "x" > /dev/null 2>"$workdir/stderr.log"
  [ -d "$workdir/docs/tmp" ]
}
assert "docs/tmp/ created lazily on first call" run_test_lazy_mkdir

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
