#!/usr/bin/env bash
#
# bump_version.sh — Bump version and build number, commit, and tag locally.
#
# Usage:
#   ./bin/bump_version.sh v1.0.0           # release
#   ./bin/bump_version.sh v1.0.0-beta.1    # pre-release
#
# Versions follow Semantic Versioning 2.0.0; pre-releases carry a -beta.N suffix.
#
# What it does:
#   1. Validates the version format (vX.Y.Z or vX.Y.Z-beta.N).
#   2. Checks the working tree is clean.
#   3. Ensures the tag does not already exist.
#   4. Derives the next build number: CFBundleVersion of Resources/Info.plist plus 1.
#   5. Sets CFBundleShortVersionString (X.Y.Z without the -beta.N suffix) and
#      CFBundleVersion in Resources/Info.plist and Resources/LoginHelper-Info.plist.
#   6. For a release, moves the [Unreleased] entries of CHANGELOG.md under
#      "## [X.Y.Z] - date" (bin/changelog.py). A pre-release leaves them under
#      [Unreleased].
#   7. Commits with "Version bump to vX.Y.Z (build N)".
#   8. Creates a local git tag vX.Y.Z.
#
# Pushing the tag starts .github/workflows/draft-release.yml, which builds,
# signs, notarizes and drafts the GitHub release. Push manually when ready:
#   git push origin main --tags

set -euo pipefail
cd "$(dirname "$0")/.."

PLISTS=(Resources/Info.plist Resources/LoginHelper-Info.plist)

# ── Argument validation ────────────────────────────────────────────────────────

VERSION="${1:-}"

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]]; then
    echo "Usage: $0 vX.Y.Z | vX.Y.Z-beta.N"
    exit 1
fi

SHORT="${VERSION#v}"   # strip leading 'v', e.g. "1.0.0" or "1.0.0-beta.1"
BASE="${SHORT%%-*}"    # without the pre-release suffix, e.g. "1.0.0"

# ── Pre-flight checks ──────────────────────────────────────────────────────────

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: working tree is dirty. Commit or stash changes first."
    exit 1
fi

if git rev-parse --verify --quiet "$VERSION" > /dev/null; then
    echo "Error: tag '$VERSION' already exists."
    exit 1
fi

# ── Derive build number ────────────────────────────────────────────────────────

LAST_BUILD=$(plutil -extract CFBundleVersion raw "${PLISTS[0]}")
if [[ ! "$LAST_BUILD" =~ ^[0-9]+$ ]]; then
    echo "Error: CFBundleVersion in ${PLISTS[0]} is not a number: '$LAST_BUILD'."
    exit 1
fi
NEW_BUILD=$(( LAST_BUILD + 1 ))

echo "Bumping to ${VERSION} (build ${NEW_BUILD})..."

# ── Update the Info.plist files ────────────────────────────────────────────────
# The app and the login helper share the version and the build number.

for PLIST in "${PLISTS[@]}"; do
    plutil -replace CFBundleShortVersionString -string "$BASE" "$PLIST"
    plutil -replace CFBundleVersion -string "$NEW_BUILD" "$PLIST"
done

# ── Update CHANGELOG.md (releases only) ───────────────────────────────────────

if [[ "$SHORT" == "$BASE" ]]; then
    if ! python3 bin/changelog.py release "$BASE"; then
        git checkout -- "${PLISTS[@]}"
        exit 1
    fi
    git add CHANGELOG.md
fi

# ── Commit and tag ─────────────────────────────────────────────────────────────

git add "${PLISTS[@]}"
git commit -m "Version bump to ${VERSION} (build ${NEW_BUILD})"
# --no-sign: with tag.gpgsign set, a plain "git tag" asks for a message and fails.
git tag --no-sign "$VERSION"

echo ""
echo "Done:"
echo "  Version : ${VERSION}  (marketing: ${BASE})"
echo "  Build   : ${NEW_BUILD}"
echo ""
echo "Push when ready:"
echo "  git push origin main --tags"
