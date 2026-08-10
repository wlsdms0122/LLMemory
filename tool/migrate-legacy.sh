#!/bin/bash
# Migrate a legacy v1 brain DB to the current v1 schema.
#
# The current v1 dropped ruleset/rule/note_meta, notes.file_mtime/indexed_at,
# note_source.source_checked_at and five write-only meta stamps. `llmemory update`
# refuses a diverged legacy DB (schema-shape gate), so the move is done here:
# a fresh canonical DB is created by `llmemory init` (markdown reprojection),
# then every non-projection table — the semantic layer and history that exist
# only in the DB — is carried over from the old file.
#
#   tool/migrate-legacy.sh <state-root> [path-to-llmemory]
#
# Idempotent per run: the old DB is preserved as data/memory.legacy-<ts>.db and
# a .backup copy is taken before anything moves.
set -euo pipefail

ROOT="${1:?usage: migrate-legacy.sh <state-root> [path-to-llmemory]}"
LLMEMORY="${2:-llmemory}"
DB="$ROOT/data/memory.db"
STAMP="$(date +%Y%m%d-%H%M%S)"
LEGACY="$ROOT/data/memory.legacy-$STAMP.db"

[ -f "$DB" ] || { echo "no DB at $DB" >&2; exit 1; }
command -v sqlite3 >/dev/null || { echo "sqlite3 required" >&2; exit 1; }

# 1. WAL-safe backup, then set the old file aside.
sqlite3 "$DB" ".backup '$ROOT/data/backup-pre-migrate-$STAMP.db'"
mv "$DB" "$LEGACY"
rm -f "$DB-wal" "$DB-shm"

# 2. Fresh canonical DB + markdown reprojection (notes/tags/entities/fts/ref markers).
"$LLMEMORY" init --home "$ROOT"

# 3. Carry the non-projection state over. Ordering respects FKs
#    (vocab before aliases, notes exist before every note_id FK,
#    windows before hits). Projection tables are NOT copied — the
#    reprojection in step 2 is their truth.
sqlite3 "$DB" <<SQL
ATTACH DATABASE '$LEGACY' AS old;
PRAGMA foreign_keys = ON;
BEGIN;

-- vocabulary: preserve created_at and authored aliases (no REPLACE — a vocab
-- delete would trip the tags(tag) RESTRICT FK)
INSERT OR IGNORE INTO tag_vocab (tag, created_at)
  SELECT tag, created_at FROM old.tag_vocab;
UPDATE tag_vocab SET created_at = (
  SELECT created_at FROM old.tag_vocab WHERE old.tag_vocab.tag = tag_vocab.tag
) WHERE tag IN (SELECT tag FROM old.tag_vocab);
INSERT OR REPLACE INTO tag_aliases (alias, canonical, created_at)
  SELECT alias, canonical, created_at FROM old.tag_aliases;

-- axes: reprojection creates bare rows — restore descriptions and empty axes
INSERT OR IGNORE INTO axes (axis, description, created_at)
  SELECT axis, description, created_at FROM old.axes;
UPDATE axes SET description = (
  SELECT description FROM old.axes WHERE old.axes.axis = axes.axis
) WHERE axis IN (SELECT axis FROM old.axes);

-- engram dynamics
INSERT OR REPLACE INTO note_usage (note_id, hit_count, last_retrieved_at, created_at)
  SELECT note_id, hit_count, last_retrieved_at, created_at FROM old.note_usage
  WHERE note_id IN (SELECT id FROM notes);

-- source drift observations (source_checked_at is gone on purpose)
INSERT OR REPLACE INTO note_source (note_id, source_hash, source_stale, decl_hash)
  SELECT note_id, source_hash, source_stale, decl_hash FROM old.note_source
  WHERE note_id IN (SELECT id FROM notes);

