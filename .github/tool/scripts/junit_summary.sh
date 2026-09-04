#!/usr/bin/env bash
set -euo pipefail

# Summarize JUnit test results across every module.
#
# Usage:
#   junit_summary.sh [ROOT]                 # default: current directory
#   junit_summary.sh app/build/test-results # legacy single-directory form
#
# Emits, e.g.:
#   JUnit: total=120, passed=118, failed=2, skipped=0

ROOT="${1:-.}"

# Restrict to test-results directories. Scanning every *.xml under the repo
# would also swallow lint/detekt reports and inflate the counts.
mapfile -t FILES < <(find "$ROOT" \
  -path '*/test-results/*' -name 'TEST-*.xml' \
  -not -path '*/.pipeline/*' 2>/dev/null || true)

if [[ ${#FILES[@]} -eq 0 ]]; then
  mapfile -t FILES < <(find "$ROOT" \
    -path '*/test-results/*' -name '*.xml' \
    -not -path '*/.pipeline/*' 2>/dev/null || true)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "JUnit: no XML reports under ${ROOT}"
  exit 0
fi

TOTAL=0
FAIL=0
SKIP=0

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue

  # Read the attributes from the <testsuite> element only. Nested <testcase>
  # elements do not carry these attributes, so head -1 is the suite header.
  header=$(grep -m1 '<testsuite ' "$f" 2>/dev/null || true)
  [[ -n "$header" ]] || continue

  attr () {
    echo "$header" | grep -oE "$1=\"[0-9]+\"" | head -1 | grep -oE '[0-9]+' || true
  }

  t=$(attr tests);    t=${t:-0}
  f1=$(attr failures); f1=${f1:-0}
  e1=$(attr errors);   e1=${e1:-0}
  s=$(attr skipped);   s=${s:-0}

  TOTAL=$((TOTAL + t))
  FAIL=$((FAIL + f1 + e1))
  SKIP=$((SKIP + s))
done

PASSED=$((TOTAL - FAIL - SKIP))
echo "JUnit: total=$TOTAL, passed=$PASSED, failed=$FAIL, skipped=$SKIP"

# Name the failing tests -- a bare count is not actionable.
if [[ "$FAIL" -gt 0 ]]; then
  echo "  failures:"
  grep -hoE '<testcase name="[^"]*" classname="[^"]*"' "${FILES[@]}" 2>/dev/null >/dev/null || true
  for f in "${FILES[@]}"; do
    if grep -q '<failure\|<error ' "$f" 2>/dev/null; then
      suite=$(grep -m1 '<testsuite ' "$f" | grep -oE 'name="[^"]*"' | head -1 | sed -E 's/name="([^"]*)"/\1/')
      echo "    ${suite:-$(basename "$f")}"
    fi
  done | sort -u | head -20
fi
