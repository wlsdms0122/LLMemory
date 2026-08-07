#!/bin/bash
# Build the release binary into build/.
#
#   tool/deploy.sh   →  build/llmemory
#
# Runs setup first so the embedded documents are current, then builds. What happens
# to the binary afterwards is the consumer's business, not this package's.
set -euo pipefail
cd "$(dirname "$0")/.."

tool/set-up.sh
swift build -c release --product llmemory

mkdir -p build
cp -f "$(swift build -c release --product llmemory --show-bin-path)/llmemory" build/llmemory
echo "deployed build/llmemory"
