#!/usr/bin/env bash
# Exercises the planner's "Guard - spec file only" step.
#
# The step body is extracted from the workflow at run time rather than copied
# here, so this cannot silently drift from what the runner executes.
#
# Why this matters more than it looks: the planner holds contents: write and
# fires automatically on issue-open, with no `@agent execute` in between. It is
# the widest automatic path in the pipeline. The agent is given no Bash tool,
# but "the agent was told to only write the spec" is not a control -- this is.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
STEP=$(mktemp)
python3 tests/extract-step.py \
  .github/workflows/reusable-planner.yml plan "Guard - spec file only" > "$STEP"

PASS=0
FAIL=0

check() {
  local name="$1" want_rc="$2" body="$3"
  local d base_file rc
  d=$(mktemp -d)
  base_file=$(mktemp)

  (
    set -e
    cd "$d"
    git init -q -b main
    git config user.email test@example.com
    git config user.name test
    mkdir -p docs/specs src
    echo readme > README.md
    echo "print(1)" > src/app.py
    git add -A
    git commit -qm base
    git rev-parse HEAD > "$base_file"
    eval "$body"
  ) >/dev/null 2>&1

  ( cd "$d" && BASE_SHA="$(cat "$base_file")" ISSUE_NUMBER=42 \
      GITHUB_ENV=$(mktemp) bash "$STEP" ) >/dev/null 2>&1
  rc=$?

  if [ "$rc" = "$want_rc" ]; then
    echo "PASS  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $name: expected rc=$want_rc, got rc=$rc"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$d" "$base_file"
}

check "writes its own spec"                0 'echo spec > docs/specs/42-a.md'
check "writes nothing at all"              1 'true'
check "also edits source"                  1 'echo spec > docs/specs/42-a.md; echo "print(2)" > src/app.py'
check "also adds a workflow"               1 'echo spec > docs/specs/42-a.md; mkdir -p .github/workflows; echo x > .github/workflows/evil.yml'
check "writes a spec for a different issue" 1 'echo spec > docs/specs/99-other.md'
check "commits the extra change itself"    1 'echo spec > docs/specs/42-a.md; echo "print(2)" > src/app.py; git add -A; git commit -qm sneaky'

rm -f "$STEP"
echo "planner-guard: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
