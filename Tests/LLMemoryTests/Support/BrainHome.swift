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
    var session: Session { get }
}

extension BrainHome {
    // MARK: - Public
    var path: String { url.path }

    var storage: GRDBStorage { session.storage }

    // What the services take alongside the store — this home's brain.
    var brain: BrainContext { session.context }

    func database() throws -> any DatabaseWriter {
        try storage.connect()
    }

    func read<T>(_ body: (Database) throws -> T) throws -> T {
        try database().read(body)
    }

    // The production shape — a read scope handed in, never hand-assembled
    // at the call site. Raw `read` stays for SQL probes.
    func readScope<T>(_ body: (GRDBReadScope) throws -> T) throws -> T {
        try database().read { db in try body(GRDBReadScope(db, session.context)) }
    }

    func write<T>(_ body: (Database) throws -> T) throws -> T {
        try storage.writeLock { try database().write(body) }
    }

    var container: Container { Container(storage: storage, brain: brain) }

    // Concrete services, for the tests that drive a scope-taking core
    // directly. The container hands out contracts, and those contracts carry
    // only what a production collaborator calls — so a test that wants the
    // sync core inside an open scope assembles the implementation itself
    // rather than widening the contract until the test fits through it.
    var retrievalService: RetrievalService { RetrievalService(storage: storage, brain: brain, keywords: FrequencyKeywordExtractor(), entities: PatternEntityHinter()) }

    var lintScanner: LintScanner { LintScanner(rules: LintRuleRegistry(), brain: brain) }

    var candidateDetector: CandidateDetector { CandidateDetector(brain: brain) }

    // The tuning a transaction would otherwise have read off the brain — the
    // production values, so a test that does not care about a threshold gets
    // the same one the service would have passed.
    var retrievalTuning: RetrievalTuning { RetrievalTuning(brain.genes) }

    var activationTuning: ActivationTuning { ActivationTuning(brain) }

    var lintTuning: LintTuning { LintTuning(brain.config) }

    var lintService: LintService { LintService(storage: storage, brain: brain, scanner: lintScanner) }

    var genomeService: GenomeService {
        GenomeService(storage: storage, brain: brain, keywords: FrequencyKeywordExtractor(), entities: PatternEntityHinter())
    }

    var notesService: NotesService {
        NotesService(storage: storage, brain: brain, retrieval: retrievalService)
    }

    var consolidateService: ConsolidateService {
        ConsolidateService(storage: storage, brain: brain, keywords: FrequencyKeywordExtractor())
    }

    var operationsEngine: OperationsEngine { OperationsEngine(lint: lintScanner, keywords: FrequencyKeywordExtractor(), brain: brain) }

    @discardableResult
    func apply(_ operations: [[String: Any]], rationale: String = "test") -> OperationsResult {
        OperationsEngine.apply(storage, brain, ["ops": operations, "rationale": rationale])
    }

    @discardableResult
    func apply(_ operation: [String: Any], rationale: String = "test") -> OperationsResult {
        apply([operation], rationale: rationale)
    }

    @discardableResult
    func createNote(
        id: String,
        title: String = "title",
        summary: String = "summary",
        tags: [String]? = nil,
        content: String = "## A\nbody\n",
        fields: [String: Any] = [:]
    ) -> OperationsResult {
        var operation: [String: Any] = [
            "op": "create_note",
            "id": id,
            "title": title,
            "summary": summary,
            // One tag by default so fixtures read the way the corpus does — nothing
            // requires it, so a test that cares passes its own tags.
            "tags": tags ?? ["flow"],
            "content": content
        ]

        for (key, value) in fields { operation[key] = value }

        return apply(operation)
    }

    func indexedPath(of id: String) throws -> URL {
        let known = try read { database in
            try Int.fetchOne(database, sql: "SELECT 1 FROM notes WHERE id = ?", arguments: [id])
        }

        guard known != nil else { throw TestFailure("no indexed path for \(id)") }

        return url.appendingPathComponent(session.context.layout.relativeFile(forId: id))
    }

    func bodyText(of id: String) throws -> String {
        try String(contentsOf: try indexedPath(of: id), encoding: .utf8)
    }

    // Replaces a note's body on disk, keeping its frontmatter and going around the ops layer. Some
    // states — a duplicate heading, say — are exactly what ops refuses to create, and a test about
    // living with such a note has to be able to produce one.
    func overwriteBody(of id: String, with body: String) throws {
        let file = try indexedPath(of: id)
        let (fields, _) = try Frontmatter().parse(try String(contentsOf: file, encoding: .utf8))

        try (Frontmatter().dump(fields) + body).write(to: file, atomically: true, encoding: .utf8)
    }

    // Writes a whole note file directly, then leaves indexing to the caller. Reference markers and
    // entity rows are derived at index time, so a test about them needs the file to exist first.
    @discardableResult
    func writeNoteFile(
        id: String,
        body: String,
        entities: [String] = []
    ) throws -> URL {
        let file = url.appendingPathComponent(session.context.layout.relativeFile(forId: id))

        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let entityLine = entities.isEmpty ? "" : "entities: [\(entities.joined(separator: ", "))]\n"

        try """
        ---
        id: \(id)
        title: title
        priority: lazy
        tags: [flow]
        summary: summary
        \(entityLine)---

        \(body)
        """.write(to: file, atomically: true, encoding: .utf8)

        return file
    }

    // Inserts catalog rows with no file behind them, for tests whose subject is the graph or the
    // ranking over it — there a note only needs to exist as a row.
    func seedBareNotes(ids: [String]) throws {
        try write { database in
            for noteId in ids {
                try database.execute(sql: """
                    INSERT INTO notes (id, title, summary, priority)
                    VALUES (?, ?, '', 'lazy')
                    """, arguments: [noteId, noteId])
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
        try write { database in _ = try ReindexNoteFileTransaction(path: file).perform(database, session.context) }
    }

    func reindexNote(id: String) throws {
        try reindexFile(at: try indexedPath(of: id))
    }

    // MARK: - Private
}
