#!/usr/bin/env bash
#
# Creates the release signing keystore and android/key.properties.
#
# Run this ONCE, ever. Then back up BOTH files somewhere you will still have
# them in five years:
#
#     android/bilibeat-release.jks
#     android/key.properties
#
# Losing the keystore is unrecoverable: Android identifies an app by its
# signing key, so a replacement key cannot update an existing install. Every
# user would have to uninstall (losing downloaded audio and playlists) and
# install fresh. Both files are gitignored — they must never be committed.
#
# keytool prompts for the passwords interactively; they are not passed on the
# command line, so they stay out of your shell history and process list.
set -euo pipefail

cd "$(dirname "$0")/.."

KEYSTORE="android/bilibeat-release.jks"
PROPS="android/key.properties"
ALIAS="bilibeat"

if [ -e "$KEYSTORE" ] || [ -e "$PROPS" ]; then
  echo "error: $KEYSTORE or $PROPS already exists." >&2
  echo "Refusing to overwrite — that would orphan every existing install." >&2
  exit 1
fi

: "${JAVA_HOME:=/opt/homebrew/opt/openjdk@21}"
export PATH="$JAVA_HOME/bin:$PATH"
command -v keytool >/dev/null || { echo "error: keytool not on PATH" >&2; exit 1; }

echo "Creating a 10000-day RSA-4096 key. You will be asked for:"
echo "  * a keystore password (choose a strong one, store it in a password manager)"
echo "  * a name/organisation (any value is fine for a personal app)"
echo

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000

# keytool -genkeypair uses one password for both store and key here.
printf 'Re-enter the keystore password to write %s: ' "$PROPS"
read -rs PASS
echo

umask 077
cat > "$PROPS" <<PROPEOF
storeFile=bilibeat-release.jks
storePassword=$PASS
keyAlias=$ALIAS
keyPassword=$PASS
PROPEOF
unset PASS

echo
echo "Wrote $PROPS (mode $(stat -f '%Lp' "$PROPS"))."
echo "Verify the build picks it up:"
echo "  tool/build_release.sh"
echo "  # then confirm the signer is no longer 'Android Debug':"
echo "  apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk"
