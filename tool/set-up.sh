#!/bin/bash
# One-time setup after clone (rerun after editing document/embed/) — like tuist generate.
#
#   document/embed/GUIDE.md  → Sources/LLMemory/Resource/Guide.swift   (agent usage guide)
#   document/embed/innate/*.md  → Sources/LLMemory/Resource/Innate.swift  (innate brain notes)
#
# Resource/ is gitignored — a persistent local artifact like .build. The package does
# not compile without it, so a fresh clone runs this first:
#
#   git clone … && tool/set-up.sh && swift build
#
# Drift between document/embed/ and the generated sources is caught by byte-equality tests.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Sources/LLMemory/Resource

{
  echo "// Generated from document/embed/GUIDE.md by tool/set-up.sh — do not edit by hand."
  echo "// Drift against the markdown is caught by the Guide byte-equality test."
  echo ""
  echo "/// Agent-facing usage guide embedded in the binary. \`init\` copies it to"
  echo "/// \`<state-root>/README.md\` so every brain carries its own manual."
  echo "public enum Guide {"
  echo "    public static let markdown = #\"\"\""
  cat document/embed/GUIDE.md
  echo ""
  echo "\"\"\"#"
  echo "}"
} > Sources/LLMemory/Resource/Guide.swift
echo "generated Sources/LLMemory/Resource/Guide.swift"

{
  echo "// Generated from document/embed/innate/*.md by tool/set-up.sh — do not edit by hand."
  echo "// Drift against the markdown is caught by the Innate byte-equality test."
  echo ""
  echo "/// The knowledge llmemory is born with — what an agent needs to run a memory well"
  echo "/// (how to fragment, how fragments stay reachable). Unlike \`Guide\`, which lands"
  echo "/// outside the cortex as \`<home>/README.md\`, these are planted under"
  echo "/// \`cortex/.innate/\` as ordinary notes so the normal retrieval descent finds them."
  echo "/// They carry \`locked: true\` — the bot cannot mutate them via ops; a human edits"
  echo "/// or deletes the file, and \`update\` refreshes it from this embedded copy."
  echo "public enum Innate {"
  echo "    public struct Seed: Sendable {"
  echo "        public let id: String"
  echo "        public let axis: String"
  echo "        public let markdown: String"
  echo "    }"
  echo ""
  echo "    public static let seeds: [Seed] = ["
  for f in document/embed/innate/*.md; do
    id=$(sed -n 's/^id:[[:space:]]*//p' "$f" | head -1)
    axis=$(sed -n 's/^axis:[[:space:]]*//p' "$f" | head -1)
    if [ -z "$id" ] || [ -z "$axis" ]; then
      echo "setup: $f is missing id: or axis: in frontmatter" >&2
      exit 1
    fi
    echo "        Seed(id: \"$id\", axis: \"$axis\", markdown: #\"\"\""
    cat "$f"
    echo ""
    echo "\"\"\"#),"
  done
  echo "    ]"
  echo "}"
} > Sources/LLMemory/Resource/Innate.swift
echo "generated Sources/LLMemory/Resource/Innate.swift"
