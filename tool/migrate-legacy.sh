#!/bin/bash
# Migrate a legacy v1 brain DB to the current v1 schema.
#
# The current v1 dropped ruleset/rule/note_meta, axes.description,
# notes.file_mtime/indexed_at, note_source.source_checked_at and five
# write-only meta stamps. `llmemory update` refuses a diverged legacy DB
# (schema-shape gate), so the move is done here:
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

# 0. Precheck, on the live DB, before anything is moved or created. Step 4 runs
#    `sqlite3 -bail` inside one transaction: a table or column this script reads
#    but the legacy DB lacks aborts it *late*, mid-carry-over, with the DB already
#    set aside. Names are cheap to compare up front — so compare them all and
#    report every miss at once, rather than discovering them one abort at a time.
python3 - "$DB" "$ROOT" <<'PY'
import os, re, sqlite3, sys

REQUIRED = {
    "tag_vocab": "tag created_at",
    "tag_aliases": "alias canonical created_at",
    "axes": "axis created_at",
    "note_usage": "note_id hit_count last_retrieved_at created_at",
    "note_source": "note_id source_hash source_stale decl_hash",
    "note_lifecycle_events": "id note_id kind reason created_at",
    "note_links": "src dst kind weight created_at last_activated_at provenance",
    "note_retrieval_terms": "note_id kind term status provenance reject_reason created_at validated_at",
    "entity_index": "entity note_id last_seen_at hit_count",
    "ripple_flags": "note_id flag reason created_at last_flagged_at flag_count resolved_at",
    "candidate_dismissals": "note_id kind dismiss_count word_count section_count generation reason last_dismissed_at",
    "corpus_dismissals": "target_key kind dismiss_count generation reason last_dismissed_at",
    "events": "id ts kind session_id payload",
    "activity_windows": "id started_at ended_at label query_count",
    "retrieval_hits": "id window_id note_id surfaced_at cmd surface_kind used_signal used_at",
    "genome": "gene_id value updated_at",
    "genome_events": "id gene_id old_value new_value cause detail ts",
    "meta": "key value",
}

# Read-only: the write lock is taken in step 1, and the promise printed below is
# "nothing was touched" — opening read-write could checkpoint a leftover WAL into
# the file before the backup exists.
db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
root = sys.argv[2]
present = {row[0] for row in db.execute(
    "SELECT name FROM sqlite_master WHERE type = 'table'")}
missing = []

for table, columns in REQUIRED.items():
    if table not in present:
        missing.append(f"  table {table} — missing entirely")
        continue

    have = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
    absent = [column for column in columns.split() if column not in have]

    if absent:
        missing.append(f"  table {table} — missing column(s): {', '.join(absent)}")

if missing:
    print("this DB cannot be carried over as-is:", file=sys.stderr)
    print("\n".join(missing), file=sys.stderr)
    print("\nnothing was touched. The carry-over reads these columns by name;\n"
          "reconcile the shape (or trim the script) before rerunning.", file=sys.stderr)
    sys.exit(1)

# note_meta retired with no successor table — its rows would vanish silently.
# The values belong in frontmatter now, and step 3 reprojects frontmatter into
# note_extra, so the move has to happen in the *files* before this runs. It cannot
# be done with `set_frontmatter`: the old binary refuses custom keys, and the new
# one writes the file and then dies reprojecting into a note_extra this DB does
# not have yet. So the instruction is a line of markdown, which any editor can add.
KEY_OK = re.compile(r"^[A-Za-z_]\w*$")

