# Integration

How to install llmemory and wire it into an agent environment. This document
is for the person setting things up; the agent-facing usage guide is
[`embed/GUIDE.md`](embed/GUIDE.md) (planted into every brain as its README).

## 1. Install the binary

```
git clone <repo> && cd llmemory
tool/set-up.sh      # once after clone — embeds document/ into sources
tool/deploy.sh      # → build/llmemory
```

`build/llmemory` is a single self-contained file. Put it wherever suits your
setup — on your `PATH`, or in a project-local `bin/`. llmemory is anchor-free:
the binary's location carries no meaning, and every invocation names its state
location explicitly with `--home`.

## 2. Create a brain

```
llmemory init --home <state-root>
```

`<state-root>` is a directory you choose — typically something like `brain/`
inside the agent's project. Init creates `cortex/` (markdown notes, the source
of truth) and `data/memory.db` (the derived index), plants the innate
operating-policy notes under `cortex/.innate/`, and copies the usage guide to
`<state-root>/README.md`. It is idempotent; existing state is preserved.

Sanity check:

```
llmemory query stats --home <state-root>
```

## 3. Wire it into the agent environment

A brain only works if it is the agent's *single* memory module. Three things
need to hold, whatever harness you use:

1. **Boot** — at session start the agent loads its standing knowledge:
   `llmemory query list --priority eager --json --home <state-root>`, then
   `query get` on the returned ids.
2. **Retrieval before work** — the agent runs the descent loop
   (`query related` → `query get` → `query neighbors`, see GUIDE.md) before
   starting a task, not only when it feels stuck.
3. **Capture routed to brain** — anything worth remembering is written via
   `ops apply`, and the harness's own memory feature (if it has one) is
   pointed away so knowledge does not fork across two stores.

How you express these depends on the harness. The common pattern is a short
instruction block in whatever file the harness injects into every session
(`CLAUDE.md`, `AGENTS.md`, a system prompt, a boot skill) stating the three
rules above and the `--home` path.

### Claude Code

Claude Code has its own auto-memory (a per-project `MEMORY.md` index plus note
files) that it loads and writes on its own initiative. Redirect it by
replacing `MEMORY.md`'s content with a stub:

```markdown
# MEMORY

This project routes all memory through brain (`llmemory --home <state-root>`),
not this harness auto-memory system. Do not write new entries here — capture
in brain instead.
```

If `MEMORY.md` already has content, don't just overwrite it: have the agent
read it, capture what is still valuable into the brain (`ops apply`), and
then replace the file with the stub. Judging which entries are worth keeping
is exactly the kind of work the agent does better than a migration script.

For boot and retrieval, add the three rules to the project's `CLAUDE.md`, or
— if you want boot to be an explicit, versioned procedure — wrap it in a
skill/slash command the session runs on start.

### Codex (and other AGENTS.md-based harnesses)

There is no auto-memory to redirect; add a short section to `AGENTS.md`
stating the three rules and the `--home` path, e.g.:

```markdown
## Memory

All memory goes through `llmemory --home <state-root>`. On session start,
load eager notes (`query list --priority eager`). Before a task, retrieve
context (`query related` → `query get` → `query neighbors`). Capture new
knowledge with `ops apply` — do not keep knowledge in this file.
```

## 4. Periodic maintenance

The deterministic passes (`consolidate integrate` / `prune`, `index build`)
can go straight into cron. The judgment passes — restructuring, in-note
cleaning, semantic enrichment — ship as forge workflows with their prompts
under [`forge/`](forge/); see its README for wiring and scheduling.

## 5. Upgrading the binary

Rebuild (`tool/deploy.sh`), replace the binary, then re-plant the shipped
knowledge into each existing brain:

```
llmemory update --check --home <state-root>   # dry-run: what would change
llmemory update --home <state-root>
```

`update` touches only the shipped seed ids — authored notes are never
touched. If `cortex/.innate/` has drifted from the shipped copy (edited
content, missing files, foreign files), update warns and stops instead of
overwriting; `update --override` restores the shipped state. Deleting the
`.innate/` directory entirely opts the brain out of seeding.
