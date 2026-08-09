# Brain maintenance via forge

llmemory's periodic upkeep has two layers: the deterministic passes the CLI
runs on its own (`consolidate integrate / prune / homeostasis`, `index build`)
and the passes that need judgment — deciding what to merge, what is still
true, what to link. The judgment passes are LLM work, and this directory
ships them as forge workflows (forge is the LLM invocation daemon used
alongside llmemory) so they can run on a schedule instead of depending on
someone remembering.

Three loops, deliberately separated (each owns one concern and stays out of
the others' jurisdiction — the prompts enforce the boundaries):

| Workflow | Sleep metaphor | Looks at | Does |
|----------|----------------|----------|------|
| `consolidate` | replay | structure **between** notes | merge / split / promote, drift-flag review, eager hygiene; then runs `prune` + `homeostasis` |
| `cleaner` | glymphatic wash | **inside** notes | fixes false memories against measured reality, rebases changed sources, splits bloat, sweeps clutter |
| `enrich` | elaboration | the **semantic layer** | plants assoc links and retrieval terms; never touches bodies |

Cadences differ by design: enrich can run often (it is self-limiting),
cleaner regularly, consolidate less often (it is the only loop that runs
`prune`, and running prune from several loops makes the decay clock tick too
fast).

## Layout

```
forge/
  workflow/   consolidate.yaml  cleaner.yaml  enrich.yaml
  prompt/     consolidate.md    cleaner.md    enrich.md
```

Each workflow gathers deterministic context with shell steps (candidates,
axes, lint signals), hands it to one agent step driven by the matching
prompt, and finishes with the deterministic CLI passes. Failure semantics
matter in the shell steps — see the comments in `cleaner.yaml` about
fallbacks that must announce failure rather than masquerade as "all clear".

## Wiring

These are anchor-free like the binary: every llmemory call takes
`--home ${inputs.home}`, so one catalog serves any number of brains.

1. Copy (or symlink) into your forge catalog:
   - `workflow/*.yaml` → `<catalog>/workflow/llmemory/`
   - `prompt/*.md` → `<catalog>/resource/prompt/llmemory/`

   The prompt path matters: the workflows reference
   `${@resource(prompt/llmemory/<name>.md, ...)}`, resolved relative to the
   catalog's resource directory. If you place the prompts elsewhere, update
   the references.
2. Make sure `llmemory` is resolvable on the PATH of the daemon's
   subprocesses (or edit the shell steps to use an absolute path).
3. Dispatch:

   ```
   forge workflow dispatch cleaner --inputs '{"home":"/abs/path/to/brain"}'
   ```

   Inputs: `home` (required, absolute state-root) and `model` (optional,
   default `claude:opus`).
4. Schedule, e.g.:

   ```
   forge schedule create --every 1d cleaner --inputs '{"home":"/abs/path/to/brain"}'
   ```

## Adapting

These are reference implementations — the contracts they rely on
(`consolidate candidates`, `query lint`, `ops apply`, and each op's schema)
are llmemory's own surfaces, so the specs and prompts transfer to any
orchestrator that can run shell steps and an agent step. What is worth
keeping whatever you change:

- **One loop, one jurisdiction.** The boundaries in the prompts (cleaner
  never merges, enrich never edits bodies, only consolidate prunes) are what
  keep three concurrent-ish loops from fighting.
- **Per-cycle caps** in the cleaner prompt — a judgment loop with write
  access needs a mass-destruction guard.
- **Fail-loud fallbacks** on the deterministic steps, as above.
- Judgment ops flow through `ops apply`, so a weak model's noise is bounded
  by llmemory's own validation — the worst case is a rejected transaction.
