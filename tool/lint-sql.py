#!/usr/bin/env python3
"""SQL lint over the package sources.

Three checks that read SQL, not code shape — which is why they are a lint and
not a unit test. Both look at the string that reaches SQLite:

  cut       a LIMIT with no total order returns an arbitrary member of a tie,
            so the same query stops having the same answer.
  predicate a gate predicate spelled out in a query instead of composed from
            Policy drifts from the others one query at a time.
  fts       a second INSERT into notes_fts is a second definition of what an
            index row is.

Neither can be a behavioural test: a wrong WHERE clause raises nothing, it
returns different rows, so there is no red to go green.

    tool/lint-sql.py [--root <package root>]

Exit 0 clean, 1 with findings.
"""

import argparse
import os
import re
import sys

# Columns unique enough to break a tie. Ordering on any of them makes the cut
# reproducible.
TIEBREAK_COLUMNS = {
    "id", "note_id", "rowid", "entity", "tag", "tag_a", "tag_b",
    "term", "key", "axis", "kind", "src", "dst", "path", "alias", "name",
    "other",
}

# The predicates that decide whether a note is visible, decayable or exempt.
GATE_PREDICATES = re.compile(
    r"archived = [01]"
    r"|template IS NULL"
    r"|COALESCE\([A-Za-z]*\.?stale, ?0\) = [01]"
    r"|priority ?(!=|=|<>) ?'(eager|lazy)'"
    r"|priority (NOT )?IN ?\('(eager|lazy)'\)"
    r"|\blocked = [01]"
    r"|NOT EXISTS ?\(SELECT 1 FROM candidate_dismissals"
)

POLICY_OWNER = "Sources/LLMemory/Module/DB/Policy.swift"

FTS_INSERT = "INSERT INTO notes_fts"
FTS_OWNER = "Sources/LLMemory/Module/DB/Transaction/Note/ReindexNoteFTSTransaction.swift"

TRIPLE_QUOTED = re.compile(r'"""(.*?)"""', re.DOTALL)


def swift_files(root):
    for base, _, names in os.walk(os.path.join(root, "Sources")):
        for name in sorted(names):
            if name.endswith(".swift"):
                yield os.path.join(base, name)


def string_literals(text):
    """Every string literal body with the 1-based line it starts on."""
    for match in TRIPLE_QUOTED.finditer(text):
        yield match.group(1), text[: match.start()].count("\n") + 1

    for offset, line in enumerate(text.split("\n")):
        # A line opening or closing a multi-line literal is already covered,
        # and its quotes would otherwise pair up wrongly here.
        if '"""' in line:
            continue

        rest = line

        while True:
            open_at = rest.find('"')

            if open_at < 0:
                break

            after = rest[open_at + 1:]
            close_at = after.find('"')

            if close_at < 0:
                break

            yield after[:close_at], offset + 1
            rest = after[close_at + 1:]


def cuts(body):
    upper = body.upper()

    if "LIMIT" not in upper:
        return False

    if "SELECT" not in upper and "ORDER BY" not in upper:
        return False

    # LIMIT 1 on a unique lookup is a single row by construction, not a cut
    # through a tie.
    without_single = re.sub(r"LIMIT\s+1\b", "", body, flags=re.IGNORECASE)

    return "LIMIT" in without_single.upper()


def order_by_columns(body):
    """Columns of the last ORDER BY, or None when there is no ORDER BY."""
    matches = list(re.finditer(r"ORDER BY", body, re.IGNORECASE))

    if not matches:
        return None

    clause = body[matches[-1].end():]
    limit = re.search(r"LIMIT", clause, re.IGNORECASE)

    if limit:
        clause = clause[: limit.start()]

    columns = []

    for term in clause.split(","):
        head = term.strip().split()

        if not head:
            continue

        columns.append(head[0].split(".")[-1].lower())

    return columns


def snippet(body):
    return " ".join(line.strip() for line in body.splitlines())[:140]


def cut_findings(root):
    findings = []

    for path in swift_files(root):
        with open(path, encoding="utf-8") as handle:
            text = handle.read()

        if "LIMIT" not in text:
            continue

        relative = os.path.relpath(path, root)

        for body, line in string_literals(text):
            if not cuts(body):
                continue

            columns = order_by_columns(body)

            if columns is None:
                findings.append(
                    f"{relative}:{line}  LIMIT cut without ORDER BY  |  {snippet(body)}"
                )
            elif not any(column in TIEBREAK_COLUMNS for column in columns):
                findings.append(
                    f"{relative}:{line}  ORDER BY has no unique tiebreak column "
                    f"({', '.join(columns)})  |  {snippet(body)}"
                )

    return findings


def predicate_findings(root):
    findings = []

    for path in swift_files(root):
        relative = os.path.relpath(path, root)

        if relative == POLICY_OWNER:
            continue

        with open(path, encoding="utf-8") as handle:
            for offset, line in enumerate(handle):
                code = line.split("//")[0]

                # An UPDATE assigns these columns rather than gating on them —
                # that is a write, not a gate.
                if " SET " in code:
                    continue

                if GATE_PREDICATES.search(code):
                    findings.append(f"{relative}:{offset + 1}  {code.strip()}")

    return findings


def fts_findings(root):
    """Only the INSERT — deletes belong to whoever owns the row being removed."""
    findings = []

    for path in swift_files(root):
        relative = os.path.relpath(path, root)

        if relative == FTS_OWNER:
            continue

        with open(path, encoding="utf-8") as handle:
            for offset, line in enumerate(handle):
                if FTS_INSERT in line.split("//")[0]:
                    findings.append(f"{relative}:{offset + 1}  {line.strip()}")

    return findings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."),
    )
    root = os.path.abspath(parser.parse_args().root)

    cut = cut_findings(root)
    predicate = predicate_findings(root)
    fts = fts_findings(root)

    if cut:
        print("LIMIT cut with no total order — the row that survives the cut is")
        print("whichever one SQLite happened to reach first:\n")
        print("\n".join(f"  {finding}" for finding in cut))
        print()

    if predicate:
        print("Raw gate predicate outside Policy — compose Policy atoms instead")
        print("(Policy.surface / decayCandidate / live / fresh / forgetExempt / …):\n")
        print("\n".join(f"  {finding}" for finding in predicate))
        print()

    if fts:
        print("INSERT INTO notes_fts outside ReindexNoteFTSTransaction — a second")
        print("insert is a second definition of what an index row is:\n")
        print("\n".join(f"  {finding}" for finding in fts))
        print()

    if cut or predicate or fts:
        return 1

    print("sql lint: clean")

    return 0


if __name__ == "__main__":
    sys.exit(main())