if "note_meta" in present:
    rows = list(db.execute(
        "SELECT note_id, namespace, key, value FROM note_meta ORDER BY note_id, namespace, key"))

    if rows and not os.environ.get("ALLOW_NOTE_META_LOSS"):
        paths = dict(db.execute("SELECT id, path FROM notes"))
        # (note, key) is the frontmatter identity; note_meta's is (note, namespace,
        # key). Two namespaces sharing a key on one note would collide into a single
        # line, so those are named, not silently folded into one.
        by_note_key = {}

        for note_id, namespace, key, value in rows:
            by_note_key.setdefault((note_id, key), []).append((namespace, value))

        writable, blocked = [], []

        for note_id, namespace, key, value in rows:
            reason = None

            if len(by_note_key[(note_id, key)]) > 1:
                reason = f"key '{key}' appears under {len(by_note_key[(note_id, key)])} namespaces"
            elif not KEY_OK.match(key):
                reason = f"key '{key}' is not a frontmatter key ([A-Za-z_]\\w*)"
            elif "\n" in value or not value.strip():
                reason = "value is empty or spans lines"
            elif note_id not in paths:
                reason = "no note row — the file it belonged to is gone"

            (blocked if reason else writable).append(
                (note_id, namespace, key, value, reason))

        print(f"note_meta still holds {len(rows)} row(s), and this migration drops the table.",
              file=sys.stderr)
        print("The values live in frontmatter now. Add these lines to the notes"
              " (inside the --- block), then rerun:\n", file=sys.stderr)

        for note_id, namespace, key, value, _ in writable:
            print(f"  {os.path.join(root, paths[note_id])}", file=sys.stderr)
            print(f"      {key}: {value}        # was note_meta {namespace}/{key}",
                  file=sys.stderr)

        if blocked:
            print("\nThese cannot become one frontmatter line as they stand —"
                  " decide each by hand:", file=sys.stderr)

            for note_id, namespace, key, value, reason in blocked:
                print(f"  {note_id} {namespace}/{key} = {value!r} — {reason}", file=sys.stderr)

        print("\nnothing was touched. Rerun once note_meta is empty, or set\n"
              "ALLOW_NOTE_META_LOSS=1 to discard these values on purpose.", file=sys.stderr)
        sys.exit(1)

db.close()
PY

# 1+2. Under llmemory's own write lock (data/.write.lock, flock — taken via
#    python/fcntl since macOS ships no flock(1)): checkpoint the WAL into the
#    main file, take a WAL-safe backup, and set the old file aside. Moving the
#    DB under a live writer would orphan its WAL — the lock refuses that race.
#    The lock is released before init below, which takes it itself; after the
#    mv a concurrent llmemory fails loudly on the missing DB instead of
#    corrupting anything.
python3 - "$ROOT/data/.write.lock" "$DB" "$LEGACY" "$ROOT/data/backup-pre-migrate-$STAMP.db" <<'PY'
import fcntl, os, sqlite3, sys
lock_path, db_path, legacy_path, backup_path = sys.argv[1:5]
lock = open(lock_path, "w")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(f"another llmemory process holds {lock_path} — stop it first")
source = sqlite3.connect(db_path)
source.execute("PRAGMA wal_checkpoint(TRUNCATE)")
backup = sqlite3.connect(backup_path)
with backup:
    source.backup(backup)
backup.close()
source.close()
os.rename(db_path, legacy_path)
for suffix in ("-wal", "-shm"):
    try: os.remove(db_path + suffix)
    except FileNotFoundError: pass
PY

# 3. Fresh canonical DB + markdown reprojection (notes/tags/entities/fts/ref markers).
"$LLMEMORY" init --home "$ROOT"

# 4. Carry the non-projection state over. Ordering respects FKs
#    (vocab before aliases, notes exist before every note_id FK,
#    windows before hits). Projection tables are NOT copied — the
#    reprojection in step 3 is their truth. -bail: one failed statement
#    must roll the whole transaction back, never half-commit.
sqlite3 -bail "$DB" <<SQL
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

-- axes: reprojection creates rows only for axes that still hold notes —
-- carry the empty ones and every original created_at over
INSERT OR IGNORE INTO axes (axis, created_at)
  SELECT axis, created_at FROM old.axes;
UPDATE axes SET created_at = (
  SELECT created_at FROM old.axes WHERE old.axes.axis = axes.axis
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

# 5. Vectors are accepted-loss (derived) — rebuild, then reseed + verify.
"$LLMEMORY" index vector --home "$ROOT"
"$LLMEMORY" update --home "$ROOT"

# 6. Prove the carry-over — old/new row counts side by side. A shortfall is
#    legitimate only for note_id-guarded tables whose notes no longer project.
echo "carried rows (old -> new):"
for t in note_usage note_source note_lifecycle_events note_links note_retrieval_terms \
         entity_index ripple_flags candidate_dismissals corpus_dismissals events \
         activity_windows retrieval_hits genome genome_events tag_vocab tag_aliases; do
  o=$(sqlite3 -bail "$LEGACY" "SELECT COUNT(*) FROM $t")
  n=$(sqlite3 -bail "$DB" "SELECT COUNT(*) FROM $t")
  flag=""; [ "$o" != "$n" ] && flag="  <- CHECK"
  printf '  %-24s %6s -> %-6s%s\n' "$t" "$o" "$n" "$flag"
done

echo "migrated. old DB kept at $LEGACY"
