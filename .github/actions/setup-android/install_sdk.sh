#!/usr/bin/env bash
set -euo pipefail

# Installs the Android SDK and required components.
#
# Only needed on self-hosted runners -- GitHub-hosted ubuntu images already ship
# the SDK. Invoked by the setup-android composite action when install_sdk=true.
#
# This script deliberately does NOT touch the caller's Gradle wrapper. The
# wrapper is bootstrapped separately, from the version the caller declares, so
# that CI never silently builds with a different Gradle than the developers do.

echo "Installing Android SDK and required components..."

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-11076708_latest.zip"

mkdir -p "$ANDROID_SDK_ROOT"
echo "SDK directory: $ANDROID_SDK_ROOT"

# -------------------------------------------------------------
# 1. Download command-line tools if missing
#    Runs in a subshell so the cd does not leak into later steps.
# -------------------------------------------------------------
if [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" ]; then
  echo "Downloading Android command-line tools..."
  (
    mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
    cd "$ANDROID_SDK_ROOT/cmdline-tools"
    curl -sSL "https://dl.google.com/android/repository/${CMDLINE_TOOLS_ZIP}" -o cmdline-tools.zip
    unzip -q cmdline-tools.zip
    rm -rf latest
    mv cmdline-tools latest
    rm cmdline-tools.zip
  )
fi

# -------------------------------------------------------------
# 2. Environment for this step
# -------------------------------------------------------------
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

# -------------------------------------------------------------
# 3. Install required packages
# -------------------------------------------------------------
COMPILE_SDK="${ANDROID_COMPILE_SDK:-34}"
BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-34.0.0}"

echo "Installing platform-tools, platforms;android-${COMPILE_SDK}, build-tools;${BUILD_TOOLS}..."
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager --install \
  "platform-tools" \
  "platforms;android-${COMPILE_SDK}" \
  "build-tools;${BUILD_TOOLS}" >/dev/null

# -------------------------------------------------------------
# 4. Persist env and PATH for subsequent steps
# -------------------------------------------------------------
{
  echo "ANDROID_HOME=$ANDROID_SDK_ROOT"
  echo "ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
} >> "${GITHUB_ENV:-/dev/null}"

{
  echo "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"
  echo "$ANDROID_SDK_ROOT/platform-tools"
  echo "$ANDROID_SDK_ROOT/emulator"
} >> "${GITHUB_PATH:-/dev/null}"

echo "Android SDK installation complete."
