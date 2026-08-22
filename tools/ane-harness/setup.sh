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
# Pinned. `main` is mutable on the Hub, and a report whose whole value is measured
# evidence cannot rest on "whatever that repo held the day it ran". The revision
# is written next to the weights so the benchmark can put it in its own output.
MODEL_REVISION="0977a61d00e39118aab5ed1e510f1d228df5eefd"

# Everything AneBenchRunner loads. A partial or stale download otherwise surfaces
# as a Core ML error three minutes into a device run.
MODEL_FILES=(
    "meta.yaml"
    "config.json"
    "tokenizer.json"
    "tokenizer_config.json"
    "qwen_embeddings.mlmodelc/coremldata.bin"
    "qwen_lm_head_lut6.mlmodelc/coremldata.bin"
    "qwen_FFN_PF_lut6_chunk_01of02.mlmodelc/coremldata.bin"
    "qwen_FFN_PF_lut6_chunk_02of02.mlmodelc/coremldata.bin"
)

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

if [ "$(cat "$DEPS/model/REVISION.txt" 2>/dev/null)" = "$MODEL_REVISION" ]; then
    echo "Model bundle present at $MODEL_REVISION."
else
    echo "Downloading $MODEL_REPO @ ${MODEL_REVISION:0:8} (~1.8 GB)…"
    command -v hf >/dev/null 2>&1 || { echo "error: the 'hf' CLI is required (pip install huggingface_hub)"; exit 1; }
    hf download "$MODEL_REPO" --revision "$MODEL_REVISION" --local-dir "$DEPS/model"
    printf '%s\n' "$MODEL_REVISION" > "$DEPS/model/REVISION.txt"
fi

missing=0
for f in "${MODEL_FILES[@]}"; do
    [ -e "$DEPS/model/$f" ] || { echo "error: missing $f"; missing=1; }
done
[ "$missing" -eq 0 ] || { echo "The model bundle is incomplete. Delete $DEPS/model and re-run."; exit 1; }
echo "Model bundle verified: ${#MODEL_FILES[@]} required paths present."

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
