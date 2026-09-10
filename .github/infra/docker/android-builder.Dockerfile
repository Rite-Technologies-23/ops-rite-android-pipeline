# syntax=docker/dockerfile:1
# ------------------------------------------------------------
# 🧱 Android Builder Dockerfile
#   - Base image for Android / Kotlin / Jetpack Compose builds
#   - Contains JDK 17, Gradle, and Android SDK
# ------------------------------------------------------------

FROM ubuntu:22.04

LABEL maintainer="Rite Technologies DevOps Team <devops@ritetech.com>"
LABEL description="Android Builder Image with JDK17 and SDK Tools"

# -------------------------------------------------------------------
# Install system dependencies
# -------------------------------------------------------------------
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    wget curl unzip zip git ca-certificates sudo \
    openjdk-17-jdk \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

# -------------------------------------------------------------------
# Install Android SDK Command-line Tools
#   Build number/checksum kept in sync with
#   .github/actions/setup-android/install_sdk.sh -- bump both together.
# -------------------------------------------------------------------
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && cd ${ANDROID_HOME}/cmdline-tools \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O sdk-tools.zip \
    && echo "d313adb7aedccf6cf0cfca51ec180f0059f5f8f8  sdk-tools.zip" | sha1sum -c - \
    && unzip -q sdk-tools.zip -d latest \
    && rm sdk-tools.zip

# -------------------------------------------------------------------
# Accept licenses and install SDK components
# -------------------------------------------------------------------
RUN yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_HOME} --licenses && \
    ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_HOME} \
      "platform-tools" \
      "build-tools;34.0.0" \
      "platforms;android-34"

# -------------------------------------------------------------------
# Pre-install Gradle for faster builds
# -------------------------------------------------------------------
ARG GRADLE_VERSION=8.7
RUN wget -q https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip -O gradle.zip && \
    unzip -q gradle.zip -d /opt/gradle && \
    rm gradle.zip
ENV PATH=$PATH:/opt/gradle/gradle-${GRADLE_VERSION}/bin

# -------------------------------------------------------------------
# Run as a non-root user. sudo stays available for anyone who needs to
# install extra packages inside a container built from this image.
# -------------------------------------------------------------------
RUN useradd --create-home --shell /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder \
    && chmod 0440 /etc/sudoers.d/builder \
    && mkdir -p /workspace \
    && chown -R builder:builder /workspace "$ANDROID_HOME"

USER builder
WORKDIR /workspace

# -------------------------------------------------------------------
# Default command prints Gradle + SDK info
# -------------------------------------------------------------------
CMD ["bash", "-c", "gradle -v && sdkmanager --list | head -20"]
