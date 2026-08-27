#!/usr/bin/env bash
# Re-apply the FluidAudio Swift-5-language-mode patch after an SPM cache reset.
#
# WHY: Xcode 26.4.1+/26.5 (Swift 6.x) flag FluidAudio 0.12.x streaming code with
# `sending 'asrManager' risks causing data races` HARD errors (SE-0430 region
# isolation). FluidAudio's fix is 0.12.6, which is incompatible with WhisperKit
# 0.x (swift-transformers 1.1.x ceiling). Until we do the WhisperKit 1.0 +
# FluidAudio 0.12.6 upgrade, we force the FluidAudio package to compile in
# Swift 5 mode, where these errors don't exist. See ADR/ memory:
# project_xcode_pin_fluidaudio.
#
# This edits the SPM CHECKOUT, which is wiped whenever Xcode re-resolves packages
# ("Reset Package Caches", DerivedData deletion — and sometimes Archive). Re-run
# this script after any such reset, then rebuild.
#
# Each build has its own checkout: a build passing `-derivedDataPath` (git
# worktree, CI-style command line) resolves packages under that path, not under
# Xcode's shared location. Patching one says nothing about the other, so the
# path is an argument and a missing checkout is a hard failure (issue #285).
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: patch-fluidaudio-swift5.sh [DERIVED_DATA_PATH]

  DERIVED_DATA_PATH  Derived data directory of the build you are about to run —
                     the same value passed to `xcodebuild -derivedDataPath`.
                     May also be given as the DERIVED_DATA_PATH env variable.
                     Defaults to Xcode's shared location
                     (~/Library/Developer/Xcode/DerivedData), which is what an
                     Xcode GUI build uses.

Examples:
  ./scripts/patch-fluidaudio-swift5.sh                    # Xcode GUI build
  ./scripts/patch-fluidaudio-swift5.sh build/DerivedData  # CI-style build
USAGE
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "error: expected at most one derived data path, got $#." >&2
  usage >&2
  exit 2
fi

# An empty path is not a request for the default: it is `$SOME_VAR` expanding to
# nothing in the caller's command line. Falling back to Xcode's shared location
# there would sweep stale checkouts and exit 0 for a build that asked about its
# own — exactly the silent success this script exists to prevent (issue #285).
# Hence ${DERIVED_DATA_PATH+set}, which tells "unset" from "set to nothing".
if [ "$#" -eq 1 ] && [ -z "$1" ]; then
  echo "error: derived data path is empty (an unset variable in the caller?)." >&2
  usage >&2
  exit 2
fi
if [ "$#" -eq 0 ] && [ -n "${DERIVED_DATA_PATH+set}" ] && [ -z "$DERIVED_DATA_PATH" ]; then
  echo "error: DERIVED_DATA_PATH is set but empty." >&2
  usage >&2
  exit 2
fi

# Explicit mode = the caller named the derived data path of the build it is
# about to run, so the script reports on THAT checkout and nothing else.
# Default mode = no argument and no DERIVED_DATA_PATH, i.e. Xcode's shared
# location, the pre-#285 behaviour.
REQUESTED="${1:-${DERIVED_DATA_PATH:-}}"
if [ -n "$REQUESTED" ]; then
  EXPLICIT=1
  ROOT="$REQUESTED"
else
  EXPLICIT=0
  ROOT="$HOME/Library/Developer/Xcode/DerivedData"
fi

# `find -path "*/SourcePackages/..."` needs a leading path component, and a
# relative root (build/DerivedData) has none — make the root absolute. The
# directory may not exist yet, and that is a failure we want to name precisely,
# so resolve it textually rather than with a tool that requires existence.
case "$ROOT" in
  /*) ;;
  *) ROOT="$PWD/${ROOT#./}" ;;
esac
ROOT="${ROOT%/}"

# Both failure paths below say the same thing: nothing was patched for the build
# you asked about, here is how to get a checkout there.
fail_no_checkout() {
  if [ "$EXPLICIT" -eq 1 ]; then
    echo "Resolve the packages for this build first:" >&2
    echo "  xcodebuild -resolvePackageDependencies -project Dictus.xcodeproj \\" >&2
    echo "    -scheme DictusApp -derivedDataPath $ROOT" >&2
  else
    echo "Open the project in Xcode (resolve packages) first." >&2
  fi
  exit 1
}

if [ ! -d "$ROOT" ]; then
  echo "error: derived data directory does not exist: $ROOT" >&2
  fail_no_checkout
fi

FOUND=0
while IFS= read -r PKG; do
  FOUND=1
  if grep -q "swiftLanguageModes: \[.v5\]" "$PKG"; then
    echo "Already patched: $PKG"
    continue
  fi
  # SPM checkouts can be read-only.
  chmod u+w "$PKG"
  # Insert swiftLanguageModes before cxxLanguageStandard (arg-order requirement).
  python3 - "$PKG" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
old = "    ],\n    cxxLanguageStandard: .cxx17\n)"
new = "    ],\n    swiftLanguageModes: [.v5],\n    cxxLanguageStandard: .cxx17\n)"
assert old in t, "anchor not found - FluidAudio Package.swift changed shape; patch manually."
open(p, "w").write(t.replace(old, new))
print("Patched:", p)
PY
done < <(find "$ROOT" \
  -path "*/SourcePackages/checkouts/FluidAudio/Package.swift" 2>/dev/null)

# The search is confined to $ROOT, so a stale checkout elsewhere on the machine
# can no longer stand in for the one this build compiles.
if [ "$FOUND" -eq 0 ]; then
  echo "error: no FluidAudio checkout found under: $ROOT" >&2
  fail_no_checkout
fi

if [ "$EXPLICIT" -eq 1 ]; then
  echo "FluidAudio checkout patched for the build using: $ROOT"
else
  echo "FluidAudio checkout patched under Xcode's shared derived data: $ROOT"
  echo "note: a build passing -derivedDataPath (worktree, CI-style command line)" \
       "uses its own checkout — re-run with that path to patch it."
fi
