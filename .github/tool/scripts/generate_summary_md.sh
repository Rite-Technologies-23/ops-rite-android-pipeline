#!/usr/bin/env bash
set -euo pipefail

# Compose the GitHub Actions job summary for a CI run.
#
# Usage: generate_summary_md.sh [REPORTS_DIR]
#   REPORTS_DIR is the directory the summary job downloaded all artifacts into.
#
# Job results and coverage arrive via environment variables set by the workflow:
#   QUALITY_RESULT ANDROID_LINT_RESULT SECURITY_RESULT DEAD_CODE_RESULT
#   TEST_RESULT BUILD_RESULT
#   COVERAGE_PERCENT BRANCH_COVERAGE_PERCENT
#   COVERAGE_THRESHOLD COVERAGE_BRANCH_THRESHOLD

REPORTS_DIR="${1:-reports}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/tmp/job-summary.md}"

icon () {
  case "${1:-}" in
    success)  echo "PASS" ;;
    failure)  echo "FAIL" ;;
    cancelled) echo "CANCELLED" ;;
    skipped)  echo "skipped" ;;
    *)        echo "${1:-n/a}" ;;
  esac
}

# Read a one-line summary that a job wrote into its artifact, if present.
read_line () {
  local pattern="$1" fallback="$2"
  local f
  f=$(find "$REPORTS_DIR" -name "$pattern" 2>/dev/null | head -1 || true)
  if [[ -n "$f" && -f "$f" ]]; then
    head -1 "$f"
  else
    echo "$fallback"
  fi
}

JUNIT_TXT=$(read_line "junit-summary.txt" "JUnit: no report")
DETEKT_TXT=$(read_line "detekt-summary.txt" "Detekt: no report")
LINT_TXT=$(read_line "android-lint-summary.txt" "Android Lint: no report")

# ---- coverage ----
COVERAGE_LINE="Coverage: n/a"
if [[ -n "${COVERAGE_PERCENT:-}" ]]; then
  COVERAGE_LINE="Coverage: ${COVERAGE_PERCENT}% line (threshold ${COVERAGE_THRESHOLD:-0}%)"
  if [[ -n "${BRANCH_COVERAGE_PERCENT:-}" && "${COVERAGE_BRANCH_THRESHOLD:-0}" != "0" ]]; then
    COVERAGE_LINE="${COVERAGE_LINE}, ${BRANCH_COVERAGE_PERCENT}% branch (threshold ${COVERAGE_BRANCH_THRESHOLD}%)"
  elif [[ -n "${BRANCH_COVERAGE_PERCENT:-}" ]]; then
    COVERAGE_LINE="${COVERAGE_LINE}, ${BRANCH_COVERAGE_PERCENT}% branch (ungated)"
  fi
fi

# ---- security counts from the raw reports ----
SEMGREP_TXT="Semgrep: no report"
SEMGREP_JSON=$(find "$REPORTS_DIR" -name "semgrep.json" 2>/dev/null | head -1 || true)
if [[ -n "$SEMGREP_JSON" && -f "$SEMGREP_JSON" ]] && command -v jq >/dev/null 2>&1; then
  E=$(jq '[.results[]? | select(.extra.severity == "ERROR")]   | length' "$SEMGREP_JSON" 2>/dev/null || echo 0)
  W=$(jq '[.results[]? | select(.extra.severity == "WARNING")] | length' "$SEMGREP_JSON" 2>/dev/null || echo 0)
  SEMGREP_TXT="Semgrep: ${E} error(s), ${W} warning(s)"
fi

TRIVY_TXT="Trivy: no report"
TRIVY_JSON=$(find "$REPORTS_DIR" -name "trivy.json" 2>/dev/null | head -1 || true)
if [[ -n "$TRIVY_JSON" && -f "$TRIVY_JSON" ]] && command -v jq >/dev/null 2>&1; then
  C=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$TRIVY_JSON" 2>/dev/null || echo 0)
  H=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")]     | length' "$TRIVY_JSON" 2>/dev/null || echo 0)
  TRIVY_TXT="Dependencies: ${C} critical, ${H} high CVE(s)"
fi

GITLEAKS_TXT="Secrets: no report"
GITLEAKS_SARIF=$(find "$REPORTS_DIR" -name "gitleaks.sarif" 2>/dev/null | head -1 || true)
if [[ -n "$GITLEAKS_SARIF" && -f "$GITLEAKS_SARIF" ]] && command -v jq >/dev/null 2>&1; then
  G=$(jq '[.runs[]?.results[]?] | length' "$GITLEAKS_SARIF" 2>/dev/null || echo 0)
  GITLEAKS_TXT="Secrets: ${G} leak(s) detected"
fi

DEPS_TXT="Unused dependencies: no report"
HEALTH=$(find "$REPORTS_DIR" -name "build-health-report.txt" 2>/dev/null | head -1 || true)
if [[ -n "$HEALTH" && -f "$HEALTH" ]]; then
  U=$(grep -ciE 'unused|can be removed' "$HEALTH" 2>/dev/null || echo 0)
  DEPS_TXT="Unused dependencies: ${U} advice line(s) -- see the dead-code artifact"
fi

{
  echo "## Android CI Summary"
  echo
  echo "| Stage | Result | Detail |"
  echo "|---|---|---|"
  echo "| Lint & Format | $(icon "${QUALITY_RESULT:-}") | ${DETEKT_TXT} |"
  echo "| Android Lint | $(icon "${ANDROID_LINT_RESULT:-}") | ${LINT_TXT} |"
  echo "| Security | $(icon "${SECURITY_RESULT:-}") | ${SEMGREP_TXT}; ${GITLEAKS_TXT} |"
  echo "| Dependencies | $(icon "${SECURITY_RESULT:-}") | ${TRIVY_TXT} |"
  echo "| Dead Code | $(icon "${DEAD_CODE_RESULT:-}") | ${DEPS_TXT} |"
  echo "| Tests | $(icon "${TEST_RESULT:-}") | ${JUNIT_TXT} |"
  echo "| Coverage | $(icon "${TEST_RESULT:-}") | ${COVERAGE_LINE} |"
  echo "| Build | $(icon "${BUILD_RESULT:-}") | APK + AAB |"
  echo

  # Expand the detail blocks that carry more than one line.
  for f in "detekt-summary.txt" "android-lint-summary.txt" "junit-summary.txt"; do
    path=$(find "$REPORTS_DIR" -name "$f" 2>/dev/null | head -1 || true)
    if [[ -n "$path" && -f "$path" && $(wc -l < "$path") -gt 1 ]]; then
      echo "<details><summary>${f%.txt}</summary>"
      echo
      echo '```'
      cat "$path"
      echo '```'
      echo
      echo "</details>"
      echo
    fi
  done

  echo "Full reports are attached as workflow artifacts."
} >> "$SUMMARY_FILE"

echo "Summary written to ${SUMMARY_FILE}"
