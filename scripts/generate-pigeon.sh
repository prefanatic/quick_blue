#!/usr/bin/env bash
# Canonical Pigeon generation, including JNIgen's compiled Android boundary.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${JAVA_HOME:?Set JAVA_HOME to JDK 17 or newer}"
: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
"$JAVA_HOME/bin/java" -version
test -x "$ANDROID_HOME/platform-tools/adb"
for package in quick_blue quick_blue_darwin quick_blue_windows; do
  (cd "$package" && dart run pigeon --input pigeons/messages.dart)
done
(cd quick_blue && dart run pigeon --input pigeons/availability.dart)
# Pigeon may report a skipped JNIgen stage as success on unsupported hosts.
test -s quick_blue/lib/src/availability.g.jni.dart
# Pigeon 30 emits trailing spaces in Swift documentation and JNI companions.
# Apply the same narrow, tested normalization locally and in CI.
python3 scripts/normalize_pigeon.py \
  quick_blue/lib/src/messages.g.dart \
  quick_blue/lib/src/availability.g.dart \
  quick_blue/lib/src/availability.native_interop.g.dart \
  quick_blue/lib/src/availability.g.jni.dart \
  quick_blue/tool/pigeon/availability_jnigen_config.dart \
  quick_blue/android/src/main/kotlin/com/example/quick_blue/Messages.g.kt \
  quick_blue/android/src/main/kotlin/com/example/quick_blue/Availability.g.kt \
  quick_blue_darwin/lib/src/messages.g.dart \
  quick_blue_darwin/darwin/quick_blue_darwin/Sources/quick_blue_darwin/Messages.g.swift \
  quick_blue_windows/lib/src/messages.g.dart \
  quick_blue_windows/windows/messages.g.cpp \
  quick_blue_windows/windows/messages.g.h
