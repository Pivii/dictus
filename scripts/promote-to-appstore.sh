#!/bin/sh
# promote-to-appstore.sh — ship a TestFlight build to the App Store.
#
# Pins the release to the EXACT commit that produced build N (the `build/N`
# tag), never to develop's current tip — so the bits users get are the bits
# that were tested on TestFlight, even if develop has moved on since.
#
# What it does:
#   1. Resolve the `build/N` tag -> commit C and marketing version X.Y.Z.
#   2. Create an ephemeral `release/X.Y.Z` branch at C and open a PR to main.
#   3. Wait for required checks (Build + SwiftLint), then merge with --admin.
#   4. Tag `vX.Y.Z` (annotated) on main + push, create a GitHub Release.
#   5. Back-merge main -> develop (the step that must never be forgotten).
#   6. Print the App Store Connect checklist (the only manual part).
#
# The binary is NOT rebuilt: in App Store Connect you select build N (already
# uploaded from TestFlight) and submit it. This script only moves source +
# tags + the GitHub release.
#
# Usage:
#   scripts/promote-to-appstore.sh 18
#
# See docs/VERSIONING.md and docs/GIT_WORKFLOW.md for the full policy.
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"
PB=/usr/libexec/PlistBuddy

N="${1:-}"
case "$N" in
  ''|*[!0-9]*) echo "usage: scripts/promote-to-appstore.sh <build-number>" >&2; exit 1 ;;
esac

TAG="build/$N"
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  git fetch origin --tags --quiet
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || {
    echo "error: tag $TAG not found. Was build $N cut with cut-testflight.sh?" >&2; exit 1; }
fi

COMMIT=$(git rev-parse "$TAG^{commit}")
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
git show "$TAG:DictusApp/Info.plist" > "$TMP"
VERSION=$($PB -c "Print :CFBundleShortVersionString" "$TMP")
VTAG="v$VERSION"
RELEASE_BRANCH="release/$VERSION"

if git rev-parse -q --verify "refs/tags/$VTAG" >/dev/null; then
  echo "error: tag $VTAG already exists — $VERSION looks already released." >&2; exit 1
fi

echo "→ build      : $N  (tag $TAG)"
echo "→ commit     : $COMMIT"
echo "→ version    : $VERSION  -> will tag $VTAG + GitHub Release"
echo "→ PR         : $RELEASE_BRANCH -> main (admin merge after CI)"
printf "Proceed with the App Store promotion of build %s? [y/N] " "$N"
read -r ANSWER
case "$ANSWER" in [yY]*) : ;; *) echo "Aborted."; exit 1 ;; esac

# --- 1. Ephemeral release branch at the pinned commit -----------------------
git branch -f "$RELEASE_BRANCH" "$COMMIT"
git push -f origin "$RELEASE_BRANCH"

# --- 2. PR to main ----------------------------------------------------------
PR_URL=$(gh pr create --base main --head "$RELEASE_BRANCH" \
  --title "release: $VTAG (build $N)" \
  --body "Promote TestFlight build $N (\`$TAG\`, commit \`$COMMIT\`) to the App Store. Source-only; binary is promoted in App Store Connect.")
echo "PR: $PR_URL"

# --- 3. Wait for required checks, then admin-merge --------------------------
echo "Waiting for required checks (Build + SwiftLint)…"
gh pr checks "$PR_URL" --watch
gh pr merge "$PR_URL" --merge --admin --delete-branch

# --- 4. Tag + GitHub Release on main ----------------------------------------
git checkout main
git pull origin main --quiet
git tag -a "$VTAG" -m "$VTAG (build $N)"
git push origin "$VTAG"
gh release create "$VTAG" --title "$VTAG" --notes "Build $N. Edit these notes with the user-facing changelog."

# --- 5. Back-merge main -> develop (never forget) ---------------------------
git checkout develop
git pull origin develop --quiet
git merge main --no-edit
git push origin develop

cat <<EOF

✅ Source promoted: $VTAG tagged on main, GitHub Release created, main merged back into develop.

📱 Now finish in App Store Connect (the manual part):
   1. My Apps → Dictus → (create / open) the $VERSION App Store version.
   2. Build section → select build $N (already uploaded from TestFlight).
   3. Fill release notes / screenshots / metadata if not done.
   4. Export compliance: ITSAppUsesNonExemptEncryption → already set in Info.plist.
   5. Submit for Review.
   6. Edit the GitHub Release notes ($VTAG) with the user-facing changelog.
EOF
