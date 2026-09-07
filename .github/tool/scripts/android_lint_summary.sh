#!/usr/bin/env bash
set -euo pipefail

# Summarize Android Lint results across every module, split by severity and
# with the security-relevant issue ids called out separately.
#
# Usage: android_lint_summary.sh [ROOT]     # default: current directory
#
# Emits, e.g.:
#   Android Lint: 3 error(s), 41 warning(s) -- 1 security, 12 unused resource(s)

ROOT="${1:-.}"

mapfile -t FILES < <(find "$ROOT" \
  -path '*/build/reports/lint-results*.xml' \
  -not -path '*/.pipeline/*' 2>/dev/null || true)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Android Lint: no report found under ${ROOT}"
  exit 0
fi

# Issue ids the pipeline treats as security-relevant. Kept in sync with the
# fatal list in gradle/android-lint.init.gradle.
SECURITY_IDS='AllowBackup|HardcodedDebugMode|Exported(Activity|ContentProvider|Receiver|Service)|TrustAllX509TrustManager|BadHostnameVerifier|UnsafeProtectedBroadcastReceiver|SetJavaScriptEnabled|UnsafeDynamicallyLoadedCode|World(Readable|Writeable)Files|SetWorld(Readable|Writable)|CustomX509TrustManager|SecureRandom|TrulyRandom|PackagedPrivateKey|GrantAllUris|CipherGetInstanceAES|JavascriptInterface|UnprotectedSMSBroadcastReceiver'
DEADCODE_IDS='UnusedResources|UnusedIds|UnusedNamespace|UnusedQuantity|UnusedAttribute'

ERRORS=0
WARNINGS=0
FATALS=0
SECURITY=0
DEADCODE=0

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  ERRORS=$((ERRORS     + $(grep -c 'severity="Error"'       "$f" 2>/dev/null || true) ))
  WARNINGS=$((WARNINGS + $(grep -c 'severity="Warning"'     "$f" 2>/dev/null || true) ))
  FATALS=$((FATALS     + $(grep -c 'severity="Fatal"'       "$f" 2>/dev/null || true) ))
  SECURITY=$((SECURITY + $(grep -oE "id=\"(${SECURITY_IDS})\"" "$f" 2>/dev/null | wc -l) ))
  DEADCODE=$((DEADCODE + $(grep -oE "id=\"(${DEADCODE_IDS})\"" "$f" 2>/dev/null | wc -l) ))
done

ERRORS=$((ERRORS + FATALS))

echo "Android Lint: ${ERRORS} error(s), ${WARNINGS} warning(s) -- ${SECURITY} security, ${DEADCODE} unused resource(s)"

if [[ "$SECURITY" -gt 0 ]]; then
  echo "  security issues:"
  grep -hoE "id=\"(${SECURITY_IDS})\"" "${FILES[@]}" 2>/dev/null \
    | sed -E 's/id="([^"]*)"/\1/' \
    | sort | uniq -c | sort -rn \
    | awk '{ printf "    %s x%s\n", $2, $1 }'
fi

if [[ "$DEADCODE" -gt 0 ]]; then
  echo "  dead resources:"
  grep -hoE "id=\"(${DEADCODE_IDS})\"" "${FILES[@]}" 2>/dev/null \
    | sed -E 's/id="([^"]*)"/\1/' \
    | sort | uniq -c | sort -rn \
    | awk '{ printf "    %s x%s\n", $2, $1 }'
fi
