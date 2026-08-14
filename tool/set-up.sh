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
# off its location: `a/b.md` is `a.b`. Every path component must therefore be a
# label, the same shape Paths.idRegex spells in Swift and migrate-legacy.sh in
# python. Checking only for a dot would let `Knowledge_Fragmentation.md` through
# and ship a seed that the brain's own lint calls an invalid id.
#
# The check runs before the generated file is opened for writing. `>` truncates
# on open, so a failure inside the block below leaves a half-written Innate.swift
# behind — a working artifact destroyed by the run that was meant to refresh it.
LABEL='^[a-z0-9][a-z0-9-]*$'
seeds=()

while IFS= read -r file; do
  relative=${file#document/cortex/}

  IFS='/' read -ra labels <<< "${relative%.md}"

  for label in "${labels[@]}"; do
    if [[ ! $label =~ $LABEL ]]; then
      echo "seed path component is not a label ([a-z0-9][a-z0-9-]*): $file" >&2
      exit 1
    fi
  done

  seeds+=("$relative")
done < <(find document/cortex -type f -name '*.md' | LC_ALL=C sort)

# An empty seed set is never intended, and `find` cannot report its own failure
# from inside a process substitution.
if [ ${#seeds[@]} -eq 0 ]; then
  echo "no seed documents under document/cortex/" >&2
  exit 1
fi

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
