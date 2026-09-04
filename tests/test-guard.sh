#!/usr/bin/env bash
# Exercises the protected-path guard from reusable-executor.yml.
#
# The step body is extracted from the workflow at run time rather than copied
# here, so this cannot silently drift from what the runner executes.
#
# The cases that matter most are the two where the agent commits on its own.
# It has unrestricted Bash, so it can do that rather than leave changes staged;
# the guard diffs against the pre-agent commit precisely so that does not slip
# past.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
STEP=$(mktemp)
python3 tests/extract-step.py \
  .github/workflows/reusable-executor.yml execute "Guard protected paths" > "$STEP"

PASS=0
FAIL=0

check() {
  local name="$1" want_rc="$2" want_changes="$3" body="$4"
  local d env_file log base_file rc ch
  d=$(mktemp -d)
  # $GITHUB_ENV must live outside the work tree, or `git add -A` stages it.
  env_file=$(mktemp)
  log=$(mktemp)
  # Also outside the work tree, for the same reason.
  base_file=$(mktemp)

  (
    set -e
    cd "$d"
    git init -q -b main
    git config user.email test@example.com
    git config user.name test
    mkdir -p src scripts .github/workflows
    echo "print(1)" > src/app.py
    printf '#!/bin/sh\ntrue\n' > scripts/verify.sh
    chmod +x scripts/verify.sh
    echo "name: ci" > .github/workflows/ci.yml
    printf '.entire\n.env\n' > .gitignore
    git add -A
    git commit -qm base
    git rev-parse HEAD > "$base_file"

    # Whatever the agent is pretending to have done, including committing.
    eval "$body"
  ) >/dev/null 2>&1

  ( cd "$d" && BASE_SHA="$(cat "$base_file")" GITHUB_ENV="$env_file" \
      bash "$STEP" ) > "$log" 2>&1
  rc=$?
  ch=$(grep -o 'HAS_CHANGES=[a-z]*' "$env_file" | tail -1)
  ch=${ch#HAS_CHANGES=}

  if [ "$rc" = "$want_rc" ] && [ "${ch:-none}" = "$want_changes" ]; then
    echo "PASS  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $name: expected rc=$want_rc changes=$want_changes, got rc=$rc changes=${ch:-none}"
    sed 's/^/        /' "$log" | head -5
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$d" "$env_file" "$log" "$base_file"
}

#     name                                   rc  changes  what the agent did
check "legitimate source edit"               0  true  'echo "print(2)" > src/app.py'
check "new source file"                      0  true  'echo "x = 1" > src/new.py'
check "no changes at all"                    0  false 'true'
check "edits an existing workflow"           1  none  'echo "name: evil" > .github/workflows/ci.yml'
check "adds a new workflow"                  1  none  'echo "x" > .github/workflows/new.yml'
check "edits the verification script"        1  none  'echo "exit 0" >> scripts/verify.sh'
check "force-adds gitignored .entire/"       1  none  'mkdir -p .entire && echo s > .entire/t.json && git add -f .entire/t.json'
check "force-adds gitignored .env"           1  none  'echo "K=v" > .env && git add -f .env'
check "adds a .pem private key"              1  none  'echo key > deploy.pem'
check "adds an id_rsa"                       1  none  'echo key > id_rsa'
check "commits a workflow edit itself"       1  none  'echo "name: evil" > .github/workflows/ci.yml && git add -A && git commit -qm sneaky'
check "commits a verify.sh edit itself"      1  none  'echo "exit 0" > scripts/verify.sh && git add -A && git commit -qm sneaky'
check "commits legitimate code itself"       0  true  'echo "print(3)" > src/app.py && git add -A && git commit -qm ok'

rm -f "$STEP"
echo "guard: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
