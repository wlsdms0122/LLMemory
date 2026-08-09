//
//  Framing.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum Framing {
    public struct AxisRow {
        // MARK: - Property
        public let axis: String
        public let count: Int
        public let description: String?
        public let topTags: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct SimilarNote {
        // MARK: - Property
        public let id: String
        public let axis: String
        public let title: String
        public let summary: String?
        public let path: String
        public let tags: [String]
        public let section: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct Snapshot {
        // MARK: - Property
        public var keywords: [String]
        public var axes: [AxisRow]
        public var similar: [SimilarNote]
        public var linked: [Links.ExpandedNote]
        public var vectorLinked: [Vectors.VectorHit]
        public var topTags: [(String, Int)]
        public var cooccur: [(String, String, Int)]
        public var vocab: [String]
        public var entityHints: [String]
        public var entityHits: [EntityHit]
        public var degraded: [String] = []
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let stopwords: Set<String> = [
        "그리고", "하지만", "그런데", "그래서", "그러면", "이게", "저게", "이거",
        "저거", "뭐야", "있어", "없어", "해줘", "해봐", "하자", "이렇게", "저렇게",
        "이런", "저런", "정도", "우리", "너가", "니가", "내가", "근데",
        "the", "and", "for", "with", "this", "that", "are", "was", "were", "will",
        "have", "has", "had", "been", "from", "not", "but", "can", "get", "got",
        "you", "your", "they", "them", "their", "our", "out", "off", "about",
        "just", "into", "what", "when", "where", "which", "than", "then"
    ]
    
    private static let wordRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9_가-힣]{2,}"#)
    
    // MARK: - Initializer
    // MARK: - Public
    static func extractKeywords(_ text: String, limit: Int = 15) -> [String] {
        var frequency: [String: Int] = [:]
        let nsText = text as NSString
        
        wordRegex.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match else { return }
            
            let word = nsText.substring(with: match.range).lowercased()
            
            if stopwords.contains(word) { return }
            
            frequency[word, default: 0] += 1
        }
        
        let ranked = frequency.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            
            return lhs.key < rhs.key
        }
        
        return ranked.prefix(limit).map { entry in entry.key }
    }
    
    static func axesInfo(_ db: Database, topTagsLimit: Int = 8) throws -> [AxisRow] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT a.axis, COALESCE(COUNT(n.id), 0) AS cnt, a.description
            FROM axes a
            LEFT JOIN notes n ON n.axis = a.axis
            GROUP BY a.axis ORDER BY a.axis
            """)
        var axes: [AxisRow] = []
        
        for row in rows {
            let axis: String = row["axis"]
            let topTags = try String.fetchAll(db, sql: """
                SELECT t.tag FROM notes n JOIN tags t ON t.note_id = n.id
                WHERE n.axis = ?
                GROUP BY t.tag ORDER BY COUNT(*) DESC, t.tag LIMIT ?
                """, arguments: [axis, topTagsLimit])
            
            axes.append(
                AxisRow(
                    axis: axis,
                    count: row["cnt"] as Int? ?? 0,
                    description: row["description"] as String?,
                    topTags: topTags
                )
            )
        }
        
        return axes
    }
    
    static func similar(
        _ db: Database,
        keywords: [String],
        limit: Int,
        includeStale: Bool = false,
        sessionId: String? = nil
    ) throws -> [SimilarNote] {
        let matchExpr = ftsQuery(keywords)
        
        if matchExpr.isEmpty { return [] }
        
        var sql = """
                SELECT n.id, n.axis, n.title, n.summary, n.path,
                       (SELECT group_concat(tag, ',') FROM tags WHERE note_id = n.id) AS tags,
                       f.section AS section, MIN(rank) AS best_rank
                FROM notes_fts f JOIN notes n ON n.id = f.id
                WHERE notes_fts MATCH ?
                """
        var arguments: [DatabaseValueConvertible?] = [matchExpr]
        
        if !includeStale {
            sql += " AND \(Policy.fresh())"
        }
        
        let now = Int(Date().timeIntervalSince1970)
        let prior: [String: Double]
        
        if let sessionId, !sessionId.isEmpty {
            let windowMin = Genome.int("priming.window_min")
            prior = (try? ComputeAxisPriorTransaction(
                sessionId: sessionId,
                windowSec: windowMin * 60,
                now: now
            )
                .perform(db)) ?? [:]
        } else {
            prior = [:]
        }
        
        let needsRerank = !prior.isEmpty
        let fetchLimit = Search.fetchPoolSize(limit: limit, needsRerank: needsRerank)
        sql += Search.noteAggregationSQL
        arguments.append(fetchLimit)
        
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        let pool: [SimilarNote] = rows.map { row in
            let tagsCSV = row["tags"] as String? ?? ""
            let tags = tagsCSV.isEmpty ? [] : tagsCSV.split(separator: ",").map(String.init)
            let section = (row["section"] as String?).flatMap { value in
                value.isEmpty ? nil : value
            }
            
            return SimilarNote(
                id: row["id"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?,
                path: row["path"],
                tags: tags,
                section: section
            )
        }
        
        if !needsRerank { return pool }
        
        return Search.rerank(pool, prior: prior, limit: limit) { note in note.axis }
    }
    
    static func topTags(_ db: Database, limit: Int = 20) throws -> [(tag: String, count: Int)] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT tag, COUNT(*) c FROM tags GROUP BY tag ORDER BY c DESC, tag LIMIT ?",
            arguments: [limit]
        )
        
        return rows.map { row in (row["tag"] as String, row["c"] as Int) }
    }
    
    static func cooccurFor(
        _ db: Database,
        tags: [String],
        limit: Int = 15
    ) throws -> [(tagA: String, tagB: String, count: Int)] {
        try Vocab.cooccurFor(db, tags: tags, limit: limit)
    }
    
    static func vocab(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT tag FROM tag_vocab ORDER BY tag")
    }
    
    static func snapshot(
        _ queue: any DatabaseReader,
        userInput: String,
        agentOutput: String,
        similarLimit: Int? = nil,
        expandHops: Int? = nil,
        linkKind: String? = nil,
        sessionId: String? = nil
    ) throws -> Snapshot {
        let similarLimit = similarLimit ?? Genome.int("related.similar_limit")
        let expandHops = expandHops ?? Genome.int("related.expand_hops")
        let text = "\(userInput)\n\(agentOutput)"
        let keywords = extractKeywords(text)
        let entityHints = NoteText.extractEntityHints(text)
        var similarNotes: [SimilarNote] = []
        var axes: [AxisRow] = []
        var topTagCounts: [(String, Int)] = []
        var cooccurrences: [(String, String, Int)] = []
        var vocabEntries: [String] = []
        var entityHits: [EntityHit] = []
        
        try queue.read { db in
            similarNotes = try similar(
                db,
                keywords: keywords,
                limit: similarLimit,
                sessionId: sessionId
            )
            
            let similarTagSet = Set(similarNotes.flatMap { note in note.tags })
            axes = try axesInfo(db)
            topTagCounts = try topTags(db)
            cooccurrences = try cooccurFor(db, tags: similarTagSet.sorted())
            vocabEntries = try vocab(db)
            entityHits = try FetchEntityHitsTransaction(entities: entityHints).perform(db)
        }
        
        var degraded: [String] = []
        var linked: [Links.ExpandedNote] = []
        
        if !similarNotes.isEmpty {
            do {
                linked = try Links.expand(
                    queue,
                    noteIds: similarNotes.map { note in note.id },
                    hops: expandHops,
                    kind: linkKind
                )
            } catch {
                degraded.append("linked: \(error)")
            }
        }
        
        var vectorLinked: [Vectors.VectorHit] = []
        
        if !similarNotes.isEmpty {
            let already = Set(similarNotes.map { note in note.id })
                .union(linked.map { note in note.id })
            
            do {
                vectorLinked = try Vectors.expand(
                    queue,
                    seedIds: similarNotes.map { note in note.id },
                    limit: similarLimit,
                    excludeIds: already
                )
            } catch {
                degraded.append("vector_linked: \(error)")
            }
        }
        
        return Snapshot(
            keywords: keywords,
            axes: axes,
            similar: similarNotes,
            linked: linked,
            vectorLinked: vectorLinked,
            topTags: topTagCounts,
            cooccur: cooccurrences,
            vocab: vocabEntries,
            entityHints: entityHints,
            entityHits: entityHits,
            degraded: degraded
        )
    }
    
    // MARK: - Private
    private static func ftsQuery(_ keywords: [String]) -> String {
        let parts = keywords
            .filter { keyword in !keyword.isEmpty }
            .map { keyword in "\"\(keyword)\"" }
        
        return parts.isEmpty ? "" : parts.joined(separator: " OR ")
    }
}

public extension Framing {
    struct RelatedResult {
        // MARK: - Property
        public let snapshot: Framing.Snapshot
        public let bodies: [String: String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
}
