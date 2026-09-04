#!/usr/bin/env bash
set -euo pipefail

# Summarize Detekt results across every module.
#
# Usage:
#   lint_summary.sh [ROOT]            # default: current directory
#   lint_summary.sh app/build/reports/detekt   # legacy single-directory form
#
# Emits one line, e.g.:
#   Detekt: 12 issues across 3 module(s)

ROOT="${1:-.}"

# Legacy form: a directory that directly contains detekt.xml/txt/html.
if [[ -f "${ROOT}/detekt.xml" || -f "${ROOT}/detekt.txt" || -f "${ROOT}/detekt.html" ]]; then
  FILES=("${ROOT}/detekt.xml")
else
  mapfile -t FILES < <(find "$ROOT" \
    -path '*/build/reports/detekt/detekt.xml' \
    -not -path '*/.pipeline/*' 2>/dev/null || true)
fi

if [[ ${#FILES[@]} -eq 0 || ! -f "${FILES[0]}" ]]; then
  echo "Detekt: no report found under ${ROOT}"
  exit 0
fi

TOTAL=0
MODULES=0

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  n=$(grep -c '<error ' "$f" 2>/dev/null || true)
  n=${n:-0}
  TOTAL=$((TOTAL + n))
  MODULES=$((MODULES + 1))
done

echo "Detekt: ${TOTAL} issues across ${MODULES} module(s)"

# Surface the most common rules so the summary is actionable, not just a count.
if [[ "$TOTAL" -gt 0 ]]; then
  grep -ho 'source="[^"]*"' "${FILES[@]}" 2>/dev/null \
    | sed -E 's/source="detekt\.([^"]*)"/\1/; s/source="([^"]*)"/\1/' \
    | sort | uniq -c | sort -rn | head -10 \
    | awk '{ printf "  %s x%s\n", $2, $1 }'
fi
