# llmemory

A memory CLI for self-growing agents. llmemory keeps a *brain* — markdown
notes under `cortex/` — in sync with a SQLite + FTS5 database
(`data/memory.db`), and provides search, associative exploration, and
restructuring over it.

**Usage (the agent guide) lives in [`document/GUIDE.md`](document/GUIDE.md)** —
this README covers the package itself: what it is, the philosophy it is built
on, and the basics of building and deploying it. The GUIDE is embedded in the
binary and copied to `<state-root>/README.md` on `llmemory init` — every brain
carries its own manual. For installing the binary and wiring it into an agent
environment, see [`document/INTEGRATION.md`](document/INTEGRATION.md).

## Philosophy

llmemory is built on a neuroscience foundation — it mimics how a brain holds
and recalls knowledge rather than how a database stores records. The design
principles below all follow from that stance.

**The agent grows; the tool only provides the substrate.** A freshly
initialized brain is almost empty: one axis (`innate`) and the innate
knowledge under `cortex/.innate/`. Axes, tags, notes, and links all come into
being through use. llmemory knows things about *itself* (its operating policy,
its plasticity parameters, its lint rules) and nothing about *the world* — no
domain vocabulary, no seeded taxonomy. Hardcoded world-knowledge would
contradict the tool's own nature.

**Markdown is the truth; the database is derived.** Notes are plain files a
human can read and edit. The DB is an index over them — but note that the
*semantic layer* (association edges, retrieval terms, dismissals, activation
traces) lives only in the DB and is not reconstructible from markdown, so the
DB is disposable only for the note catalog, not for what the brain has
learned. Deleting `data/memory.db` discards that learning.

**Retrieval is association, not lookup.** The primary read surface is a
*descent*: enter with a cue (`query related`), read candidates (`query get`),
follow neighbors (`query neighbors`), repeat. Every hit on an associative
surface carries a summary — output is not the answer but a waypoint for
deciding the next hop.

**Forgetting is not the tool for retrieval quality; fragmentation is.** There
is no activity ladder and no archive tier. A note that is never recalled
creates no retrieval cost, so there is no reason to hide it. Bloated knowledge
is split (gist/facet/piece), not buried. Disposal is always an explicit
judgment (`delete_note` → `.trash/`).

**LLM 0.** Every query and every consolidation pass is algorithmic. LLMs
produce artifacts (captured notes, aliases, proposed links) as replaceable
outside clients; llmemory owns the slots, the validation, and the retrieval.
A weak model feeding noise cannot pollute the index — the worst case is a
no-op.

**Guidance over enforcement.** Operation is entirely the agent's. What the
tool can do is observe deterministically (`query lint`), say "this looks like
a problem" with the numbers behind the verdict, and put the next command in
the agent's hand. Warnings can be dismissed per finding (habituation);
integrity errors cannot.

**Anchor-free.** State location comes only from `--home <state-root>`. The
binary is a single file with its documents embedded — no sidecar resources,
no assumptions about where it or anything else lives.

**Mutation is transactional and never wholesale.** All writes go through the
op vocabulary of `ops apply`; the coarsest unit is `patch_section`. Multiple
ops bundle into one atomic transaction — validate → snapshot → apply →
rollback, with cleanup covering even newly created files and DB rows.

## Setup

Once after cloning (like tuist `generate`):

```
tool/set-up.sh
```

Embeds the markdown under `document/` into
`Sources/LLMemory/Resource/{Guide,Innate}.swift`. `Resource/` is a gitignored
local artifact (same nature as `.build`), so **the package does not compile
without setup.** Re-run it after editing `document/` — drift between the
markdown and the embedded copies is caught fail-loud by byte-equality tests.

## Structure

```
Sources/
  LLMemory/           — core library (Feature: Query/Ops/Index/Consolidate/…, Service, Module)
    Resource/         — set-up.sh artifacts (gitignored): Guide.swift, Innate.swift
  LLMemoryCLI/        — CLI (swift-argument-parser), executable llmemory
Tests/
  LLMemoryTests/      — unit + real-binary CLI integration tests
document/
  GUIDE.md            — agent-facing usage guide (SSoT)
  INTEGRATION.md      — installing and wiring llmemory into an environment
  innate/*.md         — innate knowledge (SSoT) — planted into cortex/.innate/ on init/update
tool/
  set-up.sh           — document/ → Sources/LLMemory/Resource/ embed generation
  deploy.sh           — setup → release build → build/llmemory
```

## Build / test

```
tool/set-up.sh   # once after clone (or after editing document/)
swift build
swift test
```

Dependencies: GRDB (SQLite), swift-argument-parser, Yams. `note_vectors`
(PPMI+SVD) links Accelerate (LAPACK).

## Deploy

```
tool/deploy.sh   # → build/llmemory
```

Runs setup first so the embeds are current, then release-builds. The binary
ships as a single file (no sidecar resources — which is why the guide is
embedded). Where `build/llmemory` goes from there is the consumer's business.

For detailed contracts, each command's `--help` and `ops describe <op>` are
the SSoT.