-- lifecycle history
INSERT INTO note_lifecycle_events (note_id, kind, reason, created_at)
  SELECT note_id, kind, reason, created_at FROM old.note_lifecycle_events
  WHERE note_id IN (SELECT id FROM notes)
  ORDER BY id;

-- learned graph (reference/cooccur edges are reprojected too, but weights and
-- activation history live only here — replace wholesale where both ends exist)
INSERT OR REPLACE INTO note_links (src, dst, kind, weight, created_at, last_activated_at, provenance)
  SELECT src, dst, kind, weight, created_at, last_activated_at, provenance FROM old.note_links
  WHERE src IN (SELECT id FROM notes) AND dst IN (SELECT id FROM notes);

-- retrieval terms (alias/cue)
INSERT OR REPLACE INTO note_retrieval_terms
  (note_id, kind, term, status, provenance, reject_reason, created_at, validated_at)
  SELECT note_id, kind, term, status, provenance, reject_reason, created_at, validated_at
  FROM old.note_retrieval_terms
  WHERE note_id IN (SELECT id FROM notes);

-- entity recall counts (rows for reprojected entities get their history back)
INSERT OR REPLACE INTO entity_index (entity, note_id, last_seen_at, hit_count)
  SELECT entity, note_id, last_seen_at, hit_count FROM old.entity_index
  WHERE note_id IN (SELECT id FROM notes);

-- drift queue + habituation
INSERT OR REPLACE INTO ripple_flags
  (note_id, flag, reason, created_at, last_flagged_at, flag_count, resolved_at)
  SELECT note_id, flag, reason, created_at, last_flagged_at, flag_count, resolved_at
  FROM old.ripple_flags WHERE note_id IN (SELECT id FROM notes);
INSERT OR REPLACE INTO candidate_dismissals
  (note_id, kind, dismiss_count, word_count, section_count, generation, reason, last_dismissed_at)
  SELECT note_id, kind, dismiss_count, word_count, section_count, generation, reason, last_dismissed_at
  FROM old.candidate_dismissals WHERE note_id IN (SELECT id FROM notes);
INSERT OR REPLACE INTO corpus_dismissals
  (target_key, kind, dismiss_count, generation, reason, last_dismissed_at)
  SELECT target_key, kind, dismiss_count, generation, reason, last_dismissed_at
  FROM old.corpus_dismissals;

-- event trace + activation substrate (ids preserved: retrieval_hits FK windows)
INSERT INTO events (id, ts, kind, session_id, payload)
  SELECT id, ts, kind, session_id, payload FROM old.events ORDER BY id;
INSERT INTO activity_windows (id, started_at, ended_at, label, query_count)
  SELECT id, started_at, ended_at, label, query_count FROM old.activity_windows ORDER BY id;
INSERT INTO retrieval_hits (id, window_id, note_id, surfaced_at, cmd, surface_kind, used_signal, used_at)
  SELECT id, window_id, note_id, surfaced_at, cmd, surface_kind, used_signal, used_at
  FROM old.retrieval_hits ORDER BY id;

-- epigenome
INSERT OR REPLACE INTO genome (gene_id, value, updated_at)
  SELECT gene_id, value, updated_at FROM old.genome;
INSERT INTO genome_events (id, gene_id, old_value, new_value, cause, detail, ts)
  SELECT id, gene_id, old_value, new_value, cause, detail, ts FROM old.genome_events ORDER BY id;

-- KV: everything except the retired write-only stamps
INSERT OR REPLACE INTO meta (key, value)
  SELECT key, value FROM old.meta
  WHERE key NOT IN ('note_count', 'last_build_at',
                    'last_consolidation_at', 'last_consolidation_note_count',
                    'vectors.model');

COMMIT;
DETACH DATABASE old;
SQL

# 4. Vectors are accepted-loss (derived) — rebuild, then reseed + verify.
"$LLMEMORY" index vector --home "$ROOT"
"$LLMEMORY" update --home "$ROOT"

echo "migrated. old DB kept at $LEGACY"
