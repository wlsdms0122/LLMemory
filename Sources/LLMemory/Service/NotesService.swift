//
//  NotesService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Notes-domain service — body reads (whole, sections, budget, toc, frame),
// enumeration, history, structure, and the note_meta side-table. Body reads
// derive a retrieval record; RetrievalService applies it.
public enum NotesService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func get(
        _ storage: GRDBStorage,
        ids: [String],
        cliSessionId: String = ""
    ) async throws -> (found: [Reads.GetNote], missing: [String]) {
        let sessionId = Env.retrievalSession(cli: cliSessionId)
        let outcome = try await storage.read { scope in
            try get(scope, ids: ids, sessionId: sessionId)
        }

        try await RetrievalService.applyRecord(storage, outcome.record)

        return (outcome.found, outcome.missing)
    }

    public static func getSections(
        _ storage: GRDBStorage,
        id: String,
        sections: [String]
    ) async throws -> (note: Reads.GetNote, slices: [Reads.SectionSlice]) {
        let outcome = try await storage.read { scope in
            try getSections(scope, id: id, sections: sections)
        }

        try await RetrievalService.applyRecord(storage, outcome.record)

        return (outcome.note, outcome.slices)
    }

    public static func getBudget(
        _ storage: GRDBStorage,
        id: String,
        budget: Int
    ) async throws -> (note: Reads.GetNote, cut: Reads.BudgetCut) {
        let outcome = try await storage.read { scope in
            try getBudget(scope, id: id, budget: budget)
        }

        try await RetrievalService.applyRecord(storage, outcome.record)

        return (outcome.note, outcome.cut)
    }

    public static func toc(
        _ storage: GRDBStorage,
        id: String
    ) async throws -> (note: Reads.GetNote, entries: [Reads.TocEntry]) {
        let outcome = try await storage.read { scope in try toc(scope, id: id) }

        try await RetrievalService.applyRecord(storage, outcome.record)

        return (outcome.note, outcome.entries)
    }

    public static func template(
        _ storage: GRDBStorage,
        id: String
    ) async throws -> (note: Reads.GetNote, frame: [Template.FrameNode]) {
        let outcome = try await storage.read { scope in try template(scope, id: id) }

        try await RetrievalService.applyRecord(storage, outcome.record)

        return (outcome.note, outcome.frame)
    }

    public static func list(
        _ storage: GRDBStorage,
        priority: String?,
        axis: String?,
        stale: Bool,
        sourceStale: Bool,
        limit: Int?
    ) async throws -> [Reads.ListRow] {
        let filter = Reads.ListFilter(
            priority: priority,
            axis: axis,
            stale: stale,
            sourceStale: sourceStale,
            limit: limit
        )

        return try await storage.read { scope in try scope.run(ListNoteRowsTransaction(filter)) }
    }

    public static func history(
        _ storage: GRDBStorage,
        noteId: String,
        limit: Int
    ) async throws -> [Reads.HistoryEvent] {
        try await storage.read { scope in
            try scope.run(FetchNoteHistoryTransaction(noteId: noteId, limit: limit))
        }
    }

    public static func listAxes(
        _ storage: GRDBStorage
    ) async throws -> [(axis: String, description: String?, count: Int)] {
        try await storage.read { scope in try scope.run(FetchAxesWithCountsTransaction()) }
    }

    public static func structure(
        _ storage: GRDBStorage,
        axis: String?
    ) async throws -> Reads.StructureResult {
        try await storage.read { scope in try structure(scope, axis: axis) }
    }

    public static func metaById(
        _ storage: GRDBStorage,
        noteId: String,
        namespace: String?
    ) async throws -> [String: [String: String]] {
        try await storage.read { scope in
            try scope.run(FetchNoteMetaTransaction(noteId: noteId, namespace: namespace))
        }
    }

    public static func metaByKV(
        _ storage: GRDBStorage,
        namespace: String,
        key: String,
        value: String?,
        limit: Int
    ) async throws -> [(noteId: String, value: String)] {
        try await storage.read { scope in
            try scope.run(
                FindNoteMetaByKVTransaction(
                    namespace: namespace,
                    key: key,
                    value: value,
                    limit: limit
                )
            )
        }
    }

    // MARK: - Internal
    static func get(
        _ scope: GRDBReadScope,
        ids: [String],
        sessionId: String? = nil
    ) throws -> (found: [Reads.GetNote], missing: [String], record: RetrievalRecord?) {
        let byId = try scope.run(FetchNoteCatalogTransaction(ids: ids))
        var found: [Reads.GetNote] = []
        var missing: [String] = []

        for id in ids {
            guard let record = byId[id] else {
                missing.append(id)
                continue
            }

            let path = Paths.brainRoot.appendingPathComponent(record.path)
            let text = try String(contentsOf: path, encoding: .utf8)
            let (doc, body) = try Frontmatter.parse(text)

            found.append(
                Reads.GetNote(
                    id: id,
                    axis: record.axis,
                    path: record.path,
                    frontmatter: Reads.NoteFrontmatter(doc),
                    body: body,
                    hitCount: record.hitCount,
                    createdAt: record.createdAt,
                    editedAt: record.editedAt,
                    priority: record.priority
                )
            )
        }

        let record: RetrievalRecord? = found.isEmpty ? nil : .init(
            sessionId: sessionId,
            payloadJSON: Events.retrievalPayloadJSON(cmd: "get", payload: [
                ("hit_ids", found.map { note in note.id })
            ])
        )

        return (found, missing, record)
    }

    static func getSections(
        _ scope: GRDBReadScope,
        id: String,
        sections: [String]
    ) throws -> (note: Reads.GetNote, slices: [Reads.SectionSlice], record: RetrievalRecord?) {
        let (found, missing, record) = try get(scope, ids: [id])

        guard let note = found.first else {
            throw NotesError.unknownIds(missing)
        }

        var slices: [Reads.SectionSlice] = []

        for raw in sections {
            let path = try SectionEdit.parsePath(raw)
            let text = try SectionEdit.subtreeText(note.body, path: path)

            slices.append(Reads.SectionSlice(path: path.display(), text: text))
        }

        return (note, slices, record)
    }

    static func getBudget(
        _ scope: GRDBReadScope,
        id: String,
        budget: Int
    ) throws -> (note: Reads.GetNote, record: RetrievalRecord?, cut: Reads.BudgetCut) {
        let (found, missing, record) = try get(scope, ids: [id])

        guard let note = found.first else {
            throw NotesError.unknownIds(missing)
        }

        return (note, record, budgetCut(of: note.body, budget: budget))
    }

    static func toc(
        _ scope: GRDBReadScope,
        id: String
    ) throws -> (note: Reads.GetNote, entries: [Reads.TocEntry], record: RetrievalRecord?) {
        let (found, missing, record) = try get(scope, ids: [id])

        guard let note = found.first else {
            throw NotesError.unknownIds(missing)
        }

        let (_, rows) = SectionEdit.sectionRows(note.body)
        let entries = rows.map { row in
            Reads.TocEntry(path: row.path, words: SectionEdit.wordCount(row.text))
        }

        return (note, entries, record)
    }

    static func template(
        _ scope: GRDBReadScope,
        id: String
    ) throws -> (note: Reads.GetNote, frame: [Template.FrameNode], record: RetrievalRecord?) {
        let (found, missing, record) = try get(scope, ids: [id])

        guard let note = found.first else {
            throw NotesError.unknownIds(missing)
        }

        return (note, Template.parseFrame(note.body), record)
    }

    static func structure(_ scope: GRDBReadScope, axis: String?) throws -> Reads.StructureResult {
        let axes = try scope.run(FetchAxesWithCountsTransaction())
        let distribution = try scope.run(FetchLinkDistributionTransaction())
        var stats: AxisStats? = nil

        if let axis {
            stats = try scope.run(AxisStatsTransaction(axis: axis))
        }

        return Reads.StructureResult(axes: axes, distribution: distribution, axisStats: stats)
    }

    // MARK: - Private
    // The word-budget cut — always lands on a section boundary; a truncation
    // is stated, never silent.
    private static func budgetCut(of body: String, budget: Int) -> Reads.BudgetCut {
        let lines = body.unicodeLines()
        let all = SectionEdit.splitSections(body)
        let totalWords = SectionEdit.wordCount(body)

        func maximal(in range: Range<Int>) -> [SectionEdit.Section] {
            var sections: [SectionEdit.Section] = []
            var cursor = range.lowerBound

            for section in all
            where section.lineStart >= cursor && section.lineEnd <= range.upperBound {
                sections.append(section)
                cursor = section.lineEnd
            }

            return sections
        }

        func heading(_ section: SectionEdit.Section) -> String {
            "\(String(repeating: "#", count: section.level)) \(section.title)"
        }

        var prefix = ""
        var units = maximal(in: 0..<lines.count)

        while units.count == 1, let only = units.first {
            let children = maximal(in: (only.lineStart + 1)..<only.lineEnd)

            if children.isEmpty { break }

            prefix = prefix.isEmpty ? heading(only) : prefix + " > " + heading(only)
            units = children
        }

        let unitPath: (SectionEdit.Section) -> String = { section in
            prefix.isEmpty ? heading(section) : prefix + " > " + heading(section)
        }
        let tops = units.map { section in
            (path: unitPath(section), start: section.lineStart, end: section.lineEnd)
        }

        func linePrefix(of range: Range<Int>, cap: Int) -> Int {
            var words = 0
            var end = range.lowerBound

            for index in range {
                let lineWords = SectionEdit.wordCount(lines[index])

                if end > range.lowerBound && words + lineWords > cap { break }

                words += lineWords
                end = index + 1
            }

            return end
        }

        let headEnd = tops.first?.start ?? lines.count
        let headWords = SectionEdit.wordCount(lines[..<headEnd].joined(separator: "\n"))

        if headWords > budget {
            let cut = linePrefix(of: 0..<headEnd, cap: budget)
            let shown = lines[..<cut].joined(separator: "\n")
            let name = prefix.isEmpty ? "(preamble)" : prefix

            return Reads.BudgetCut(
                shown: shown,
                shownSections: [],
                omitted: tops.map { top in
                    Reads.TocEntry(
                        path: top.path,
                        words: SectionEdit.wordCount(
                            lines[top.start..<top.end].joined(separator: "\n")
                        )
                    )
                },
                truncatedWithin: name,
                shownWords: SectionEdit.wordCount(shown),
                totalWords: totalWords
            )
        }

        var running = headWords
        var shownSections: [Reads.TocEntry] = []
        var omitted: [Reads.TocEntry] = []
        var cutAt: Int? = nil

        for top in tops {
            let words = SectionEdit.wordCount(lines[top.start..<top.end].joined(separator: "\n"))

            if cutAt == nil && running + words <= budget {
                running += words
                shownSections.append(Reads.TocEntry(path: top.path, words: words))
            } else {
                if cutAt == nil { cutAt = top.start }

                omitted.append(Reads.TocEntry(path: top.path, words: words))
            }
        }

        guard let cut = cutAt else {
            return Reads.BudgetCut(
                shown: body,
                shownSections: shownSections,
                omitted: [],
                truncatedWithin: nil,
                shownWords: totalWords,
                totalWords: totalWords
            )
        }

        if shownSections.isEmpty && running == 0, let first = tops.first {
            let end = linePrefix(of: first.start..<first.end, cap: budget)
            let shown = lines[..<end].joined(separator: "\n")

            return Reads.BudgetCut(
                shown: shown,
                shownSections: [],
                omitted: Array(omitted.dropFirst()),
                truncatedWithin: first.path,
                shownWords: SectionEdit.wordCount(shown),
                totalWords: totalWords
            )
        }

        return Reads.BudgetCut(
            shown: lines[..<cut].joined(separator: "\n"),
            shownSections: shownSections,
            omitted: omitted,
            truncatedWithin: nil,
            shownWords: running,
            totalWords: totalWords
        )
    }
}
