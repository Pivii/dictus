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
# This edits the SPM CHECKOUT, which is wiped by "Reset Package Caches" / DerivedData
# deletion. Re-run this script after any such reset, then rebuild.
set -euo pipefail

PKG=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path "*/SourcePackages/checkouts/FluidAudio/Package.swift" 2>/dev/null | head -1)

if [ -z "${PKG:-}" ]; then
  echo "FluidAudio checkout not found. Open the project in Xcode (resolve packages) first."
  exit 1
fi

if grep -q "swiftLanguageModes: \[.v5\]" "$PKG"; then
  echo "Already patched: $PKG"
  exit 0
fi

# Insert swiftLanguageModes before cxxLanguageStandard (arg-order requirement).
python3 - "$PKG" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
old = "    ],\n    cxxLanguageStandard: .cxx17\n)"
new = "    ],\n    swiftLanguageModes: [.v5],\n    cxxLanguageStandard: .cxx17\n)"
assert old in t, "anchor not found — FluidAudio Package.swift changed shape; patch manually."
open(p, "w").write(t.replace(old, new))
print("Patched:", p)
PY
