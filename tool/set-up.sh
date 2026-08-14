#!/bin/bash
# One-time setup after clone (rerun after editing document/) — like tuist generate.
#
#   document/GUIDE.md  → Sources/LLMemory/Resource/Guide.swift   (agent usage guide)
#   document/cortex/**/*.md  → Sources/LLMemory/Resource/Innate.swift  (innate brain notes)
#
# Resource/ is gitignored — a persistent local artifact like .build. The package does
# not compile without it, so a fresh clone runs this first:
#
#   git clone … && tool/set-up.sh && swift build
#
# Drift between document/ and the generated sources is caught by byte-equality tests.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Sources/LLMemory/Resource

{
  echo "// Generated from document/GUIDE.md by tool/set-up.sh — do not edit by hand."
  echo "// Drift against the markdown is caught by the Guide byte-equality test."
  echo ""
  echo "/// Agent-facing usage guide embedded in the binary. \`init\` copies it to"
  echo "/// \`<state-root>/README.md\` so every brain carries its own manual."
  echo "public enum Guide {"
  echo "    public static let markdown = #\"\"\""
  cat document/GUIDE.md
  echo ""
  echo "\"\"\"#"
  echo "}"
} > Sources/LLMemory/Resource/Guide.swift
echo "generated Sources/LLMemory/Resource/Guide.swift"

# document/cortex/ is the shipped subtree of a brain's cortex/, laid out exactly
# as it will be planted — so a seed's id is read the one way every id is read,
# off its location: `a/b.md` is `a.b`. A dot inside a path component would break
# that reading in both directions at once
# (`a/b.c.md` and `a/b/c.md` would spell one address), so the layout is refused
# here, before a generated seed can carry the ambiguity into the binary.
seeds=()
while IFS= read -r file; do
  relative=${file#document/cortex/}

  if [[ "${relative%.md}" == *.* ]]; then
    echo "seed path may not contain '.': $file" >&2
    exit 1
  fi

  seeds+=("$relative")
done < <(find document/cortex -type f -name '*.md' | sed 's|^\./||' | sort)

{
  echo "// Generated from document/cortex/**/*.md by tool/set-up.sh — do not edit by hand."
  echo "// Drift against the markdown is caught by the Innate byte-equality test."
  echo ""
  echo "/// The knowledge llmemory is born with — what an agent needs to run a memory well"
  echo "/// (how to fragment, how fragments stay reachable). Unlike \`Guide\`, which lands"
  echo "/// outside the cortex as \`<home>/README.md\`, these are planted under"
  echo "/// \`cortex/innate/\` as ordinary notes so the normal retrieval descent finds them."
  echo "/// They carry \`locked: true\` — the bot cannot mutate them via ops; a human edits"
  echo "/// or deletes the file, and \`update\` refreshes it from this embedded copy."
  echo "public enum Innate {"
  echo "    public struct Seed: Sendable {"
  echo "        public let id: String"
  echo "        public let markdown: String"
  echo "    }"
  echo ""
  echo "    public static let seeds: [Seed] = ["
  for relative in "${seeds[@]}"; do
    # The location is the address — the same rule the cortex follows, so a seed
    # cannot declare an id that disagrees with where it will be planted.
    id=${relative%.md}
    id=${id//\//.}
    echo "        Seed(id: \"$id\", markdown: #\"\"\""
    cat "document/cortex/$relative"
    echo ""
    echo "\"\"\"#),"
  done
  echo "    ]"
  echo "}"
} > Sources/LLMemory/Resource/Innate.swift
echo "generated Sources/LLMemory/Resource/Innate.swift"
