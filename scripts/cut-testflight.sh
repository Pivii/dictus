#!/bin/sh
# cut-testflight.sh — prepare a TestFlight build from `develop`.
#
# What it does (deterministic, no room to forget a step):
#   1. Verify we are on a clean `develop`, in sync with origin.
#   2. Increment CFBundleVersion (build number) across the 3 Info.plists.
#   3. Optionally set CFBundleShortVersionString (marketing version) if passed.
#   4. Commit `chore: bump to X.Y.Z (build N)`.
#   5. Create the lightweight `build/N` tag on that commit.
#   6. Push develop + the tag.
#
# After this: archive from `develop` in Xcode and upload to App Store Connect.
# The `build/N` tag is the anchor used later by promote-to-appstore.sh.
#
# Usage:
#   scripts/cut-testflight.sh            # build-number bump only (same version)
#   scripts/cut-testflight.sh 1.8.0      # also set marketing version to 1.8.0
#
# See docs/VERSIONING.md and docs/GIT_WORKFLOW.md for the full policy.
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

PLISTS="DictusApp/Info.plist DictusKeyboard/Info.plist DictusWidgets/Info.plist"
PB=/usr/libexec/PlistBuddy
NEW_VERSION="${1:-}"

# --- Safety gates -----------------------------------------------------------
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "develop" ]; then
  echo "error: must be on 'develop' (currently on '$BRANCH'). Aborting." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is not clean. Commit or stash first. Aborting." >&2
  git status --short >&2
  exit 1
fi
git fetch origin develop --quiet
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/develop)" ]; then
  echo "error: local develop is not in sync with origin/develop. Pull/push first." >&2
  exit 1
fi

# --- Compute the new build number -------------------------------------------
CUR_BUILD=$($PB -c "Print :CFBundleVersion" DictusApp/Info.plist)
case "$CUR_BUILD" in
  ''|*[!0-9]*) echo "error: current build number '$CUR_BUILD' is not an integer." >&2; exit 1 ;;
esac
NEW_BUILD=$((CUR_BUILD + 1))

# Guard: the build/N tag must not already exist (build numbers never repeat).
if git rev-parse -q --verify "refs/tags/build/$NEW_BUILD" >/dev/null; then
  echo "error: tag build/$NEW_BUILD already exists. Build numbers never repeat." >&2
  exit 1
fi

# Marketing version: keep current unless an argument is given.
CUR_VERSION=$($PB -c "Print :CFBundleShortVersionString" DictusApp/Info.plist)
if [ -n "$NEW_VERSION" ]; then
  case "$NEW_VERSION" in
    [0-9]*.[0-9]*.[0-9]*|[0-9]*.[0-9]*) : ;;
    *) echo "error: '$NEW_VERSION' is not a valid X.Y.Z marketing version." >&2; exit 1 ;;
  esac
  VERSION="$NEW_VERSION"
else
  VERSION="$CUR_VERSION"
fi

echo "→ version  : $CUR_VERSION -> $VERSION"
echo "→ build    : $CUR_BUILD -> $NEW_BUILD"
echo "→ plists   : $PLISTS"
printf "Proceed? [y/N] "
read -r ANSWER
case "$ANSWER" in [yY]*) : ;; *) echo "Aborted."; exit 1 ;; esac

# --- Apply to all three plists ----------------------------------------------
for P in $PLISTS; do
  $PB -c "Set :CFBundleVersion $NEW_BUILD" "$P"
  $PB -c "Set :CFBundleShortVersionString $VERSION" "$P"
done

# --- Commit, tag, push ------------------------------------------------------
git add $PLISTS
git commit -m "chore: bump to $VERSION (build $NEW_BUILD)"
git tag "build/$NEW_BUILD"
git push origin develop "build/$NEW_BUILD"

echo ""
echo "✅ develop bumped to $VERSION (build $NEW_BUILD), tagged build/$NEW_BUILD, pushed."
echo "   Next: Xcode → Product > Archive (scheme DictusApp, from develop) → upload to App Store Connect."
echo "   To ship this build to the App Store later: scripts/promote-to-appstore.sh $NEW_BUILD"
