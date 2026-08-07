//
//  Candidates.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum Candidates {
    public struct SplitCandidate {
        // MARK: - Property
        public let id: String
        public let axis: String
        public let title: String
        public let wordCount: Int
        public let sectionCount: Int
        public let tagCount: Int
        public let sections: [SectionSketch]
        public let reason: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct SectionSketch {
        // MARK: - Property
        public let path: String
        public let title: String
        public let wordCount: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct FlaggedCandidate {
        // MARK: - Property
        public let id: String
        public let reason: String?
        public let createdAt: Int
        public let axis: String
        public let title: String
        public let summary: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct NeighborScore {
        // MARK: - Property
        public var id: String
        public var axis: String
        public var title: String
        public var summary: String?
        public var fts: Double
        public var entity: Double
        public var link: Double
        public var score: Double
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct Cluster {
        public struct Member {
            // MARK: - Property
            package let id: String
            package let axis: String
            package let title: String
            package let summary: String?
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        public struct Edge {
            // MARK: - Property
            public let a: String
            package let b: String
            public let fts: Double
            package let entity: Double
            package let link: Double
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        // MARK: - Property
        public let size: Int
        public let axes: [String]
        public let members: [Member]
        public let edges: [Edge]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct MissingEdge {
        public struct Member {
            // MARK: - Property
            public let id: String
            public let axis: String
            public let title: String
            public let summary: String?
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        // MARK: - Property
        public let a: Member
        public let b: Member
        public let source: String
        public let score: Double
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct NearDuplicate {
        public struct Member {
            // MARK: - Property
            public let id: String
            public let axis: String
            public let title: String
            public let summary: String?
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        // MARK: - Property
        public let a: Member
        public let b: Member
        public let fts: Double
        public let entity: Double
        public let link: Double
        public let jaccard: Double
        public let containment: Double
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let retrievalKinds: [String] = ["clusters", "missing_edge", "near_duplicate"]
    static let structuralKinds: [String] = ["split", "reconsolidate", "ripple", "enrich_review"]
    
    static var validKinds: [String] { retrievalKinds + structuralKinds }
    
    private static let wordRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9가-힣]{3,}"#)
    
    // MARK: - Initializer
    // MARK: - Public
    static func splitCandidates(_ db: Database, limit: Int = 20) throws -> [SplitCandidate] {
        let minWords = Config.getInt("split.min_words", default: 400)
        let minSections = Config.getInt("split.min_sections", default: 4)
        let minTagDiversity = Config.getInt("split.min_tag_diversity", default: 3)
        let rows = try Row.fetchAll(db, sql: """
            SELECT n.id, n.axis, n.title, n.word_count, n.section_count,
                   (SELECT COUNT(DISTINCT tag) FROM tags WHERE note_id = n.id) AS tag_count
            FROM notes n
            WHERE \(Policy.decayCandidate())
              AND n.word_count >= ?
              AND n.section_count >= ?
            ORDER BY n.word_count DESC, n.id ASC
            """, arguments: [minWords, minSections])
        let dismissals = try Dismissals.byNote(db, kind: "split")
        let generation = try Dismissals.generation(db)
        var candidates: [SplitCandidate] = []
        
        for row in rows {
            let noteId: String = row["id"]
            let tagCount: Int = row["tag_count"] as Int? ?? 0
            
            if tagCount < minTagDiversity { continue }
            
            let wordCount: Int = row["word_count"] as Int? ?? 0
            let sectionCount: Int = row["section_count"] as Int? ?? 0
            let verdict = Dismissals.gate(
                dismissals[noteId],
                currentWords: wordCount,
                currentSections: sectionCount,
                globalGeneration: generation
            )
            
            if !verdict.surface { continue }
            
            let sections: [SectionSketch]
            do {
                sections = try sectionSketch(db, nid: noteId)
            } catch is NoteUnreadable {
                continue
            }
            
            let base = "size=\(wordCount)w sections=\(sectionCount) tags=\(tagCount)"
            
            candidates.append(
                SplitCandidate(
                    id: noteId,
                    axis: row["axis"],
                    title: row["title"],
                    wordCount: wordCount,
                    sectionCount: sectionCount,
                    tagCount: tagCount,
                    sections: sections,
                    reason: verdict.annotation.map { note in "\(base) · 재부상: \(note)" } ?? base
                )
            )
            
            if candidates.count >= limit { break }
        }
        
        return candidates
    }
    
    static func reconsolidateCandidates(
        _ db: Database,
        limit: Int = 20
    ) throws -> [FlaggedCandidate] {
        try flagged(db, flag: "reconsolidate", limit: limit)
    }
    
    static func rippleCandidates(_ db: Database, limit: Int = 20) throws -> [FlaggedCandidate] {
        try flagged(db, flag: "stale_ref", limit: limit)
    }
    
    static func enrichReviewCandidates(
        _ db: Database,
        limit: Int = 20
    ) throws -> [FlaggedCandidate] {
        try flagged(db, flag: EnrichmentReview.flagKind, limit: limit)
    }
    
    static func neighbors(_ db: Database, noteId: String, k: Int = 10) throws -> [NeighborScore] {
        guard let targetRow = try Row.fetchOne(
            db,
            sql: "SELECT id, axis, title, path FROM notes WHERE id = ?",
            arguments: [noteId]
        ) else {
            throw NotesError.unknownIds([noteId])
        }
        
        let targetTitle: String = targetRow["title"]
        let targetRelativePath: String = targetRow["path"]
        let targetPath = Paths.brainRoot.appendingPathComponent(targetRelativePath)
        let body = try Notes.requireNote(at: targetPath).body
        var scores: [String: NeighborScore] = [:]
        let searchText = "\(targetTitle) \(body)"
        let nsSearchText = searchText as NSString
        var tokens = Set<String>()
        
        wordRegex.enumerateMatches(
            in: searchText,
            range: NSRange(location: 0, length: nsSearchText.length)
        ) { match, _, _ in
            guard let match else { return }
            
            tokens.insert(nsSearchText.substring(with: match.range).lowercased())
        }
        
        if !tokens.isEmpty {
            let tokenList = tokens.sorted()
            let matchExpr = tokenList.map { token in "\"\(token)\"" }.joined(separator: " OR ")
            
            if let rows = try? Row.fetchAll(db, sql: """
                SELECT n.id, n.axis, n.title, n.summary, MIN(rank) AS s
                FROM notes_fts f JOIN notes n ON n.id = f.id
                WHERE notes_fts MATCH ? AND n.id != ? AND \(Policy.surface())
                GROUP BY n.id
                ORDER BY s, n.id LIMIT 30
                """, arguments: [matchExpr, noteId]) {
                let total = max(rows.count, 1)
                
                for (rank, row) in rows.enumerated() {
                    let normalized = 1.0 - Double(rank) / Double(total)
                    let hitId: String = row["id"]
                    var score = scores[hitId] ?? NeighborScore(
                        id: hitId,
                        axis: row["axis"],
                        title: row["title"],
                        summary: row["summary"] as String?,
                        fts: 0,
                        entity: 0,
                        link: 0,
                        score: 0
                    )
                    score.fts = normalized
                    scores[hitId] = score
                }
            }
        }
        
        let targetEntities = Set(
            try String.fetchAll(
                db,
                sql: "SELECT entity FROM entity_index WHERE note_id = ?",
                arguments: [noteId]
            )
        )
        
        if !targetEntities.isEmpty {
            let rows = try Row.fetchAll(db, sql: """
                SELECT n.id, n.axis, n.title, n.summary,
                       (SELECT COUNT(*) FROM entity_index e1
                         JOIN entity_index e2 ON e1.entity = e2.entity
                         WHERE e1.note_id = ? AND e2.note_id = n.id) AS inter,
                       (SELECT COUNT(*) FROM entity_index WHERE note_id = n.id) AS sz
                FROM notes n
                WHERE n.id != ? AND \(Policy.surface())
                """, arguments: [noteId, noteId])
            let targetSize = targetEntities.count
            
            for row in rows {
                let intersection: Int = row["inter"] as Int? ?? 0
                
                if intersection == 0 { continue }
                
                let otherSize: Int = row["sz"] as Int? ?? 0
                let denominator = max(targetSize + otherSize - intersection, 1)
                let jaccard = Double(intersection) / Double(denominator)
                let hitId: String = row["id"]
                var score = scores[hitId] ?? NeighborScore(
                    id: hitId,
                    axis: row["axis"],
                    title: row["title"],
                    summary: row["summary"] as String?,
                    fts: 0,
                    entity: 0,
                    link: 0,
                    score: 0
                )
                score.entity = jaccard
                scores[hitId] = score
            }
        }
        
        let linkRows = try Row.fetchAll(db, sql: """
            SELECT n.id, n.axis, n.title, n.summary, SUM(\(Links.rankWeightSQL("l"))) AS w
            FROM (
              SELECT dst AS other, kind, weight FROM note_links WHERE src = ?
              UNION ALL
              SELECT src AS other, kind, weight FROM note_links WHERE dst = ?
            ) l
            JOIN notes n ON n.id = l.other
            WHERE \(Policy.surface())
            GROUP BY n.id ORDER BY w DESC, n.id LIMIT 30
            """, arguments: [noteId, noteId])
        
        if !linkRows.isEmpty {
            let maxWeight = linkRows.compactMap { row in row["w"] as Double? }.max() ?? 1.0
            let normalizer = maxWeight == 0 ? 1.0 : maxWeight
            
            for row in linkRows {
                let weight: Double = row["w"] as Double? ?? 0
                let hitId: String = row["id"]
                var score = scores[hitId] ?? NeighborScore(
                    id: hitId,
                    axis: row["axis"],
                    title: row["title"],
                    summary: row["summary"] as String?,
                    fts: 0,
                    entity: 0,
                    link: 0,
                    score: 0
                )
                score.link = weight / normalizer
                scores[hitId] = score
            }
        }
        
        var ranked: [NeighborScore] = scores.values.map { neighbor in
            var scored = neighbor
            scored.score = round((scored.fts + scored.entity + scored.link) * 10000) / 10000
            
            return scored
        }
        
        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            
            return lhs.id < rhs.id
        }
        
        return Array(ranked.prefix(k))
    }
    
    static func clusters(
        _ db: Database,
        minSize: Int = 2,
        maxSize: Int? = nil,
        limit: Int = 20
    ) throws -> [Cluster] {
        let cap = maxSize ?? Config.getInt("candidates.cluster.max_size", default: 12)
        var edges: [(String, String)] = []
        let linkRows = try Row.fetchAll(db, sql: """
            SELECT src, dst FROM note_links nl
            JOIN notes a ON a.id = nl.src
            JOIN notes b ON b.id = nl.dst
            WHERE \(Policy.all(Policy.surface("a"), Policy.forgetExempt("a")))
              AND \(Policy.all(Policy.surface("b"), Policy.forgetExempt("b")))
            """)
        
        for row in linkRows {
            edges.append((row["src"], row["dst"]))
        }
        
        let entityRows = try Row.fetchAll(db, sql: """
            SELECT e1.note_id AS a, e2.note_id AS b
            FROM entity_index e1 JOIN entity_index e2
              ON e1.entity = e2.entity AND e1.note_id < e2.note_id
            JOIN notes na ON na.id = e1.note_id
            JOIN notes nb ON nb.id = e2.note_id
            WHERE \(Policy.all(Policy.surface("na"), Policy.forgetExempt("na")))
              AND \(Policy.all(Policy.surface("nb"), Policy.forgetExempt("nb")))
            GROUP BY e1.note_id, e2.note_id
            """)
        
        for row in entityRows {
            edges.append((row["a"], row["b"]))
        }
        
        var parent: [String: String] = [:]
        
        func find(_ node: String) -> String {
            var cursor = node
            
            while parent[cursor, default: cursor] != cursor {
                let up = parent[cursor, default: cursor]
                let grandparent = parent[up, default: up]
                parent[cursor] = grandparent
                cursor = grandparent
            }
            
            parent[cursor] = cursor
            
            return cursor
        }
        
        func union(_ left: String, _ right: String) {
            let leftRoot = find(left)
            let rightRoot = find(right)
            
            if leftRoot != rightRoot { parent[leftRoot] = rightRoot }
        }
        
        for (left, right) in edges {
            _ = find(left)
            _ = find(right)
            union(left, right)
        }
        
        var groups: [String: [String]] = [:]
        
        for node in parent.keys {
            groups[find(node), default: []].append(node)
        }
        
        var clusters: [Cluster] = []
        
        for (_, members) in groups where members.count >= minSize && members.count <= cap {
            let placeholders = Array(repeating: "?", count: members.count).joined(separator: ",")
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, axis, title, summary FROM notes WHERE id IN (\(placeholders)) ORDER BY id",
                arguments: StatementArguments(members)
            )
            let memberStructs = rows.map { row in
                Cluster.Member(
                    id: row["id"],
                    axis: row["axis"],
                    title: row["title"],
                    summary: row["summary"] as String?
                )
            }
            let axes = Array(Set(memberStructs.map { member in member.axis })).sorted()
            let clusterEdges = try clusterEdges(db, memberIds: members)
            
            clusters.append(
                Cluster(
                    size: members.count,
                    axes: axes,
                    members: memberStructs,
                    edges: clusterEdges
                )
            )
        }
        
        clusters.sort { lhs, rhs in
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            
            let leftFirst = lhs.members.first?.id ?? ""
            let rightFirst = rhs.members.first?.id ?? ""
            
            return leftFirst < rightFirst
        }
        
        return Array(clusters.prefix(limit))
    }
    
    static func missingEdges(
        _ db: Database,
        limit: Int = 20,
        perNote: Int = 3,
        vecCos: Double? = nil,
        ftsBm25: Double? = nil
    ) throws -> [MissingEdge] {
        let cosineThreshold = vecCos ?? Genome.double("candidates.missing_edge.vec_cos")
        let bm25Threshold = ftsBm25 ?? Genome.double("candidates.missing_edge.fts_bm25")
        var linked = Set<String>()
        var degree: [String: Int] = [:]
        
        for row in try Row.fetchAll(db, sql: """
            SELECT l.src, l.dst FROM note_links l
            JOIN notes ns ON ns.id = l.src AND \(Policy.surface("ns"))
            JOIN notes nd ON nd.id = l.dst AND \(Policy.surface("nd"))
            """) {
            let src: String = row["src"]
            let dst: String = row["dst"]
            
            linked.insert(pairKey(src, dst))
            degree[src, default: 0] += 1
            degree[dst, default: 0] += 1
        }
        
        var meta: [String: MissingEdge.Member] = [:]
        
        for row in try Row.fetchAll(
            db,
            sql: "SELECT id, axis, title, summary FROM notes WHERE \(Policy.all(Policy.surface(""), Policy.notEager("")))"
        ) {
            let id: String = row["id"]
            meta[id] = MissingEdge.Member(
                id: id,
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?
            )
        }
        
        var best: [String: (source: String, score: Double, a: String, b: String)] = [:]
        
        func offer(_ left: String, _ right: String, source: String, score: Double) {
            guard meta[left] != nil, meta[right] != nil, left != right else { return }
            
            let (a, b) = left < right ? (left, right) : (right, left)
            let key = pairKey(a, b)
            
            if linked.contains(key) { return }
            
            if let current = best[key] {
                let currentIsVector = current.source == "vector"
                let newIsVector = source == "vector"
                
                if !newIsVector && currentIsVector { return }
                
                if newIsVector == currentIsVector {
                    let better = newIsVector ? score > current.score : score < current.score
                    
                    if !better { return }
                }
            }
            
            best[key] = (source, score, a, b)
        }
        
        do {
            let raw = try EnrichmentReview.loadVectors(db)
            var vectors: [String: [Float]] = [:]
            
            for (id, vector) in raw where vector.count > 1 {
                vectors[id] = Array(vector.dropFirst())
            }
            
            let connected = Array(
                vectors.keys.filter { id in (degree[id] ?? 0) >= 1 && meta[id] != nil }
            )
            
            for anchor in connected {
                guard let anchorVector = vectors[anchor] else { continue }
                
                var scored: [(String, Double)] = []
                
                for other in connected where other != anchor {
                    guard let otherVector = vectors[other] else { continue }
                    
                    let cosine = EnrichmentReview.cosine(anchorVector, otherVector)
                    
                    if cosine >= cosineThreshold { scored.append((other, cosine)) }
                }
                
                scored.sort { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0 < rhs.0 }
                
                for (other, cosine) in scored.prefix(perNote) {
                    offer(anchor, other, source: "vector", score: round(cosine * 1000) / 1000)
                }
            }
        }
        
        for anchor in meta.keys where (degree[anchor] ?? 0) == 0 {
            let hits: [(String, Double)]
            do {
                hits = try bm25Neighbors(
                    db,
                    noteId: anchor,
                    limit: perNote,
                    maxBm25: bm25Threshold
                )
            } catch is NoteUnreadable {
                continue
            }
            
            for (other, score) in hits {
                offer(anchor, other, source: "fts", score: round(score * 1000) / 1000)
            }
        }
        
        let sorted = best.values.sorted { lhs, rhs in
            let leftIsVector = lhs.source == "vector"
            let rightIsVector = rhs.source == "vector"
            
            if leftIsVector != rightIsVector { return leftIsVector }
            
            if lhs.score != rhs.score {
                return leftIsVector ? lhs.score > rhs.score : lhs.score < rhs.score
            }
            
            if lhs.a != rhs.a { return lhs.a < rhs.a }
            
            return lhs.b < rhs.b
        }
        
        return sorted.prefix(limit).map { entry in
            MissingEdge(
                a: meta[entry.a]!,
                b: meta[entry.b]!,
                source: entry.source,
                score: entry.score
            )
        }
    }
    
    static func nearDuplicates(
        _ db: Database,
        minFts: Double = 0.85,
        minJaccard: Double = 0.6,
        minContainment: Double = 0.85,
        limit: Int = 20
    ) throws -> [NearDuplicate] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, axis, title, summary, path FROM notes
            WHERE \(Policy.all(Policy.surface(""), Policy.forgetExempt("")))
            ORDER BY id
            """)
        var tokensById: [String: Set<String>] = [:]
        var summaryById: [String: String?] = [:]
        
        for row in rows {
            let id: String = row["id"]
            let title: String = row["title"]
            let summary = row["summary"] as String?
            let relativePath: String = row["path"]
            let bodyPath = Paths.brainRoot.appendingPathComponent(relativePath)
            let body: String
            do {
                body = try Notes.requireNote(at: bodyPath).body
            } catch is NoteUnreadable {
                continue
            }
            
            tokensById[id] = nearDupTokens(title + " " + (summary ?? "") + " " + body)
            summaryById[id] = summary
        }
        
        var seen: Set<String> = []
        var duplicates: [NearDuplicate] = []
        
        for row in rows {
            let id: String = row["id"]
            let axis: String = row["axis"]
            let title: String = row["title"]
            let summary = row["summary"] as String?
            
            guard let ownTokens = tokensById[id] else { continue }
            
            let neighborScores: [NeighborScore]
            do {
                neighborScores = try neighbors(db, noteId: id, k: 3)
            } catch is NoteUnreadable {
                continue
            }
            
            for neighbor in neighborScores {
                if neighbor.fts < minFts { continue }
                if id == neighbor.id { continue }
                
                let key = id < neighbor.id ? "\(id)|\(neighbor.id)" : "\(neighbor.id)|\(id)"
                
                if seen.contains(key) { continue }
                
                guard let neighborTokens = tokensById[neighbor.id] else { continue }
                
                let intersection = ownTokens.intersection(neighborTokens).count
                let union = ownTokens.union(neighborTokens).count
                let minSize = min(ownTokens.count, neighborTokens.count)
                
                if union == 0 || minSize == 0 { continue }
                
                let jaccard = Double(intersection) / Double(union)
                let containment = Double(intersection) / Double(minSize)
                
                if jaccard < minJaccard && containment < minContainment { continue }
                
                seen.insert(key)
                
                duplicates.append(
                    NearDuplicate(
                        a: .init(id: id, axis: axis, title: title, summary: summary),
                        b: .init(
                            id: neighbor.id,
                            axis: neighbor.axis,
                            title: neighbor.title,
                            summary: summaryById[neighbor.id] ?? nil
                        ),
                        fts: round(neighbor.fts * 1000) / 1000,
                        entity: round(neighbor.entity * 1000) / 1000,
                        link: round(neighbor.link * 1000) / 1000,
                        jaccard: round(jaccard * 1000) / 1000,
                        containment: round(containment * 1000) / 1000
                    )
                )
            }
        }
        
        duplicates.sort { lhs, rhs in
            if lhs.fts != rhs.fts { return lhs.fts > rhs.fts }
            
            if lhs.a.id != rhs.a.id { return lhs.a.id < rhs.a.id }
            
            return lhs.b.id < rhs.b.id
        }
        
        return Array(duplicates.prefix(limit))
    }
    
    // MARK: - Private
    private static func sectionSketch(_ db: Database, nid: String) throws -> [SectionSketch] {
        guard let relativePath = try String.fetchOne(
            db,
            sql: "SELECT path FROM notes WHERE id = ?",
            arguments: [nid]
        ) else {
            return []
        }
        
        let path = Paths.brainRoot.appendingPathComponent(relativePath)
        let (_, body) = try Notes.requireNote(at: path)
        let sections = SectionEdit.splitSections(body)
        let lines = body.unicodeLines()
        var sketches: [SectionSketch] = []
        
        for section in sections where section.level == 2 {
            let bodyLines = Array(lines[(section.lineStart + 1)..<section.lineEnd])
            let wordCount = SectionEdit.wordCount(bodyLines.joined(separator: "\n"))
            
            sketches.append(
                SectionSketch(
                    path: "\(String(repeating: "#", count: section.level)) \(section.title)",
                    title: section.title,
                    wordCount: wordCount
                )
            )
        }
        
        return sketches
    }
    
    private static func flagged(
        _ db: Database,
        flag: String,
        limit: Int
    ) throws -> [FlaggedCandidate] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT r.note_id, r.reason, r.created_at, n.axis, n.title, n.summary
            FROM ripple_flags r
            JOIN notes n ON n.id = r.note_id
            WHERE r.flag = ? AND r.resolved_at IS NULL
              AND \(Policy.surface())
            ORDER BY r.created_at ASC, r.note_id ASC
            LIMIT ?
            """, arguments: [flag, limit])
        
        return rows.map { row in
            FlaggedCandidate(
                id: row["note_id"],
                reason: row["reason"] as String?,
                createdAt: row["created_at"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?
            )
        }
    }
    
    private static func pairKey(_ left: String, _ right: String) -> String {
        left < right ? "\(left)|\(right)" : "\(right)|\(left)"
    }
    
    private static func clusterEdges(
        _ db: Database,
        memberIds: [String]
    ) throws -> [Cluster.Edge] {
        if memberIds.count < 2 { return [] }
        
        let memberSet = Set(memberIds)
        var edgesMap: [String: (Double, Double, Double)] = [:]
        
        func key(_ left: String, _ right: String) -> String {
            left < right ? "\(left)|\(right)" : "\(right)|\(left)"
        }
        
        for memberId in memberIds {
            let neighborScores: [NeighborScore]
            do {
                neighborScores = try neighbors(
                    db,
                    noteId: memberId,
                    k: max(memberIds.count, 30)
                )
            } catch is NoteUnreadable {
                continue
            }
            
            for neighbor in neighborScores where memberSet.contains(neighbor.id) {
                let pair = key(memberId, neighbor.id)
                let candidate = (neighbor.fts, neighbor.entity, neighbor.link)
                
                if let current = edgesMap[pair] {
                    if candidate.0 + candidate.1 + candidate.2
                        > current.0 + current.1 + current.2 {
                        edgesMap[pair] = candidate
                    }
                } else {
                    edgesMap[pair] = candidate
                }
            }
        }
        
        var edges: [Cluster.Edge] = []
        
        for (pair, score) in edgesMap where !(score.0 == 0 && score.1 == 0 && score.2 == 0) {
            let parts = pair.split(separator: "|").map(String.init)
            
            edges.append(
                Cluster.Edge(
                    a: parts[0],
                    b: parts[1],
                    fts: round(score.0 * 1000) / 1000,
                    entity: round(score.1 * 1000) / 1000,
                    link: round(score.2 * 1000) / 1000
                )
            )
        }
        
        edges.sort { lhs, rhs in
            let leftTotal = lhs.fts + lhs.entity + lhs.link
            let rightTotal = rhs.fts + rhs.entity + rhs.link
            
            if leftTotal != rightTotal { return leftTotal > rightTotal }
            
            return (lhs.a, lhs.b) < (rhs.a, rhs.b)
        }
        
        return edges
    }
    
    private static func bm25Neighbors(
        _ db: Database,
        noteId: String,
        limit: Int,
        maxBm25: Double
    ) throws -> [(String, Double)] {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT title, path FROM notes WHERE id = ?",
            arguments: [noteId]
        ) else {
            return []
        }
        
        let title: String = row["title"]
        let relativePath: String = row["path"]
        let url = Paths.brainRoot.appendingPathComponent(relativePath)
        let body = try Notes.requireNote(at: url).body
        let searchText = "\(title) \(body)"
        let nsSearchText = searchText as NSString
        var tokens = Set<String>()
        
        wordRegex.enumerateMatches(
            in: searchText,
            range: NSRange(location: 0, length: nsSearchText.length)
        ) { match, _, _ in
            guard let match else { return }
            
            tokens.insert(nsSearchText.substring(with: match.range).lowercased())
        }
        
        guard !tokens.isEmpty else { return [] }
        
        let matchExpr = tokens.sorted().map { token in "\"\(token)\"" }.joined(separator: " OR ")
        let rows = (try? Row.fetchAll(db, sql: """
            SELECT n.id AS id, MIN(rank) AS s
            FROM notes_fts f JOIN notes n ON n.id = f.id
            WHERE notes_fts MATCH ? AND n.id != ? AND \(Policy.all(Policy.surface(), Policy.notEager()))
            GROUP BY n.id
            ORDER BY s, n.id LIMIT ?
            """, arguments: [matchExpr, noteId, limit * 3])) ?? []
        var hits: [(String, Double)] = []
        
        for row in rows {
            let score: Double = row["s"]
            
            if score <= maxBm25 { hits.append((row["id"], score)) }
        }
        
        return Array(hits.prefix(limit))
    }
    
    private static func nearDupTokens(_ text: String) -> Set<String> {
        let nsText = text as NSString
        var tokens = Set<String>()
        
        wordRegex.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match else { return }
            
            tokens.insert(nsText.substring(with: match.range).lowercased())
        }
        
        return tokens
    }
}
