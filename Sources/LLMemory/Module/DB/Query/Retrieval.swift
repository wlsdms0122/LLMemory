//
//  Retrieval.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Read-side retrieval mechanisms — pure functions of a reader connection.
// Side effects are never applied here: mechanisms derive them as
// `RecordRetrievalTransaction.Parameter` for the write path to apply.
public enum Retrieval {
    // MARK: - Property
    public static let candidateValidKinds = Candidates.validKinds
    public static let candidateRetrievalKinds = Candidates.retrievalKinds
    public static let candidateStructuralKinds = Candidates.structuralKinds

    // MARK: - Initializer
    // MARK: - Public
    static func search(
        _ queue: any DatabaseReader,
        query: String,
        axis: String?,
        limit: Int,
        expand: Int,
        cliSessionId: String,
        includeStale: Bool,
        excludeAxes: [String],
        raw: Bool
    ) throws -> (rows: [Search.SearchRow], extra: [Links.ExpandedNote], record: RecordRetrievalTransaction.Parameter) {
        try searchNotes(
            queue,
            query: query,
            axis: axis,
            limit: limit,
            expand: expand,
            sessionId: Env.retrievalSession(cli: cliSessionId),
            includeStale: includeStale,
            excludeAxes: excludeAxes.isEmpty ? nil : excludeAxes,
            raw: raw
        )
    }
    
    static func related(
        _ queue: any DatabaseReader,
        text: String,
        kind: String?,
        cliSessionId: String,
        includeBodies: Bool
    ) throws -> (result: Framing.RelatedResult, record: RecordRetrievalTransaction.Parameter) {
        let sessionId = Env.retrievalSession(cli: cliSessionId)
        let snapshot = try Framing.snapshot(
            queue,
            userInput: text,
            agentOutput: "",
            linkKind: kind,
            sessionId: sessionId
        )
        
        var bodies: [String: String] = [:]
        
        if includeBodies {
            for note in snapshot.similar {
                let path = Paths.brainRoot.appendingPathComponent(note.path)
                
                if let body = try? String(contentsOf: path, encoding: .utf8) {
                    bodies[note.id] = body
                }
            }
        }
        
        let record = RecordRetrievalTransaction.Parameter(
            sessionId: sessionId,
            rebirthRanked: relatedRanked(snapshot: snapshot),
            payloadJSON: Events.retrievalPayloadJSON(cmd: "related", payload: [
                ("text", String(text.prefix(200))),
                ("hit_ids", snapshot.similar.map { note in note.id }),
                ("expand_ids", snapshot.linked.map { note in note.id })
            ])
        )
        
        return (Framing.RelatedResult(snapshot: snapshot, bodies: bodies), record)
    }
    
        static func get(
        _ queue: any DatabaseReader,
        ids: [String],
        cliSessionId: String = ""
    ) throws -> (found: [Reads.GetNote], missing: [String], record: RecordRetrievalTransaction.Parameter?) {
        let byId = try queue.read { db in try Reads.catalog(db, ids: ids) }
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
        
        let record: RecordRetrievalTransaction.Parameter? = found.isEmpty ? nil : .init(
            sessionId: Env.retrievalSession(cli: cliSessionId),
            payloadJSON: Events.retrievalPayloadJSON(cmd: "get", payload: [
                ("hit_ids", found.map { note in note.id })
            ])
        )
        
        return (found, missing, record)
    }
    
        static func getSections(
        _ queue: any DatabaseReader,
        id: String,
        sections: [String]
    ) throws -> (note: Reads.GetNote, slices: [Reads.SectionSlice], record: RecordRetrievalTransaction.Parameter?) {
        let (found, missing, record) = try get(queue, ids: [id])
        
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
        _ queue: any DatabaseReader,
        id: String,
        budget: Int
    ) throws -> (note: Reads.GetNote, record: RecordRetrievalTransaction.Parameter?, cut: Reads.BudgetCut) {
        let (found, missing, record) = try get(queue, ids: [id])
        
        guard let note = found.first else {
            throw NotesError.unknownIds(missing)
        }
        
        let body = note.body
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
            
            return (note, record, Reads.BudgetCut(
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
            ))
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
            return (note, record, Reads.BudgetCut(
                shown: body,
                shownSections: shownSections,
                omitted: [],
                truncatedWithin: nil,
                shownWords: totalWords,
                totalWords: totalWords
            ))
        }
        
