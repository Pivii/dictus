#!/bin/sh
# upload-testflight.sh — archive, sign and upload the current build to TestFlight.
#
# The step that used to be "Xcode → Product ▸ Archive → upload". This does it
# headless, so a cut can finish without a window opening.
#
# WHY it authenticates with the App Store Connect API key rather than the Xcode
# account (learned the hard way on 2026-09-07):
#
#   Xcode 26 stores its signed-in Apple Account somewhere `xcodebuild` does not
#   read. The CLI still resolves the legacy `IDEProvisioningTeams` preference,
#   finds a stale free-Personal-Team entry with no keychain token, and exits with
#
#       DVTDeveloperAccountManager: Failed to load credentials for <old-account>:
#         missing Xcode-Token
#       error: exportArchive No Accounts
#       error: exportArchive No signing certificate "iOS Distribution" found
#
#   …while Xcode's own Settings ▸ Apple Accounts shows the right account, signed
#   in and healthy. Nothing is broken; the two just read different stores. Adding
#   the account again does not help, because the CLI never looks there.
#
#   Passing the API key bypasses the account system entirely: xcodebuild talks to
#   App Store Connect directly, creates the distribution certificate and the App
#   Store profiles it needs, and signs. It also makes this reproducible on a
#   machine that has never opened Xcode.
#
# Prerequisites:
#   - `asc` installed and authenticated (`asc auth doctor` all green).
#   - The API key's .p8 readable at $ASC_KEY_PATH below. It must NOT live in
#     ~/Downloads, ~/Desktop or ~/Documents: macOS TCC blocks a terminal from
#     reading those, and the failure looks like "Operation not permitted" on a
#     file `ls` can see perfectly well.
#
# Usage:
#   scripts/upload-testflight.sh          # after scripts/cut-testflight.sh
#
# See docs/VERSIONING.md for where this sits in the release flow.
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"
PB=/usr/libexec/PlistBuddy

ASC_APP_ID="6761262378"
ASC_KEY_ID="JM7UBBWY67"
ASC_ISSUER_ID="10faa72b-f025-4a36-a7f7-ef2ef12ac984"
ASC_KEY_PATH="$HOME/.asc/keys/AuthKey_${ASC_KEY_ID}.p8"

VERSION=$($PB -c "Print :CFBundleShortVersionString" DictusApp/Info.plist)
BUILD=$($PB -c "Print :CFBundleVersion" DictusApp/Info.plist)
STEM="Dictus-${VERSION}-${BUILD}"
ARCHIVE=".asc/artifacts/${STEM}.xcarchive"
IPA=".asc/artifacts/${STEM}.ipa"
DERIVED="build/DerivedData"

# --- Safety gates -----------------------------------------------------------
if [ ! -r "$ASC_KEY_PATH" ]; then
  echo "error: cannot read $ASC_KEY_PATH" >&2
  echo "  The key is also in the system keychain (asc uses it from there), but" >&2
  echo "  xcodebuild needs a file. Copy it out of ~/Downloads with Finder —" >&2
  echo "  a terminal cannot, TCC blocks that folder." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is not clean. Aborting." >&2
  exit 1
fi
if ! git rev-parse -q --verify "refs/tags/build/$BUILD" >/dev/null; then
  echo "error: tag build/$BUILD does not exist. Run scripts/cut-testflight.sh first." >&2
  exit 1
fi

echo "→ version : $VERSION ($BUILD)"
echo "→ commit  : $(git rev-parse --short HEAD)"
echo "→ archive : $ARCHIVE"

# --- 1. Resolve packages, then patch FluidAudio -----------------------------
# The patch has to land after resolution and before the build, or a fresh
# derived data fails to compile FluidAudio (#285).
xcodebuild -resolvePackageDependencies \
  -project Dictus.xcodeproj -scheme DictusApp -derivedDataPath "$DERIVED" >/dev/null
./scripts/patch-fluidaudio-swift5.sh "$DERIVED"

# --- 2. Archive -------------------------------------------------------------
mkdir -p .asc/artifacts
asc xcode archive \
  --project "Dictus.xcodeproj" \
  --scheme "DictusApp" \
  --configuration Release \
  --archive-path "$ARCHIVE" \
  --overwrite \
  --xcodebuild-flag=-destination \
  --xcodebuild-flag=generic/platform=iOS \
  --xcodebuild-flag=-derivedDataPath \
  --xcodebuild-flag="$DERIVED"

# --- 3. Export, signed for the App Store ------------------------------------
asc xcode export \
  --archive-path "$ARCHIVE" \
  --ipa-path "$IPA" \
  --xcodebuild-flag=-allowProvisioningUpdates \
  --xcodebuild-flag=-authenticationKeyPath \
  --xcodebuild-flag="$ASC_KEY_PATH" \
  --xcodebuild-flag=-authenticationKeyID \
  --xcodebuild-flag="$ASC_KEY_ID" \
  --xcodebuild-flag=-authenticationKeyIssuerID \
  --xcodebuild-flag="$ASC_ISSUER_ID"

# --- 4. Refuse to upload a development-signed IPA ---------------------------
# get-task-allow is the bit that separates a development build from a store one,
# and Apple rejects the upload rather than the archive. Cheaper to catch here.
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" "Payload/DictusApp.app/embedded.mobileprovision" -d "$WORK"
security cms -D -i "$WORK/Payload/DictusApp.app/embedded.mobileprovision" > "$WORK/pp.plist"
if ! $PB -c "Print :Entitlements:get-task-allow" "$WORK/pp.plist" 2>/dev/null | grep -q false; then
  echo "error: $IPA is not signed for distribution (get-task-allow is not false)." >&2
  exit 1
fi

# --- 5. Upload and wait for processing --------------------------------------
asc builds upload --app "$ASC_APP_ID" --ipa "$IPA" --wait

echo ""
echo "✅ $VERSION ($BUILD) uploaded and processed."
echo "   Next: What to Test —"
echo "   asc builds test-notes create --app $ASC_APP_ID --latest --locale en-GB --whats-new \"…\""
