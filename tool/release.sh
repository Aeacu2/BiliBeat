#!/usr/bin/env bash
#
# Cuts a release: bumps pubspec.yaml, prepends a CHANGELOG.md entry, commits
# and tags. It deliberately does NOT build — run tool/build_release.sh
# afterwards, then attach the artifacts and symbols/ to the GitHub release.
#
#   tool/release.sh patch "first note" ["second note" ...]
#   tool/release.sh minor "..."
#   tool/release.sh major "..."
#
# Why this exists:
#
#   1. Before this script, the version number lived in three places that had
#      to be kept in sync by hand: pubspec.yaml, the commit message, and the
#      git tag. Releases 3.4.1, 3.5.x, 3.8.0/3.8.1 and 3.10.1/3.10.2 shipped
#      without tags at all. This script makes the tagged commit the single
#      act of releasing.
#   2. It refuses to run on a dirty tree, so the release commit contains
#      exactly the version bump and changelog entry — nothing accidental.
#   3. The build number (the +N in x.y.z+N) is bumped automatically. Android
#      uses it as versionCode; forgetting it makes installs reject updates.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  echo "usage: tool/release.sh <patch|minor|major> \"note\" [\"note\" ...]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
BUMP="$1"; shift
case "$BUMP" in
  patch|minor|major) ;;
  *) usage ;;
esac
NOTES=("$@")

# --- Preflight ---------------------------------------------------------------

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty — commit or stash first, so the release" >&2
  echo "       commit contains only the version bump and changelog entry." >&2
  git status --short >&2
  exit 1
fi

if ! git diff --quiet origin/main main 2>/dev/null; then
  echo "warning: local main differs from origin/main — did you forget to pull/push?" >&2
fi

# --- Version bump ------------------------------------------------------------

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
SHORT="${VERSION%%+*}"
BUILD="${VERSION##*+}"
MAJOR="${SHORT%%.*}"
REST="${SHORT#*.}"
MINOR="${REST%%.*}"
PATCH="${REST##*.}"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
NEW_SHORT="$MAJOR.$MINOR.$PATCH"
NEW_BUILD=$((BUILD + 1))
NEW_VERSION="$NEW_SHORT+$NEW_BUILD"

if git rev-parse "v$NEW_SHORT" >/dev/null 2>&1; then
  echo "error: tag v$NEW_SHORT already exists" >&2
  exit 1
fi

sed -i '' "s/^version: .*$/version: $NEW_VERSION/" pubspec.yaml
grep -q "^version: $NEW_VERSION$" pubspec.yaml || {
  echo "error: failed to update pubspec.yaml" >&2; exit 1; }

# --- Changelog ---------------------------------------------------------------

TODAY=$(date +%F)
{
  printf '## [%s] - %s\n\n' "$NEW_SHORT" "$TODAY"
  for note in "${NOTES[@]}"; do
    printf -- '- %s\n' "$note"
  done
  printf '\n'
} > /tmp/release_entry.md

# Insert the entry right above the first existing version heading.
awk '
  BEGIN { done = 0 }
  !done && /^## \[/ {
    while ((getline line < "/tmp/release_entry.md") > 0) print line
    close("/tmp/release_entry.md")
    done = 1
  }
  { print }
' CHANGELOG.md > CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md
rm -f /tmp/release_entry.md

# --- Commit + tag ------------------------------------------------------------

FIRST_NOTE="${NOTES[0]}"
git add pubspec.yaml CHANGELOG.md
git commit -m "feat(release): $NEW_SHORT - $FIRST_NOTE"
git tag "v$NEW_SHORT"

echo
echo "==> Released $NEW_VERSION (tag v$NEW_SHORT)"
echo
echo "Next steps:"
echo "  git push && git push --tags"
echo "  tool/build_release.sh all"
echo "  # then create the GitHub release for v$NEW_SHORT and attach the APK/IPA/DMG"
echo "  # plus the matching symbols/ directory contents"
