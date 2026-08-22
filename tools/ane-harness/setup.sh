#!/bin/bash
# tools/ane-harness/setup.sh
#
# THROWAWAY — #268 D2. Fetches everything the ANE harness needs and that this
# repository deliberately does not carry: the ANEMLL Swift runtime (a git
# checkout, because its Package.swift is not at its repository root and SPM
# cannot address a subdirectory of a remote) and the converted Core ML model
# (1.8 GB of weights).
#
# Both land in .deps/, which is gitignored. Run this once per worktree before
# building anything under tools/ane-harness.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS="$HERE/.deps"

# Pinned so the measurement is reproducible. 0.3.5 beta, the release whose
# conversion pipeline produced the model bundle below.
ANEMLL_REPO="https://github.com/Anemll/Anemll.git"
ANEMLL_SHA="fb42f60b2e7a7b4709052c7146d37480bf21941e"

# ANEMLL's own pre-converted Qwen3-1.7B for the ANE: 2048-token context (the
# shipping French polish prompt is ~1,700), batch 64, LUT6 on the FFN and LM
# head, FP16 embeddings. Its meta.yaml records the exact conversion parameters.
MODEL_REPO="anemll/anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5"

mkdir -p "$DEPS"

if [ -d "$DEPS/Anemll/.git" ]; then
    echo "ANEMLL checkout present."
else
    echo "Cloning ANEMLL…"
    git clone --quiet "$ANEMLL_REPO" "$DEPS/Anemll"
fi
git -C "$DEPS/Anemll" fetch --quiet origin "$ANEMLL_SHA" 2>/dev/null || git -C "$DEPS/Anemll" fetch --quiet origin
git -C "$DEPS/Anemll" checkout --quiet --detach "$ANEMLL_SHA"
echo "ANEMLL at $(git -C "$DEPS/Anemll" rev-parse --short HEAD)"

if [ -f "$DEPS/model/meta.yaml" ]; then
    echo "Model bundle present."
else
    echo "Downloading $MODEL_REPO (~1.8 GB)…"
    command -v hf >/dev/null 2>&1 || { echo "error: the 'hf' CLI is required (pip install huggingface_hub)"; exit 1; }
    hf download "$MODEL_REPO" --local-dir "$DEPS/model"
fi

# The harness builds the prompt from DictusCore at runtime, but the raw fixture
# text lives in the polish-harness resource bundle, which another target cannot
# reach. Copy it in rather than transcribing it: a hand copy is a second source
# of truth that drifts, and this measurement is only worth anything if the
# prompt is byte-identical to the shipping one.
mkdir -p "$HERE/AneBenchKit/Sources/AneBenchKit/Resources"
cp "$HERE/../../DictusCore/Sources/polish-harness/fixtures/seed.json" \
   "$HERE/AneBenchKit/Sources/AneBenchKit/Resources/seed.json"
echo "Copied seed.json fixtures."

echo
echo "Ready. Next:"
echo "  cd $HERE/AneBenchKit && swift run -c release ane-bench   # Mac gate: loads, ANE, sane French"
echo "  cd $HERE && xcodegen                                     # iOS harness, see README.md"
