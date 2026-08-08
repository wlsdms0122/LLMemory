//
//  Query.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import Storage

public struct QueryFeature {
    public struct RelatedResult {
        // MARK: - Property
        public let snapshot: Framing.Snapshot
        public let bodies: [String: String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct NoteFrontmatter: Encodable {
        // MARK: - Property
        private let doc: FrontmatterDoc
        
        // MARK: - Initializer
        init(_ doc: FrontmatterDoc) {
            self.doc = doc
        }
        
        // MARK: - Public
        public func encode(to encoder: Encoder) throws {
            try doc.encode(to: encoder)
        }
        
        // MARK: - Private
    }
    
    public struct GetNote {
        // MARK: - Property
        public let id, axis, path: String
        public let frontmatter: NoteFrontmatter
        public let body: String
        public let hitCount, createdAt, editedAt: Int
        public let priority: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct SectionSlice {
        // MARK: - Property
        public let path: String
        public let text: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct TocEntry {
        // MARK: - Property
        public let path: String
        public let words: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct BudgetCut {
        // MARK: - Property
        public let shown: String
        public let shownSections: [TocEntry]
        public let omitted: [TocEntry]
        public let truncatedWithin: String?
        public let shownWords: Int
        public let totalWords: Int
        
        public var truncated: Bool { !omitted.isEmpty || truncatedWithin != nil }
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct StructureResult {
        // MARK: - Property
        public let axes: [(axis: String, description: String?, count: Int)]
        public let distribution: Links.Distribution
        public let axisStats: Stats.AxisStats?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public enum CandidateBatch {
        case split([Candidates.SplitCandidate])
        case flagged([Candidates.FlaggedCandidate])
        case clusters([Candidates.Cluster])
        case missingEdge([Candidates.MissingEdge])
        case nearDuplicate([Candidates.NearDuplicate])
        
        public var count: Int {
            switch self {
            case .split(let items):
                return items.count
            
            case .flagged(let items):
                return items.count
            
            case .clusters(let items):
                return items.count
            
            case .missingEdge(let items):
                return items.count
            
            case .nearDuplicate(let items):
                return items.count
            }
        }
    }
    
    // MARK: - Property
    public static let candidateValidKinds = Candidates.validKinds
    public static let candidateRetrievalKinds = Candidates.retrievalKinds
    public static let candidateStructuralKinds = Candidates.structuralKinds
    
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public

    // MARK: - Public (domain surface — configures the session and runs the matching transaction)
    public func search(
        query: String,
        axis: String?,
        limit: Int,
        expand: Int,
        cliSessionId: String,
        includeStale: Bool,
        excludeAxes: [String],
        raw: Bool
    ) async throws -> (rows: [Search.SearchRow], extra: [Links.ExpandedNote]) {
        try await session.storage.run(
            SearchNotesTransaction(
                .init(
                    query: query,
                    axis: axis,
                    limit: limit,
                    expand: expand,
                    cliSessionId: cliSessionId,
                    includeStale: includeStale,
                    excludeAxes: excludeAxes,
                    raw: raw
                )
            )
        )
    }

    public func related(
        text: String,
        kind: String?,
        cliSessionId: String,
        includeBodies: Bool
    ) async throws -> RelatedResult {
        try await session.storage.run(
            RelatedNotesTransaction(
                .init(
                    text: text,
                    kind: kind,
                    cliSessionId: cliSessionId,
                    includeBodies: includeBodies
                )
            )
        )
    }

    public func get(
        ids: [String],
        cliSessionId: String = ""
    ) async throws -> (found: [GetNote], missing: [String]) {
        try await session.storage.run(
            GetNotesTransaction(
                .init(
                    ids: ids,
                    cliSessionId: cliSessionId
                )
            )
        )
    }

    public func getSections(
        id: String,
        sections: [String]
    ) async throws -> (note: GetNote, slices: [SectionSlice]) {
        try await session.storage.run(
            GetSectionsTransaction(
                .init(
                    id: id,
                    sections: sections
                )
            )
        )
    }

    public func getBudget(
        id: String,
        budget: Int
    ) async throws -> (note: GetNote, cut: BudgetCut) {
        try await session.storage.run(
            GetBudgetTransaction(
                .init(
                    id: id,
                    budget: budget
                )
            )
        )
    }

    public func toc(
        id: String
    ) async throws -> (note: GetNote, entries: [TocEntry]) {
        try await session.storage.run(
            NoteTocTransaction(
                .init(
                    id: id
                )
            )
        )
    }

    public func template(
        id: String
    ) async throws -> (note: GetNote, frame: [Template.FrameNode]) {
        try await session.storage.run(
            TemplateFrameTransaction(
                .init(
                    id: id
                )
            )
        )
    }

    public func metaById(
        noteId: String,
        namespace: String?
    ) async throws -> [String: [String: String]] {
        try await session.storage.run(
            NoteMetaByIdTransaction(
                .init(
                    noteId: noteId,
                    namespace: namespace
                )
            )
        )
    }

    public func metaByKV(
        namespace: String,
        key: String,
        value: String?,
        limit: Int
    ) async throws -> [(noteId: String, value: String)] {
        try await session.storage.run(
            NoteMetaByKVTransaction(
                .init(
                    namespace: namespace,
                    key: key,
                    value: value,
                    limit: limit
                )
            )
        )
    }

    public func entity(
        name: String?,
        limit: Int
    ) async throws -> [Reads.EntityHit] {
        try await session.storage.run(
            EntityNotesTransaction(
                .init(
                    name: name,
                    limit: limit
                )
            )
        )
    }

    public func listAxes() async throws -> [(axis: String, description: String?, count: Int)] {
        try await session.storage.run(ListAxesTransaction())
    }

    public func structure(
        axis: String?
    ) async throws -> StructureResult {
        try await session.storage.run(
            StructureReportTransaction(
                .init(
                    axis: axis
                )
            )
        )
    }

    public func neighbors(
        id: String,
        k: Int,
        cliSessionId: String = ""
    ) async throws -> [Candidates.NeighborScore] {
        try await session.storage.run(
            NeighborsTransaction(
                .init(
                    id: id,
                    k: k,
                    cliSessionId: cliSessionId
                )
            )
        )
    }

    public func noteStats(
        id: String
    ) async throws -> Stats.NoteStats? {
        try await session.storage.run(
            NoteStatsTransaction(
                .init(
                    id: id
                )
            )
        )
    }

    public func axisStats(
        axis: String
    ) async throws -> Stats.AxisStats {
        try await session.storage.run(
            AxisStatsTransaction(
                .init(
                    axis: axis
                )
            )
        )
    }

    public func overallStats() async throws -> Stats.OverallStats {
        try await session.storage.run(OverallStatsTransaction())
    }

    public func list(
        priority: String?,
        axis: String?,
        stale: Bool,
        sourceStale: Bool,
        limit: Int?
    ) async throws -> [Reads.ListRow] {
        try await session.storage.run(
            ListNotesTransaction(
                .init(
                    priority: priority,
                    axis: axis,
                    stale: stale,
                    sourceStale: sourceStale,
                    limit: limit
                )
            )
        )
    }

    public func history(
        noteId: String,
        limit: Int
    ) async throws -> [Reads.HistoryEvent] {
        try await session.storage.run(
            NoteHistoryTransaction(
                .init(
                    noteId: noteId,
                    limit: limit
                )
            )
        )
    }

    public func lint(
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) async throws -> [Lint.Issue] {
        try await session.storage.run(
            LintTransaction(
                .init(
                    id: id,
                    code: code,
                    severity: severity,
                    limit: limit,
                    includeDismissed: includeDismissed
                )
            )
        )
    }

    public func enrichment() async throws -> EnrichmentReview.Status {
        try await session.storage.run(EnrichmentStatusTransaction())
    }

    public func candidates(
        kinds: [String],
        limit: Int
    ) async throws -> [String: CandidateBatch] {
        try await session.storage.run(
            CandidatesTransaction(
                .init(
                    kinds: kinds,
                    limit: limit
                )
            )
        )
    }

    static func search(
        _ queue: any DatabaseWriter,
        query: String,
        axis: String?,
        limit: Int,
        expand: Int,
        cliSessionId: String,
        includeStale: Bool,
        excludeAxes: [String],
        raw: Bool
    ) throws -> (rows: [Search.SearchRow], extra: [Links.ExpandedNote]) {
        return try searchNotes(
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
        _ queue: any DatabaseWriter,
        text: String,
        kind: String?,
        cliSessionId: String,
        includeBodies: Bool
    ) throws -> RelatedResult {
        let sessionId = Env.retrievalSession(cli: cliSessionId)
        let snapshot = try Framing.snapshot(
            queue,
            userInput: text,
            agentOutput: "",
            linkKind: kind,
            sessionId: sessionId
        )
        
        Events.recordRetrieval(
            queue,
            cmd: "related",
            payload: [
                ("text", String(text.prefix(200))),
                ("hit_ids", snapshot.similar.map { note in note.id }),
                ("expand_ids", snapshot.linked.map { note in note.id })
            ],
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
        
        return RelatedResult(snapshot: snapshot, bodies: bodies)
    }
    
    static func get(
        _ queue: any DatabaseWriter,
        ids: [String],
        cliSessionId: String = ""
    ) throws -> (found: [GetNote], missing: [String]) {
                let byId = try queue.read { db in try Reads.catalog(db, ids: ids) }
        var found: [GetNote] = []
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
                GetNote(
                    id: id,
                    axis: record.axis,
                    path: record.path,
                    frontmatter: NoteFrontmatter(doc),
                    body: body,
                    hitCount: record.hitCount,
                    createdAt: record.createdAt,
                    editedAt: record.editedAt,
                    priority: record.priority
                )
            )
        }
        
        if !found.isEmpty {
            Events.recordRetrieval(
                queue,
                cmd: "get",
                payload: [("hit_ids", found.map { note in note.id })],
                sessionId: Env.retrievalSession(cli: cliSessionId)
            )
        }
        
        return (found, missing)
    }
    
    static func getSections(
        _ queue: any DatabaseWriter,
        id: String,
        sections: [String]
    ) throws -> (note: GetNote, slices: [SectionSlice]) {
        let (found, missing) = try get(queue, ids: [id])
        
        guard let note = found.first else {
            throw NotesError.unknownIds(missing)
        }
        
        var slices: [SectionSlice] = []
        
        for raw in sections {
            let path = try SectionEdit.parsePath(raw)
            let text = try SectionEdit.subtreeText(note.body, path: path)
            
            slices.append(SectionSlice(path: path.display(), text: text))
        }
        
        return (note, slices)
    }
    
    static func getBudget(
        _ queue: any DatabaseWriter,
        id: String,
        budget: Int
    ) throws -> (note: GetNote, cut: BudgetCut) {
        let (found, missing) = try get(queue, ids: [id])
        
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
            
            return (note, BudgetCut(
                shown: shown,
                shownSections: [],
                omitted: tops.map { top in
                    TocEntry(
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
        var shownSections: [TocEntry] = []
        var omitted: [TocEntry] = []
        var cutAt: Int? = nil
        
        for top in tops {
            let words = SectionEdit.wordCount(lines[top.start..<top.end].joined(separator: "\n"))
            
            if cutAt == nil && running + words <= budget {
                running += words
                shownSections.append(TocEntry(path: top.path, words: words))
            } else {
                if cutAt == nil { cutAt = top.start }
                
                omitted.append(TocEntry(path: top.path, words: words))
            }
        }
        
        guard let cut = cutAt else {
            return (note, BudgetCut(
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
            
            return (note, BudgetCut(
                shown: shown,
                shownSections: [],
                omitted: Array(omitted.dropFirst()),
                truncatedWithin: first.path,
                shownWords: SectionEdit.wordCount(shown),
                totalWords: totalWords
            ))
        }
        
        return (note, BudgetCut(
            shown: lines[..<cut].joined(separator: "\n"),
            shownSections: shownSections,
            omitted: omitted,
            truncatedWithin: nil,
            shownWords: running,
            totalWords: totalWords
        ))
    }
    
    static func toc(_ queue: any DatabaseWriter, id: String) throws -> (note: GetNote, entries: [TocEntry]) {
        let (found, missing) = try get(queue, ids: [id])
        
        guard let note = found.first else {
            throw NotesError.unknownIds(missing)
        }
        
        let (_, rows) = SectionEdit.sectionRows(note.body)
        let entries = rows.map { row in
            TocEntry(path: row.path, words: SectionEdit.wordCount(row.text))
        }
        
        return (note, entries)
    }
    
    static func template(
        _ queue: any DatabaseWriter,
        id: String
    ) throws -> (note: GetNote, frame: [Template.FrameNode]) {
        let (found, missing) = try get(queue, ids: [id])
        
        guard let note = found.first else {
            throw NotesError.unknownIds(missing)
        }
        
        return (note, Template.parseFrame(note.body))
    }
    
    static func metaById(
        _ queue: any DatabaseWriter,
        noteId: String,
        namespace: String?
    ) throws -> [String: [String: String]] {
        return try queue.read { db in
            try NoteMeta.getAll(db, noteId: noteId, namespace: namespace)
        }
    }
    
    static func metaByKV(
        _ queue: any DatabaseWriter,
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
    
    static func entity(_ queue: any DatabaseWriter, name: String?, limit: Int) throws -> [Reads.EntityHit] {
        return try queue.read { db in try Reads.entityLookup(db, name: name, limit: limit) }
    }
    
    static func listAxes(_ queue: any DatabaseWriter) throws -> [(axis: String, description: String?, count: Int)] {
        try axesWithCounts(queue)
    }
    
    static func structure(_ queue: any DatabaseWriter, axis: String?) throws -> StructureResult {
                let axes = try axesWithCounts(queue)
        let distribution = try Links.distribution(queue)
        var stats: Stats.AxisStats? = nil
        
        if let axis {
            stats = try queue.read { db in try Stats.axisStats(db, axis: axis) }
        }
        
        return StructureResult(axes: axes, distribution: distribution, axisStats: stats)
    }
    
    static func neighbors(
        _ queue: any DatabaseWriter,
        id: String,
        k: Int,
        cliSessionId: String = ""
    ) throws -> [Candidates.NeighborScore] {
                let scores = try queue.read { db in try Candidates.neighbors(db, noteId: id, k: k) }
        
        Events.recordRetrieval(
            queue,
            cmd: "neighbors",
            payload: [("anchor", id), ("hit_ids", scores.map { score in score.id })],
            sessionId: Env.retrievalSession(cli: cliSessionId)
        )
        
        return scores
    }
    
    static func noteStats(_ queue: any DatabaseWriter, id: String) throws -> Stats.NoteStats? {
        return try queue.read { db in try Stats.noteStats(db, nid: id) }
    }
    
    static func axisStats(_ queue: any DatabaseWriter, axis: String) throws -> Stats.AxisStats {
        return try queue.read { db in try Stats.axisStats(db, axis: axis) }
    }
    
    static func overallStats(_ queue: any DatabaseWriter) throws -> Stats.OverallStats {
        return try queue.read { db in try Stats.overall(db) }
    }
    
    static func list(
        _ queue: any DatabaseWriter,
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
        _ queue: any DatabaseWriter,
        noteId: String,
        limit: Int
    ) throws -> [Reads.HistoryEvent] {
        return try queue.read { db in try Reads.history(db, noteId: noteId, limit: limit) }
    }
    
    static func lint(
        _ queue: any DatabaseWriter,
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
    
    static func enrichment(_ queue: any DatabaseWriter) throws -> EnrichmentReview.Status {
        return try queue.read { db in try EnrichmentReview.status(db) }
    }
    
    static func candidates(
        _ queue: any DatabaseWriter,
        kinds: [String],
        limit: Int
    ) throws -> [String: CandidateBatch] {
        return try queue.read { db in
            var batches: [String: CandidateBatch] = [:]
            
            for kind in kinds { batches[kind] = try batchForKind(db, kind, limit: limit) }
            
            return batches
        }
    }
    
    static func searchNotes(
        _ queue: any DatabaseWriter,
        query: String,
        axis: String? = nil,
        limit: Int = 5,
        expand: Int = 0,
        sessionId: String? = nil,
        includeStale: Bool = false,
        excludeAxes: [String]? = nil,
        sinceTs: Int? = nil,
        raw: Bool = false
    ) throws -> (rows: [Search.SearchRow], extra: [Links.ExpandedNote]) {
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
        
        try queue.write { db in
            try Notes.activate(db, ids: hitIds, now: Int(Date().timeIntervalSince1970))
        }
        
        wireTogether(queue, ids: hitIds)
        rehearseAssoc(queue, rows: rows, extra: extra)
        
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
        
        Events.recordRetrieval(queue, cmd: "search", payload: payload, sessionId: sessionId)
        
        return (rows, extra)
    }
    
    // MARK: - Private
    private static func wireTogether(_ queue: any DatabaseWriter, ids: [String]) {
        var seen = Set<String>()
        var unique: [String] = []
        
        for id in ids where !id.isEmpty && !seen.contains(id) {
            seen.insert(id)
            unique.append(id)
        }
        
        if unique.count < 2 || unique.count > 8 { return }
        
        var pairs: [(String, String)] = []
        
        for left in 0..<unique.count {
            for right in (left + 1)..<unique.count {
                pairs.append((unique[left], unique[right]))
            }
        }
        
        _ = try? Links.strengthen(queue, pairs: pairs, cap: 1.0)
    }
    
    private static func rehearseAssoc(_ queue: any DatabaseWriter, rows: [Search.SearchRow], extra: [Links.ExpandedNote]) {
        let boost = Genome.double("rebirth.search_boost")
        var ranked: [(String, Double)] = []
        
        for (index, row) in rows.enumerated() {
            ranked.append((row.id, 1.0 + boost / Double(index + 1)))
        }
        
        let base = rows.count
        
        for (index, note) in extra.enumerated() {
            ranked.append((note.id, 1.0 + boost / Double(base + index + 1)))
        }
        
        if ranked.count >= 2 { _ = try? Links.rebirth(queue, rankedIds: ranked) }
    }
    
    private static func axesWithCounts(
        _ queue: any DatabaseWriter
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
    ) throws -> CandidateBatch {
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
