#!/usr/bin/env bash
#
# Builds the release APKs with Dart obfuscation.
#
# Two things this exists to get right, because both have already bitten us:
#
#   1. JDK version. AGP's bundled lint calls java.util.List.removeLast(), which
#      only exists on JDK 21+. Building on JDK 17 fails deep inside lint with a
#      NoSuchMethodError that says nothing about Java versions.
#   2. Symbol files. --obfuscate renames every identifier, so a crash from a
#      shipped build is unreadable without the matching .symbols file. They are
#      written to symbols/<version>/ and MUST be kept for as long as that
#      version is in anyone's hands. Attach them to the GitHub release.
#
# Usage: tool/build_release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

: "${JAVA_HOME:=/opt/homebrew/opt/openjdk@21}"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

if ! java -version 2>&1 | grep -qE '"(2[1-9]|[3-9][0-9])'; then
  echo "error: need JDK 21+ (AGP lint requires it); JAVA_HOME=$JAVA_HOME" >&2
  java -version >&2 || true
  exit 1
fi

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
SYMBOLS_DIR="symbols/$VERSION"
mkdir -p "$SYMBOLS_DIR"

echo "==> Building $VERSION (obfuscated), symbols -> $SYMBOLS_DIR"
"$FLUTTER" build apk --release \
  --split-per-abi \
  --obfuscate \
  --split-debug-info="$SYMBOLS_DIR"

echo
echo "==> APKs"
ls -lh build/app/outputs/flutter-apk/*-release.apk
echo
echo "==> Symbols (keep these — required to read any crash from this build)"
ls -lh "$SYMBOLS_DIR"
echo
echo "Symbolize a stack trace with:"
echo "  flutter symbolize -i <trace.txt> -d $SYMBOLS_DIR/app.android-arm64.symbols"
