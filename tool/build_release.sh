#!/usr/bin/env bash
#
# Builds the shippable release artifacts with Dart obfuscation.
#
#   tool/build_release.sh            # android (default)
#   tool/build_release.sh ios
#   tool/build_release.sh all
#
# Android: a single arm64-only APK. `--target-platform android-arm64` keeps
# Flutter from compiling the other ABIs at all, and `abiFilters` in
# android/app/build.gradle is the backstop so even a plain `flutter build apk`
# cannot ship 32-bit.
#
# iOS: an **unsigned** .ipa for sideloading (AltStore / Sideloadly / your own
# provisioning profile). There is no Apple Developer account behind this app,
# so there is nothing to sign with here and nothing to submit to; the archive
# is built with --no-codesign and packaged by hand. Whoever installs it signs
# it with their own identity.
#
# Things this exists to get right, because all of them have already bitten us:
#
#   1. JDK version. AGP's bundled lint calls java.util.List.removeLast(), which
#      only exists on JDK 21+. Building on JDK 17 fails deep inside lint with a
#      NoSuchMethodError that says nothing about Java versions.
#   2. Symbol files. --obfuscate renames every identifier, so a crash from a
#      shipped build is unreadable without the matching .symbols file. They are
#      written to symbols/<version>/ and MUST be kept for as long as that
#      version is in anyone's hands. Attach them to the GitHub release.
#   3. iOS has no CocoaPods. Every plugin this app uses ships a Package.swift,
#      so the project is integrated through Swift Package Manager and there is
#      deliberately no ios/Podfile. Do not re-add one to "fix" a build; if a
#      future plugin is Pods-only, regenerate it with `flutter create .` and
#      say so here.
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-android}"
case "$TARGET" in
  android|ios|all) ;;
  *) echo "usage: tool/build_release.sh [android|ios|all]" >&2; exit 2 ;;
esac

# Flutter is not always on PATH (it isn't on this machine), so resolve it
# rather than failing halfway through with "command not found".
FLUTTER="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [ -z "$FLUTTER" ] && [ -x "$HOME/flutter/bin/flutter" ]; then
  FLUTTER="$HOME/flutter/bin/flutter"
fi
if [ -z "$FLUTTER" ]; then
  echo "error: flutter not found; set FLUTTER_BIN=/path/to/flutter" >&2
  exit 1
fi

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
SHORT_VERSION="${VERSION%%+*}"
SYMBOLS_DIR="symbols/$VERSION"
mkdir -p "$SYMBOLS_DIR"

build_android() {
  : "${JAVA_HOME:=/opt/homebrew/opt/openjdk@21}"
  export JAVA_HOME
  export PATH="$JAVA_HOME/bin:$PATH"

  if ! java -version 2>&1 | grep -qE '"(2[1-9]|[3-9][0-9])'; then
    echo "error: need JDK 21+ (AGP lint requires it); JAVA_HOME=$JAVA_HOME" >&2
    java -version >&2 || true
    exit 1
  fi

  if [ ! -f android/key.properties ]; then
    echo "WARNING: android/key.properties not found — this build will be signed" >&2
    echo "         with the DEBUG key and must not be published." >&2
    echo "         Run tool/make_keystore.sh first." >&2
    echo >&2
  fi

  echo "==> Android $VERSION (obfuscated), symbols -> $SYMBOLS_DIR"
  # No --split-per-abi: with a single ABI there is nothing to split, and AGP
  # rejects `splits.abi` and `ndk.abiFilters` being set at the same time
  # ("Conflicting configuration ... cannot be present when splits abi filters
  # are set"). The output is a single app-release.apk containing only arm64.
  "$FLUTTER" build apk --release \
    --target-platform android-arm64 \
    --obfuscate \
    --split-debug-info="$SYMBOLS_DIR"

  # Publish under a name that says what it is, rather than "app-release.apk".
  cp build/app/outputs/flutter-apk/app-release.apk \
     "build/app/outputs/flutter-apk/bilibeat-${SHORT_VERSION}-arm64-v8a.apk"

  echo
  echo "==> APK"
  ls -lh build/app/outputs/flutter-apk/*-release.apk
}

build_ios() {
  if [ "$(uname)" != "Darwin" ]; then
    echo "error: iOS builds need macOS with Xcode" >&2
    exit 1
  fi

  echo "==> iOS $VERSION (obfuscated, unsigned), symbols -> $SYMBOLS_DIR"
  "$FLUTTER" build ios --release --no-codesign \
    --obfuscate \
    --split-debug-info="$SYMBOLS_DIR"

  # An .ipa is just a zip with the .app inside a Payload/ directory. Building
  # one by hand (rather than via `flutter build ipa`, which insists on an
  # export method and therefore a signing identity) is what lets an unsigned
  # build be produced at all.
  local out_dir="build/ios/ipa"
  local ipa="$out_dir/bilibeat-${SHORT_VERSION}-unsigned.ipa"
  rm -rf "$out_dir"
  mkdir -p "$out_dir/Payload"
  cp -R build/ios/iphoneos/Runner.app "$out_dir/Payload/"
  (cd "$out_dir" && zip -qry "$(basename "$ipa")" Payload)
  rm -rf "$out_dir/Payload"

  echo
  echo "==> IPA (UNSIGNED — sideload with AltStore/Sideloadly, or re-sign)"
  ls -lh "$ipa"
}

case "$TARGET" in
  android) build_android ;;
  ios) build_ios ;;
  all) build_android; build_ios ;;
esac

echo
echo "==> Symbols (keep these — required to read any crash from this build)"
ls -lh "$SYMBOLS_DIR"
echo
echo "Symbolize a stack trace with:"
echo "  flutter symbolize -i <trace.txt> -d $SYMBOLS_DIR/<app.*.symbols>"
