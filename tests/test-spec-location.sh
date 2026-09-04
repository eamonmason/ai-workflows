#!/usr/bin/env bash
# Exercises the executor's "Locate the approved spec" step.
#
# The step body is extracted from the workflow at run time rather than copied
# here, so this cannot silently drift from what the runner executes.
#
# The property under test is fail-closed: the executor must refuse to run the
# agent unless exactly one spec branch and exactly one spec file exist. Zero is
# "nobody approved this"; more than one is "it is not clear what was approved".
# Both must stop the run rather than pick one.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
STEP=$(mktemp)
python3 tests/extract-step.py \
  .github/workflows/reusable-executor.yml execute spec > "$STEP"

PASS=0
FAIL=0

check() {
  local name="$1" want_found="$2" body="$3"
  local remote clone out rc found

  remote=$(mktemp -d)
  clone=$(mktemp -d)
  out=$(mktemp)

  (
    set -e
    git init -q --bare "$remote"
    seed=$(mktemp -d)
    cd "$seed"
    git init -q -b main
    git config user.email test@example.com
    git config user.name test
    mkdir -p docs/specs
    echo readme > README.md
    git add -A
    git commit -qm base
    git remote add origin "$remote"
    git push -q origin main
    # $body creates whatever branches and spec files the case needs.
    eval "$body"
    rm -rf "$seed"
  ) >/dev/null 2>&1

  git clone -q "$remote" "$clone" >/dev/null 2>&1

  (
    cd "$clone" || exit 1
    ISSUE_NUMBER=42 GITHUB_OUTPUT="$out" GITHUB_ENV=$(mktemp) bash "$STEP"
  ) >/dev/null 2>&1
  rc=$?
  found=$(grep -o 'found=[a-z]*' "$out" | tail -1)
  found=${found#found=}

  if [ "$rc" = "0" ] && [ "${found:-none}" = "$want_found" ]; then
    echo "PASS  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $name: expected found=$want_found (rc 0), got found=${found:-none} rc=$rc"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$remote" "$clone" "$out"
}

mkbranch() {
  # mkbranch <branch> <spec-file>...
  local br="$1"; shift
  git checkout -q -B "$br" main
  for f in "$@"; do
    mkdir -p "$(dirname "$f")"
    echo "spec" > "$f"
  done
  git add -A
  git commit -qm "spec on $br"
  git push -q origin "$br"
}

check "one branch, one spec"            true  'mkbranch agent/42-a docs/specs/42-a.md'
check "no spec branch at all"           false 'true'
check "branch for a different issue"    false 'mkbranch agent/7-a docs/specs/7-a.md'
check "two branches for one issue"      false 'mkbranch agent/42-a docs/specs/42-a.md; mkbranch agent/42-b docs/specs/42-b.md'
check "branch exists but no spec file"  false 'mkbranch agent/42-a'
check "two spec files on one branch"    false 'mkbranch agent/42-a docs/specs/42-a.md docs/specs/42-b.md'
check "spec numbered like a prefix"     false 'mkbranch agent/42-a docs/specs/420-a.md'

rm -f "$STEP"
echo "spec-location: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
