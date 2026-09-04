#!/usr/bin/env bash
set -euo pipefail

# Parse coverage percentages from a JaCoCo report (the format this pipeline
# produces) or a Kover report (kept for projects that use Kover instead).
#
# Usage:
#   parse_coverage.sh --jacoco app/build/reports/jacoco/jacocoTestReport/jacocoTestReport.xml
#   parse_coverage.sh --xml    app/build/reports/kover/xml/report.xml
#   parse_coverage.sh --html   app/build/reports/kover/html/index.html
#   parse_coverage.sh --find   .        # locate a JaCoCo report automatically
#
# Emits, e.g.:
#   Coverage: 78.23% line, 64.10% branch

JACOCO=""
HTML=""
XML=""
FIND_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jacoco) JACOCO="${2:-}"; shift 2 ;;
    --html)   HTML="${2:-}";   shift 2 ;;
    --xml)    XML="${2:-}";    shift 2 ;;
    --find)   FIND_ROOT="${2:-.}"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "$FIND_ROOT" && -z "$JACOCO" ]]; then
  JACOCO=$(find "$FIND_ROOT" -name 'jacocoTestReport.xml' -not -path '*/.pipeline/*' 2>/dev/null | head -1 || true)
fi

# ---------------------------------------------------------------------------
# JaCoCo: report-level <counter> elements are the LAST ones in the document,
# after every package element.
# ---------------------------------------------------------------------------
jacoco_pct () {
  local file="$1" type="$2"
  local line missed covered total

  line=$(grep -oE "<counter type=\"${type}\" missed=\"[0-9]+\" covered=\"[0-9]+\"[[:space:]]*/>" "$file" | tail -1 || true)
  [[ -n "$line" ]] || return 1

  missed=$(echo "$line"  | grep -oE 'missed="[0-9]+"'  | grep -oE '[0-9]+')
  covered=$(echo "$line" | grep -oE 'covered="[0-9]+"' | grep -oE '[0-9]+')
  total=$((missed + covered))

  if [[ "$total" -eq 0 ]]; then
    echo "0.00"
  else
    awk -v c="$covered" -v t="$total" 'BEGIN { printf "%.2f", (c/t)*100 }'
  fi
}

if [[ -n "$JACOCO" && -f "$JACOCO" ]]; then
  LINE_PCT=$(jacoco_pct "$JACOCO" LINE   || echo "")
  BRANCH_PCT=$(jacoco_pct "$JACOCO" BRANCH || echo "")

  if [[ -n "$LINE_PCT" ]]; then
    if [[ -n "$BRANCH_PCT" ]]; then
      echo "Coverage: ${LINE_PCT}% line, ${BRANCH_PCT}% branch"
    else
      echo "Coverage: ${LINE_PCT}% line"
    fi
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Kover fallbacks.
# ---------------------------------------------------------------------------
extract_from_html () {
  grep -oE 'Total[^%]*([0-9]+\.[0-9]+)%' "$1" | head -1 | grep -oE '[0-9]+\.[0-9]+' || true
}

extract_from_xml () {
  local rate
  rate=$(grep -oE 'line-rate="[0-9]+\.[0-9]+"' "$1" | head -1 | sed -E 's/line-rate="([0-9.]+)"/\1/' || true)
  [[ -n "$rate" ]] && awk -v r="$rate" 'BEGIN{printf "%.2f\n", (r*100)}'
}

PCT=""
[[ -n "$HTML" && -f "$HTML" ]] && PCT=$(extract_from_html "$HTML")
[[ -z "$PCT" && -n "$XML" && -f "$XML" ]] && PCT=$(extract_from_xml "$XML")

if [[ -z "$PCT" ]]; then
  echo "Coverage: N/A"
  exit 0
fi

echo "Coverage: ${PCT}% line"
