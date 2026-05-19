#!/bin/sh
# Smoke test: dispatch.sh with a mock dispatch-agent, simulating the spec-review
# round-1 round-trip the main agent would perform.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISPATCH="$REPO_ROOT/skills/using-wens-superpowers/scripts/dispatch.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR" || exit 1
git init -q .
mkdir -p bin
cat > bin/dispatch-agent <<'EOF'
#!/bin/sh
# Mock that echoes back its prompt file content prefixed with PASS YAML.
PROMPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -f) shift; PROMPT="$1"; shift ;;
    *) shift ;;
  esac
done
printf -- '---\nstatus: PASS\nissues: []\n---\n\nProcessed: %s\n' "$PROMPT"
EOF
chmod +x bin/dispatch-agent

PATH="$WORKDIR/bin:$PATH" WENS_DISPATCH_TIMEOUT=30 sh "$DISPATCH" spec-review-r1 \
  > /dev/null 2> stderr.log <<EOF_PROMPT
# Spec Review — Round 1
Review the spec at /tmp/spec.md.
EOF_PROMPT

rc=$?
[ "$rc" = "0" ] || { echo "FAIL: exit code $rc"; exit 1; }

prompt_path=$(grep -o 'prompt=[^ ]*' stderr.log | head -1 | cut -d= -f2)
out_path=$(grep -o 'out=[^ ]*' stderr.log | head -1 | cut -d= -f2)
[ -f "$prompt_path" ] || { echo "FAIL: prompt file missing"; exit 1; }
[ -f "$out_path" ] || { echo "FAIL: out file missing"; exit 1; }
grep -q "Spec Review — Round 1" "$prompt_path" || { echo "FAIL: prompt content wrong"; exit 1; }
grep -q "status: PASS" "$out_path" || { echo "FAIL: out content wrong"; exit 1; }
case "$prompt_path" in
  */docs/tmp/*) ;;
  *) echo "FAIL: prompt not under docs/tmp/: $prompt_path"; exit 1 ;;
esac

echo "PASS: end-to-end smoke"