        if shownSections.isEmpty && running == 0, let first = tops.first {
            let end = linePrefix(of: first.start..<first.end, cap: budget)
            let shown = lines[..<end].joined(separator: "\n")
            
            return (note, record, Reads.BudgetCut(
                shown: shown,
                shownSections: [],
                omitted: Array(omitted.dropFirst()),
                truncatedWithin: first.path,
                shownWords: SectionEdit.wordCount(shown),
                totalWords: totalWords
            ))
        }
        
        return (note, record, Reads.BudgetCut(
            shown: lines[..<cut].joined(separator: "\n"),
            shownSections: shownSections,
            omitted: omitted,
            truncatedWithin: nil,
            shownWords: running,
            totalWords: totalWords
        ))
    }
    
    static func toc(_ queue: any DatabaseReader, id: String) throws -> (note: Reads.GetNote, entries: [Reads.TocEntry], record: RecordRetrievalTransaction.Parameter?) {
        let (found, missing, record) = try get(queue, ids: [id])
        
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
        _ queue: any DatabaseReader,
        id: String
    ) throws -> (note: Reads.GetNote, frame: [Template.FrameNode], record: RecordRetrievalTransaction.Parameter?) {
        let (found, missing, record) = try get(queue, ids: [id])
        
        guard let note = found.first else {
            throw NotesError.unknownIds(missing)
        }
        
        return (note, Template.parseFrame(note.body), record)
    }
    
    static func metaById(
        _ queue: any DatabaseReader,
        noteId: String,
        namespace: String?
    ) throws -> [String: [String: String]] {
        return try queue.read { db in
            try NoteMeta.getAll(db, noteId: noteId, namespace: namespace)
        }
    }
    
    static func metaByKV(
        _ queue: any DatabaseReader,
        namespace: String,
        key: String,
        value: String?,
        limit: Int
    ) throws -> [(noteId: String, value: String)] {
        return try queue.read { db in
            try NoteMeta.findByKV(
                db,
                namespace: namespace,
                key: key,
                value: value,
                limit: limit
            )
        }
    }
    
    static func entity(_ queue: any DatabaseReader, name: String?, limit: Int) throws -> [Reads.EntityHit] {
        return try queue.read { db in try Reads.entityLookup(db, name: name, limit: limit) }
    }
    
    static func listAxes(_ queue: any DatabaseReader) throws -> [(axis: String, description: String?, count: Int)] {
        try axesWithCounts(queue)
    }
    
    static func structure(_ queue: any DatabaseReader, axis: String?) throws -> Reads.StructureResult {
                let axes = try axesWithCounts(queue)
        let distribution = try Links.distribution(queue)
        var stats: Stats.AxisStats? = nil
        
        if let axis {
            stats = try queue.read { db in try Stats.axisStats(db, axis: axis) }
        }
        
        return Reads.StructureResult(axes: axes, distribution: distribution, axisStats: stats)
    }
    
    static func neighbors(
        _ queue: any DatabaseReader,
        id: String,
        k: Int,
        cliSessionId: String = ""
    ) throws -> (scores: [Candidates.NeighborScore], record: RecordRetrievalTransaction.Parameter?) {
        let scores = try queue.read { db in try Candidates.neighbors(db, noteId: id, k: k) }
        let record: RecordRetrievalTransaction.Parameter? = scores.isEmpty ? nil : .init(
            sessionId: Env.retrievalSession(cli: cliSessionId),
            payloadJSON: Events.retrievalPayloadJSON(cmd: "neighbors", payload: [
                ("anchor", id),
                ("hit_ids", scores.map { score in score.id })
            ])
        )
        
        return (scores, record)
    }
    
        static func noteStats(_ queue: any DatabaseReader, id: String) throws -> Stats.NoteStats? {
        return try queue.read { db in try Stats.noteStats(db, nid: id) }
    }
    
    static func axisStats(_ queue: any DatabaseReader, axis: String) throws -> Stats.AxisStats {
        return try queue.read { db in try Stats.axisStats(db, axis: axis) }
    }
    
    static func overallStats(_ queue: any DatabaseReader) throws -> Stats.OverallStats {
        return try queue.read { db in try Stats.overall(db) }
    }
    
    static func list(
        _ queue: any DatabaseReader,
        priority: String?,
        axis: String?,
        stale: Bool,
        sourceStale: Bool,
        limit: Int?
    ) throws -> [Reads.ListRow] {
                let filter = Reads.ListFilter(
            priority: priority,
            axis: axis,
            stale: stale,
            sourceStale: sourceStale,
            limit: limit
        )
        
        return try queue.read { db in try Reads.list(db, filter) }
    }
    
    static func history(
        _ queue: any DatabaseReader,
        noteId: String,
        limit: Int
    ) throws -> [Reads.HistoryEvent] {
        return try queue.read { db in try Reads.history(db, noteId: noteId, limit: limit) }
    }
    
    static func lint(
        _ queue: any DatabaseReader,
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) throws -> [Lint.Issue] {
        return try queue.read { db in
            var issues = try id != nil ? Lint.lintNote(db, nid: id!) : Lint.lintAll(db)
            
            if !includeDismissed {
                issues = try Lint.suppressDismissed(db, issues)
            }
            
            if let code { issues = issues.filter { issue in issue.code == code } }
            
            if let severity { issues = issues.filter { issue in issue.severity == severity } }
            
            issues.sort { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity == "error" }
                
                if lhs.target != rhs.target {
                    if lhs.target.scope != rhs.target.scope {
                        return lhs.target.scope < rhs.target.scope
                    }
                    
                    return lhs.target.subject < rhs.target.subject
                }
                
                if lhs.code != rhs.code { return lhs.code < rhs.code }
                
                return lhs.message < rhs.message
            }
            
            if let limit, issues.count > limit { issues = Array(issues.prefix(limit)) }
            
            return issues
        }
    }
    
    static func enrichment(_ queue: any DatabaseReader) throws -> EnrichmentReview.Status {
        return try queue.read { db in try EnrichmentReview.status(db) }
    }
    
    static func candidates(
        _ queue: any DatabaseReader,
        kinds: [String],
        limit: Int
    ) throws -> [String: Candidates.Batch] {
        return try queue.read { db in
            var batches: [String: Candidates.Batch] = [:]
            
            for kind in kinds { batches[kind] = try batchForKind(db, kind, limit: limit) }
            
            return batches
        }
    }
    
    static func searchNotes(
        _ queue: any DatabaseReader,
        query: String,
        axis: String? = nil,
        limit: Int = 5,
        expand: Int = 0,
        sessionId: String? = nil,
        includeStale: Bool = false,
        excludeAxes: [String]? = nil,
        sinceTs: Int? = nil,
        raw: Bool = false
    ) throws -> (rows: [Search.SearchRow], extra: [Links.ExpandedNote], record: RecordRetrievalTransaction.Parameter) {
        let rows: [Search.SearchRow] = try queue.read { db in
            try Search.fts(
                db,
                query: query,
                axis: axis,
                limit: limit,
                includeStale: includeStale,
                excludeAxes: excludeAxes,
                sinceTs: sinceTs,
                sessionId: sessionId,
                raw: raw
            )
        }
        var extra: [Links.ExpandedNote] = []
        
        if expand > 0 {
            extra = (try? Links.expand(
                queue,
                noteIds: rows.map { row in row.id },
                hops: 1,
                limit: expand
            )) ?? []
        }
        
        let hitIds = rows.map { row in row.id } + extra.map { note in note.id }
        let trimmedQuery = String(query.prefix(200))
        let payload: [(String, Any?)] = [
            ("query", trimmedQuery),
            ("axis", axis),
            ("limit", limit),
            ("include_stale", includeStale),
            ("exclude_axes", excludeAxes as Any?),
            ("since_ts", sinceTs as Any?),
            ("hit_ids", rows.map { row in row.id }),
            ("expand_ids", extra.map { note in note.id })
        ]
        let record = RecordRetrievalTransaction.Parameter(
            sessionId: sessionId,
            activateIds: hitIds,
            strengthenPairs: cooccurrencePairs(hitIds),
            rebirthRanked: searchRanked(rows: rows, extra: extra),
            payloadJSON: Events.retrievalPayloadJSON(cmd: "search", payload: payload)
        )
        
        return (rows, extra, record)
    }
    
        // MARK: - Private
    // Pure derivations of the retrieval side effects — applied later by
    // RecordRetrievalTransaction on the write path.
    private static func cooccurrencePairs(_ ids: [String]) -> [RecordRetrievalTransaction.Pair] {
        var seen = Set<String>()
        var unique: [String] = []
        
        for id in ids where !id.isEmpty && !seen.contains(id) {
            seen.insert(id)
            unique.append(id)
        }
        
        if unique.count < 2 || unique.count > 8 { return [] }
        
        var pairs: [RecordRetrievalTransaction.Pair] = []
        
        for left in 0..<unique.count {
            for right in (left + 1)..<unique.count {
                pairs.append(RecordRetrievalTransaction.Pair(unique[left], unique[right]))
            }
        }
        
        return pairs
    }
    
    private static func searchRanked(
        rows: [Search.SearchRow],
        extra: [Links.ExpandedNote]
    ) -> [RecordRetrievalTransaction.Ranked] {
        let boost = Genome.double("rebirth.search_boost")
        var ranked: [RecordRetrievalTransaction.Ranked] = []
        
        for (index, row) in rows.enumerated() {
            ranked.append(RecordRetrievalTransaction.Ranked(row.id, 1.0 + boost / Double(index + 1)))
        }
        
        let base = rows.count
        
        for (index, note) in extra.enumerated() {
            ranked.append(RecordRetrievalTransaction.Ranked(note.id, 1.0 + boost / Double(base + index + 1)))
        }
        
        return ranked
    }
    
    private static func relatedRanked(snapshot: Framing.Snapshot) -> [RecordRetrievalTransaction.Ranked] {
        let boost = Genome.double("rebirth.related_boost")
        var ranked: [RecordRetrievalTransaction.Ranked] = []
        
        for (index, note) in snapshot.similar.enumerated() {
            ranked.append(RecordRetrievalTransaction.Ranked(note.id, 1.0 + boost / Double(index + 1)))
        }
        
        let baseRank = snapshot.similar.count
        
        for (index, note) in snapshot.linked.enumerated() {
            ranked.append(RecordRetrievalTransaction.Ranked(note.id, 1.0 + boost / Double(baseRank + index + 1)))
        }
        
        return ranked
    }
    
        private static func axesWithCounts(
        _ queue: any DatabaseReader
    ) throws -> [(axis: String, description: String?, count: Int)] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT a.axis, a.description, COALESCE(COUNT(n.id), 0) AS c
                FROM axes a LEFT JOIN notes n ON n.axis = a.axis
                GROUP BY a.axis ORDER BY a.axis
                """)
            
            return rows.map { row in
                (
                    axis: row["axis"] as String,
                    description: row["description"] as String?,
                    count: row["c"] as Int
                )
            }
        }
    }
    
    private static func batchForKind(
        _ db: Database,
        _ kind: String,
        limit: Int
    ) throws -> Candidates.Batch {
        switch kind {
        case "split":
            return .split(try Candidates.splitCandidates(db, limit: limit))
        
        case "reconsolidate":
            return .flagged(try Candidates.reconsolidateCandidates(db, limit: limit))
        
        case "ripple":
            return .flagged(try Candidates.rippleCandidates(db, limit: limit))
        
        case "enrich_review":
            return .flagged(try Candidates.enrichReviewCandidates(db, limit: limit))
        
        case "clusters":
            return .clusters(try Candidates.clusters(db, limit: limit))
        
        case "missing_edge":
            return .missingEdge(try Candidates.missingEdges(db, limit: limit))
        
        case "near_duplicate":
            return .nearDuplicate(try Candidates.nearDuplicates(db, limit: limit))
        
        default:
            return .split([])
        }
    }
}
