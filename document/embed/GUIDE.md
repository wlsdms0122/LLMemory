# llmemory

Memory CLI for a self-growing agent. It keeps markdown notes under
`<state-root>/cortex/` in sync with `<state-root>/data/memory.db`
(SQLite + FTS5), providing search, associative exploration, and restructuring.

llmemory is anchor-free — give it the state location with `--home <state-root>`
and it works regardless of where the binary lives. State (the user's knowledge)
lives outside this package.

## First use

```
llmemory init --home <state-root>
```

Creates `data/` and `cortex/` and applies an empty schema. Idempotent —
existing state is preserved.

Two things are planted alongside:
- `<state-root>/README.md` — a derived copy of this document (the manual
  *outside* the brain). Refreshed on every init.
- **Operating-policy notes** — planted as `locked: true` notes at
  `cortex/<axis>/<id>.md` (knowledge *inside* the brain). They are ordinary
  notes, so retrieval descent surfaces them. Seed files that already exist are
  left untouched by init.

To re-plant both into an existing brain after upgrading the binary:

```
llmemory update --home <state-root>
```

Overwrites the seed notes with the binary's copy, refreshes the README, and
reindexes. **Scope is the seed ids only** — authored notes are never touched.
Seeds deleted by a human are restored (a brain without its operating policy is
exactly the failure this command exists to prevent). **Seed ids always carry
the shipped content** — if you need a local fork, duplicate the content into a
note with a new id. `locked` means nothing more than "ops mutations blocked"
(it is not ownership).

## Invocation pattern

```
llmemory <subcommand> [options] --home <state-root>
```

**Important**: `--home` goes after the subcommand. It is a leaf option in
swift-argument-parser — placed earlier it is rejected with
`Unknown option '--home'`.

## Command groups

`--help` is the guide everywhere; every subcommand carries an abstract,
a discussion, and examples. The first surface is always help.

```
llmemory --help                                  # all groups
llmemory query --help                            # group overview
llmemory query search --help                     # options + examples
llmemory ops vocab --home <state-root>           # current op catalog
llmemory ops describe <op> --home <state-root>   # per-op field schema + examples
```

| Group | Role |
|------|------|
| `init` | First-time setup (idempotent) — schema + README + operating-policy seeds |
| `update` | Re-apply seeds and README to an existing brain (authored notes untouched) |
| `query` | Read — search / get / related / neighbors / entity / meta / structure / stats / list / axes / history / lint / enrichment / template |
| `ops` | Write — apply / dry-run (atomic transaction) / vocab / describe |
| `index` | DB maintenance — build / verify (integrity/sources/terms) / vector |
| `consolidate` | Periodic upkeep (separated concerns) — integrate (A, non-destructive) / prune (B, synaptic pruning) / homeostasis (H, metaplasticity tick) / candidates / report |
| `genome` | Plasticity parameters — list (catalog, current values, provenance) / history (mutation log) / shadow (offline reranking of candidate values) |

## Retrieval surfaces — retrieval descent

Read surfaces come in two kinds. **Associative surfaces** (related / search /
neighbors / entity) accompany their output with the information needed to
decide the next hop — a `summary` on every hit, the anchor's neighbors. The
rest (get / list / stats / …) each do only their own job (read a body,
enumerate, observe).

The standard descent loop — repeat until you have reached sufficient knowledge:

```
1. Enter    query related --input '{"text":"<task context>"}' --json   # cue-based association
            (or query search "<keyword>" --json when keywords are clear)
2. Body     query get <id>                                             # read candidates
3. Descend  query neighbors --id <id> --json                           # anchor's neighbors → next hop
4. Repeat   iterate 2–3, judging by the summaries
```

Always parse output with `--json`. Plain output is a table for humans.

**Finding notes related to a conversational context** (the standard entry for
capture/retrieval agents):
```
llmemory query related --input '{"text":"..."}' --json --home <state-root>
```
Input via `--input` or stdin.

**Keyword FTS search**:
```
llmemory query search "transfer" --axis tech --home <state-root>
```

**Reading note bodies** (instead of reading files directly — look up by id,
several at once):
```
llmemory query get principles --home <state-root>
llmemory query get identity principles tone --home <state-root>
```

**Partial reads of long notes** (section-level — use the `section` path from
search/related results as-is):
```
llmemory query get <id> --toc --home <state-root>          # section TOC + word counts
llmemory query get <id> --section '## Section name' --home <state-root>
llmemory query get <id> --budget 800 --home <state-root>   # up to a word budget — when unsure where to open
```
The FTS index is section-level too — search results carry the matched section
path (empty for a head match), and BM25 is normalized by section length so
long multi-topic notes take no length penalty.

`--budget` cuts only at section boundaries (no mid-sentence truncation). When
output is cut, **the cut is made explicit** — every omitted section is listed
with its word count, followed by the exact `--section` command to continue
reading (JSON: `truncated`/`omitted_sections`). A note whose entire body sits
under a single wrapper heading is cut at the wrapper's children; a body with no
headings has no boundary to cut at and comes out whole — that is a note-shape
problem, caught by lint (`note-oversized`).

**Listing notes by condition** (eager/stale etc. — plain is an
axis/id/title/summary table; extract ids in scripts by parsing `--json`):
```
llmemory query list --priority eager --home <state-root>
llmemory query list --axis skill --json --home <state-root>
```
Filters combine with AND: `--priority` / `--axis` / `--stale` /
`--source-stale` / `--limit`.

**Factual edges of fragmentation and promotion**: `split_note` automatically
plants `sibling` edges among the children. Promotion (piece → gist/facet) is
recorded with `link_lineage` — unlike `propose_link` (a decaying associative
proposal), it is a weight-1.0 factual edge exempt from decay. Read direction as
the sentence **`src <kind> dst`** — there is no single "new→old" convention:
an original journal entry is `promoted_to` the extracted note (src = original),
while a replacement note `supersedes` the old one (src = the new note).

Note that **facthood and ranking voice are separated**: `sibling` keeps its
stored weight of 1.0 for family recognition, delete guards, and decay
exemption, but enters the ranking of associative surfaces (related expansion,
neighbors) discounted (`links.sibling_rank_weight`, default 0.3). In an
N-clique every member gets N−1 full-score edges, so siblings flood association
and crowd out the gist — the fact stays, the megaphone is taken away.

```
llmemory ops apply --input '{"ops":[{"op":"link_lineage","src":"<original entry>","dst":"<extracted principle>","kind":"promoted_to","reason":"..."}],"rationale":"..."}' --home <state-root>
```

**Transactional writes**:
```
llmemory ops apply --input '{"ops":[...],"rationale":"..."}' --json --home <state-root>
```
Input via `--input` or stdin (heredoc).

**Periodic upkeep** (LLM 0) — separated by concern. Cadences differ, so call
them separately:
```
llmemory consolidate integrate --home <state-root>   # A: non-destructive upkeep, vector rebuild (frequent; also for recovery)
llmemory consolidate prune --home <state-root>       # B: synaptic pruning — learned-edge decay (rare)
```

## Structured documents (document / template / locked)

Most notes are free-form knowledge, but *documents* (tech specs and the like)
follow a fixed skeleton. The behavior is carried by **two frontmatter fields**
(axis-independent):

- `template: <id>` — this note follows the heading **frame** of that template
  note. Ops mutations that would break the frame (deleting or renaming a
  required section, foreign sections, reordering) are rejected. Content, empty
  sections, and deeper sub-headings are free. Excluded from upkeep candidates
  (split/merge) but searched and ranked like any note.
- `locked: true` — blocks bot-side ops mutations (humans edit the file
  directly). DB-only signals such as `flag` are still allowed. Template notes
  are the canonical case. General-purpose — attach to any note.

```
llmemory query template <template-id> --home <state-root>      # skeleton + per-section guidance
# Creating a document (empty content scaffolds the frame as empty sections):
llmemory ops apply --input '{"ops":[{"op":"create_note","axis":"spec","id":"...","title":"...","summary":"...","tags":["spec"],"template":"<template-id>"}],"rationale":"..."}' --json --home <state-root>
```

Template frame: every declared heading is required (no markers). Declared
levels are closed (foreign sections rejected) and order-preserving; below the
leaves (`###`+) and inside sections everything is free (empty sections OK).
Heading matching is normalized (NFC, lowercase, leading numbers/bullets
stripped). If a human edits the template and the frame changes,
`query lint`'s `template-drift` surfaces the documents now out of line.

## Output / exit codes — level × format, orthogonal

Output is the product of two orthogonal axes. **Level** (how much data) and
**format** (how it is expressed) are independent; at the same level, plain and
`--json` carry **the same data**.

- Level: default = the semantic core (axis/id/title/summary + ranking scores).
  `--verbose` = + metadata (timestamps, path, tags, lifecycle flags, score
  components, candidate details, related's axes/cooccur/vocab sections). The
  level is decided at model-construction time — default-level JSON has no
  detail keys at all. `--verbose` exists only on commands where a level
  difference actually exists (list / search / get / neighbors / related /
  candidates).
- Format: default = a plain table for humans; `--json` = one line of JSON
  (mutating commands: a result summary; query: data). Exceptions:
  `query axes` and `consolidate report` are plain-only.
- Consumers that need detail use `--verbose --json` (the capture/consolidate
  workflows take this form).
- stderr: errors and diagnostics.
- Exit codes: `0` OK, `1` validation failure or result status ≠ ok,
  `2` missing option.

## lint — an observation layer that guides

`query lint` is deterministic observation. **error** = integrity violation
(must fix); **warn** = request for judgment. llmemory does not enforce — even
with rules in place, operation is entirely the agent's, so all it can do is
*broad guidance and guards*: point out "this looks like a problem" and **put
the next hop in your hand**. That is why warn messages carry both the numbers
behind the verdict and the next command (a warning that ends at "too large"
gets re-read every cycle and ignored every cycle).

The rule set that keeps the fragmentation policy (brain
`knowledge-fragmentation`) alive:

| code | What it looks at | Why |
|------|-----------|-----|
| `note-oversized` | Absolute size | The waste of loading a whole note to answer one question |
| `growth-unbounded` | The growth *structure* of accumulating dated sections | Size-independent — it is only a matter of time, and untangling is expensive once it has grown. Notes that already bake the period into their id (sealed buckets) are excluded |
| `fragment-unlinked` | A fragment family with no gist/sibling links | Fragmentation that ended in loss. A split without links is not upkeep. Reported once per family |

> Family recognition is **primarily by connected components of `sibling`
> edges** (facts planted by the tool — the edge is the evidence, so two
> members suffice). Only notes belonging to no component are grouped by name
> stem (a naming-convention oracle — weak, but it is our convention). The
> ordering prevents false positives: members sharing a longer prefix within
> one family are not reinterpreted as a phantom sub-family. Families split by
> the tool get `sibling` planted directly, so they cannot be born isolated.

**Warns can be closed (habituation).** If you reviewed and decided to leave it,
`dismiss_candidate kind="lint:<code>"`. A dismissal is **bound to one
finding** — if a note has several findings of the same code, you must point at
one via the `finding` field (otherwise rejected), and only that one goes quiet
until the note's shape meaningfully diverges or a corpus reshape reopens it.
Closing a whole code would bury the remaining real defects and future ones
too. Dismissals with no live finding are also rejected (prevents silent
no-ops). Without a way to close, the same false positive gets re-tried every
cycle (measured: a cleaner re-examined all 59 dangling-ref findings four
cycles in a row, reaching the same conclusion). To see what is suppressed,
`--include-dismissed`. **Errors cannot be dismissed** — integrity violations
are not a matter of opinion.

**Findings target two kinds of subject (`target_scope`/`subject`).** With
`target_scope=note`, `subject` is a note id and you dismiss by `id` — reopened
by that note's shape diverging (dishabituation) or a corpus reshape. With
`target_scope=corpus`, the finding is a fact owned by no note (e.g. the tag
pair `tag-pair:rates|finance`) and you dismiss by `target` — note shape is no
evidence for a corpus fact, so **only a corpus reshape reopens it**. Back when
both were squeezed into the single note-id slot, corpus warns flowed out with
`note_id:""` — impossible to suppress or dismiss: the catalog advertised
dismissible while the door was shut, exactly the state habituation exists to
prevent.

## Principles

- **Single source of truth**: the markdown in cortex/ is the truth; the DB is
  derived.
- **No whole-body overwrites**: every mutation goes through the op vocabulary
  of `ops apply`. The coarsest unit is `patch_section`.
- **Atomic transactions**: multiple ops are bundled into one transaction —
  validate → snapshot → apply → rollback. On partial failure, cleanup covers
  even newly created files and DB rows.
- **Anchor-free**: takes only `--home`. No assumptions about external paths.
- **Cold is not a cost**: no activity ladder, no "keep but hide" tier — a note
  that is never recalled creates no retrieval cost, so there is no reason to
  hide it. `hit_count`/`last_retrieved_at` are pure observations and **derive
  nothing about a note's lifecycle** (what activation records tune is only the
  genome's read-path parameters below — not notes). The premise of retrieval
  quality is not forgetting but **fragmentation** — don't hide bloated
  knowledge, split it (gist/facet/piece). Disposal is a judgment call via
  `delete_note` (→ `.trash/`).
- **Association carries company**: every hit on an associative surface
  (related/search/neighbors/entity) carries a summary — output is not the
  answer but a waypoint for deciding the next descent.

## Activation records + Genome (the substrate's self-observation and plasticity parameters)

The brain keeps no raw firing log — firing leaves traces in structure and the
signal disappears. By the same principle, raw `events` are discarded after
retention (default 30 days), but **inherited** into persistent traces before
disposal (integrate enforces the order):

- `activity_windows` — an *estimate* of task sessions. With a caller
  correlation id (`--session-id`, `MEMORY_SESSION_ID`) they group under that
  label; without one, by temporal proximity (gap). The estimate stays in the
  type name — it is not a retrieval_session. The gap applies to labels too
  (a closed window never reopens — exactly-once beats label continuity).
- `retrieval_hits` — surfaced (what came to mind) + `used_signal` (weak usage
  signals: reported = caller-declared / content_overlap = response-overlap
  heuristic — not proof of causation). Marking used goes through the
  `mark_used` op, which accepts only notes that appeared in a recent window.

**Genome** — the layer that turns the catalog of plasticity parameters into
data. The *declaration* (gene list, bounds, wild-type, mutability) has code as
its SSoT — species-level, versioned with the binary. Only the *per-brain
current values* (the epigenome) live in the DB; a gene with no row behaves as
wild-type. This is where two brains on the same binary become different brains
down to their parameters.

There are only two write doors:
- **`set_gene` op** — direct value setting. All genes, bounds-validated;
  omitting the value = reset to wild-type. Every change lands in
  genome_events as provenance.
- **`consolidate homeostasis`** — a deterministic metaplasticity tick (LLM 0).
  Mutable (read-path) genes only; reacts only to waste signals in the
  activation records (no distribution aesthetics — an axis firing a lot is
  expertise, not imbalance); adjustments are one step, within bounds, capped
  at wild-type. Windows are consumed exactly once via a watermark and evidence
  accumulates to min_sample, so call frequency is not a hidden parameter.
  Windows predating get-tracking are excluded from evidence (the blind-cohort
  guard — a zero from the uninstrumented era is absence of observation, not
  evidence of waste).

Observation surfaces: `genome list` (catalog, current values, source),
`genome history` (mutation provenance), `genome shadow` (replays the retention
window's search/related logs against the current corpus under candidate
values — offline reranking, not a counterfactual), and the activation section
of `query stats`.

## Semantic enrichment (the retrieval semantic layer)

Adds a *semantic layer* on top of lexical (BM25) and graph. Two branches —
① semantic data an LLM plants at capture time (alias, cue, `assoc` edges),
② algorithmic vectors derived from the graph (`note_vectors`, PPMI+SVD).
Retrieval stays **LLM 0**.

**The boundary** — llmemory is the SSoT for slots, validation, and retrieval;
the outside is a replaceable client that only *produces* LLM artifacts.
Validation lives inside llmemory, so a weak model feeding noise cannot pollute
the index (graceful degradation — the worst case is a no-op).

**Write contracts** (`ops describe <op>`):
- `add_retrieval_terms` — alias/cue text. After round-trip + IDF validation,
  indexed into the `enrich` column of `notes_fts` (fills the blind spots of
  synonyms and Korean particles).
- `propose_link` — an LLM semantic-association edge (`assoc`). Enters at low
  weight; the decay/strengthen loop is itself the validator.
- `purge_enrichment` — retraction by provenance.

**State observation**: `query enrichment` — term active/pending/rejected,
`assoc` edges, vector coverage, per-provenance model noise rates.

**Algorithmic vectors**: `index vector` — factorizes the `note_links` graph
with PPMI+SVD to build `note_vectors` (`index build --rebuild` regenerates it
at the end automatically). `query related` uses `vector_linked` to expand to
semantically close notes that share no keywords. `consolidate integrate`
refactorizes periodically (always re-factorizes when called).

**Schema version**: if the schema the binary expects and the DB's
`user_version` disagree, every command fast-fails. There is no backward
compatibility (no migrations) — delete `data/memory.db` and `init` to
reconstruct from the cortex/ markdown.

> **Caution — deleting the DB is not "reconstruct from cortex", it is
> "discard the semantic layer".** Markdown is the SSoT only for `notes`
> (+tags/entities/source); **the semantic layer and history live only in the
> DB** — assoc/cooccur edges, retrieval terms (alias/cue), `note_meta`, ripple
> flags, candidate dismissals, lifecycle events, hit observations. Delete it
> and they are all gone and do not come back (enrichment has to accumulate
> again over time). If a schema change makes reconstruction unavoidable,
> **copy `memory.db` first**, then after init transplant those tables from
> the copy.

For each op's and command's contracts and validation rules, llmemory's own
surfaces are the SSoT — `ops describe <op>`, `index <cmd> --help`,
`query enrichment`. (No separate design document to depend on.)

## Data layout

```
<state-root>/
  data/
    memory.db         — catalog, FTS5 index, events (30 days) + persistent
                        activation traces (activity_windows/retrieval_hits)
                        + genome (epigenome)
  cortex/
    <axis>/<id>.md    — flat notes (axis-agnostic)
    <axis>/YYYY/MM/<id>.md  — chronological threads (id ends in YYMMDD)
    .innate/          — innate knowledge (axis: innate, locked). If it differs
                        from the shipped copy (edited content, missing file,
                        foreign file), update only warns and touches nothing —
                        only `--override` restores the shipped state. Deleting
                        the whole directory means opting out (skipped).
                        Inspect with `--check`.
    .trash/           — soft-deleted (awaiting human review)
```
