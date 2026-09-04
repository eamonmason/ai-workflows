#!/usr/bin/env bash
# Exercises the verify-and-repair loop from reusable-executor.yml.
#
# The step body is extracted from the workflow at run time rather than copied
# here, so this cannot silently drift from what the runner executes.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
STEP=$(mktemp)
python3 tests/extract-step.py .github/workflows/reusable-executor.yml execute verify > "$STEP"

PASS=0
FAIL=0

# Runs the real step with a stub verify command and a stub `claude` that
# "repairs" the code by decrementing a failure counter.
run_case() {
  local fails="$1" max="$2" mode="$3"
  local d
  d=$(mktemp -d)
  export RUNNER_TEMP="$d" MAX_ATTEMPTS="$max" VERIFY_CMD="$d/verify.sh"
  export GITHUB_OUTPUT="$d/out"
  echo "$fails" > "$d/remaining"

  cat > "$d/verify.sh" <<INNER
#!/usr/bin/env bash
r=\$(cat "$d/remaining")
if [ "\$r" -gt 0 ]; then echo "simulated failure, \$r to go"; exit 1; fi
echo "verify: ok"
INNER
  chmod +x "$d/verify.sh"
  [ "$mode" = "missing" ] && rm -f "$d/verify.sh"
  [ "$mode" = "noexec" ] && chmod -x "$d/verify.sh"

  cat > "$d/claude" <<INNER
#!/usr/bin/env bash
r=\$(cat "$d/remaining"); echo \$((r-1)) > "$d/remaining"
echo x >> "$d/claude_calls"
INNER
  chmod +x "$d/claude"
  : > "$d/claude_calls"

  PATH="$d:$PATH" bash "$STEP" > "$d/log" 2>&1
  local rc=$?
  local ok
  ok=$(grep -o 'ok=[a-z]*' "$d/out" 2>/dev/null | tail -1)
  local calls
  calls=$(wc -l < "$d/claude_calls")
  local tail_file=no
  [ -f "$d/verify-tail.log" ] && tail_file=yes
  echo "$rc|${ok:-none}|$calls|$tail_file"
  rm -rf "$d"
}

check() {
  local name="$1" expected="$2"
  shift 2
  local actual
  actual=$(run_case "$@")
  if [ "$actual" = "$expected" ]; then
    echo "PASS  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $name: expected [$expected] got [$actual]"
    FAIL=$((FAIL + 1))
  fi
}

# expected is rc|ok|claude_calls|tail_written
check "passes on the first attempt"        "0|ok=true|0|no"   0 3 normal
check "fails twice, repaired, then passes" "0|ok=true|2|no"   2 3 normal
check "fails every attempt, gives up"      "0|ok=false|2|yes" 9 3 normal
check "max_attempts=1 does no repair"      "0|ok=false|0|yes" 9 1 normal
check "missing verify script is fatal"     "1|none|0|no"      0 3 missing
check "non-executable script is fatal"     "1|none|0|no"      0 3 noexec

rm -f "$STEP"
echo "verify-loop: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
