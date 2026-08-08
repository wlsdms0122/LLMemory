//
//  BrainHome.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
@testable import LLMemory

// A state root a test can write notes into. Ops always land in whichever home is currently bound, so
// this is deliberately a contract about location rather than about a connection.
protocol BrainHome {
    var url: URL { get }
    // One clock reading per home, so everything a test writes shares a timestamp.
    var now: Int { get }
}

extension BrainHome {
    // MARK: - Public
    var path: String { url.path }

    func database() throws -> any DatabaseWriter {
        try GRDBStorage.session.connect()
    }

    func read<T>(_ body: (Database) throws -> T) throws -> T {
        try database().read(body)
    }

    func write<T>(_ body: (Database) throws -> T) throws -> T {
        try GRDBStorage.session.writeLock { try database().write(body) }
    }

    @discardableResult
    func apply(_ operations: [[String: Any]], rationale: String = "test") -> Transaction.Result {
        Transaction.apply(["ops": operations, "rationale": rationale])
    }

    @discardableResult
    func apply(_ operation: [String: Any], rationale: String = "test") -> Transaction.Result {
        apply([operation], rationale: rationale)
    }

    @discardableResult
    func createNote(
        id: String,
        axis: String = "flow",
        title: String = "title",
        summary: String = "summary",
        tags: [String]? = nil,
        content: String = "## A\nbody\n",
        fields: [String: Any] = [:]
    ) -> Transaction.Result {
        var operation: [String: Any] = [
            "op": "create_note",
            "id": id,
            "axis": axis,
            "title": title,
            "summary": summary,
            // The axis must appear in the tags, so defaulting to it keeps the two from drifting apart
            // at a call site that only meant to change the axis.
            "tags": tags ?? [axis],
            // Homes start with zero axes, so any axis a test names is brand new and create_note
            // demands a description. Harmless when the axis already exists.
            "axis_description": "(test axis)",
            "content": content
        ]

        for (key, value) in fields { operation[key] = value }

        return apply(operation)
    }

    func indexedPath(of id: String) throws -> URL {
        let relativePath = try read { database in
            try String.fetchOne(database, sql: "SELECT path FROM notes WHERE id = ?", arguments: [id])
        }

        guard let relativePath else { throw TestFailure("no indexed path for \(id)") }

        return url.appendingPathComponent(relativePath)
    }

    func bodyText(of id: String) throws -> String {
        try String(contentsOf: try indexedPath(of: id), encoding: .utf8)
    }

    // Replaces a note's body on disk, keeping its frontmatter and going around the ops layer. Some
    // states — a duplicate heading, say — are exactly what ops refuses to create, and a test about
    // living with such a note has to be able to produce one.
    func overwriteBody(of id: String, with body: String) throws {
        let file = try indexedPath(of: id)
        let (fields, _) = try Frontmatter.parse(try String(contentsOf: file, encoding: .utf8))

        try (Frontmatter.dump(fields) + body).write(to: file, atomically: true, encoding: .utf8)
    }

    // Writes a whole note file directly, then leaves indexing to the caller. Reference markers and
    // entity rows are derived at index time, so a test about them needs the file to exist first.
    @discardableResult
    func writeNoteFile(
        id: String,
        axis: String = "flow",
        body: String,
        entities: [String] = []
    ) throws -> URL {
        let directory = url.appendingPathComponent("cortex/\(axis)")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appendingPathComponent("\(id).md")
        let entityLine = entities.isEmpty ? "" : "entities: [\(entities.joined(separator: ", "))]\n"

        try """
        ---
        id: \(id)
        title: title
        axis: \(axis)
        priority: lazy
        tags: [\(axis)]
        summary: summary
        \(entityLine)---

        \(body)
        """.write(to: file, atomically: true, encoding: .utf8)

        return file
    }

    // Inserts catalog rows with no file behind them, for tests whose subject is the graph or the
    // ranking over it — there a note only needs to exist as a row.
    func seedBareNotes(ids: [String], axis: String = "flow") throws {
        try write { database in
            try database.execute(
                sql: "INSERT OR IGNORE INTO axes (axis, description, created_at) VALUES (?, ?, ?)",
                arguments: [axis, axis, now]
            )

            for noteId in ids {
                try database.execute(sql: """
                    INSERT INTO notes (id, axis, path, title, summary, priority, file_mtime, indexed_at)
                    VALUES (?, ?, ?, ?, '', 'lazy', ?, ?)
                    """, arguments: [noteId, axis, "tmp/\(noteId).md", noteId, now, now])
            }
        }
    }

    func linkNotes(_ source: String, _ destination: String, kind: String, weight: Double = 1.0) throws {
        try write { database in
            try database.execute(sql: """
                INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [source, destination, kind, weight, now, now])
        }
    }

    func reindexFile(at file: URL) throws {
        try write { database in _ = try Notes.reindexFile(database, path: file) }
    }

    func reindexNote(id: String) throws {
        try reindexFile(at: try indexedPath(of: id))
    }

    // MARK: - Private
}
