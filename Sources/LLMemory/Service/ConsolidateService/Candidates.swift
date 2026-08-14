//
//  Candidates.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

// The restructuring detector — what counts as a candidate (split shapes,
// stale flags, clusters, missing edges, near-duplicates) is decided here;
// row access rides candidate transactions in Module/DB.
//
// The Service tier's line: an XxxService instance is an effectful surface
// over storage (owns the async doors, gets wired by the container); a
// policy namespace like Candidates/Lint is pure judgment vocabulary over a
// scope — stateless, shared by whichever services need it (Consolidate
// dispatches batches, Retrieval scores neighbors).
public enum CandidatesError: Error, CustomStringConvertible {
    case unknownKind(String)

    public var description: String {
        switch self {
        case .unknownKind(let kind):
            return "unknown candidate kind: '\(kind)' — see candidateValidKinds"
        }
    }
}

public struct SplitCandidate: Sendable {
    // MARK: - Property
    public let id: String
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

public struct SectionSketch: Sendable {
    // MARK: - Property
    public let path: String
    public let title: String
    public let wordCount: Int
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct FlaggedCandidate: Sendable {
    // MARK: - Property
    public let id: String
    public let reason: String?
    public let createdAt: Int
    public let title: String
    public let summary: String?
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct NeighborScore: Sendable {
    // MARK: - Property
    public var id: String
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

// One note as a candidate-family member — shared by cluster, missing-edge
// and near-duplicate findings.
public struct CandidateMember: Sendable {
    // MARK: - Property
    public let id: String
    public let title: String
    public let summary: String?
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct CandidateCluster: Sendable {
    public struct Edge: Sendable {
        // MARK: - Property
        public let a: String
        public let b: String
        public let fts: Double
        public let entity: Double
        public let link: Double
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    public let size: Int
    public let members: [CandidateMember]
    public let edges: [Edge]
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct MissingEdge: Sendable {
    // MARK: - Property
    public let a: CandidateMember
    public let b: CandidateMember
    public let source: String
    public let score: Double
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct NearDuplicate: Sendable {
    // MARK: - Property
    public let a: CandidateMember
    public let b: CandidateMember
    public let fts: Double
    public let entity: Double
    public let link: Double
    public let jaccard: Double
    public let containment: Double
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public enum CandidateBatch: Sendable {
    case split([SplitCandidate])
    case flagged([FlaggedCandidate])
    case clusters([CandidateCluster])
    case missingEdge([MissingEdge])
    case nearDuplicate([NearDuplicate])
    
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

public struct Candidates: Sendable {
    // MARK: - Property
    private let sectionEdit = SectionEdit()
    private let noteFiles = Notes()
    private let vectorMath = VectorMath()
    private let dismissalPolicy = Dismissals()

    // The closed candidate vocabulary — the compiler owns exhaustiveness;
    // strings exist only at the API boundary.
    public enum Kind: String, CaseIterable, Sendable {
        case clusters
        case missingEdge = "missing_edge"
        case nearDuplicate = "near_duplicate"
        case split
        case reconsolidate
        case ripple
        case enrichReview = "enrich_review"

        public static let retrieval: [Kind] = [.clusters, .missingEdge, .nearDuplicate]
        public static let structural: [Kind] = [.split, .reconsolidate, .ripple, .enrichReview]
    }

    // MARK: - Property
    static let retrievalKinds: [String] = Kind.retrieval.map { kind in kind.rawValue }
    static let structuralKinds: [String] = Kind.structural.map { kind in kind.rawValue }
    
    static var validKinds: [String] { retrievalKinds + structuralKinds }
    
    private static let wordRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9가-힣]{3,}"#)
    
    // MARK: - Initializer
    // MARK: - Public
    func splitCandidates(_ scope: GRDBReadScope, limit: Int = 20) throws -> [SplitCandidate] {
        let minWords = Config.getInt("split.min_words", default: 400)
        let minSections = Config.getInt("split.min_sections", default: 4)
        let minTagDiversity = Config.getInt("split.min_tag_diversity", default: 3)
        let rows = try scope.run(
            FetchSplitShapeRowsTransaction(minWords: minWords, minSections: minSections)
        )
        let dismissals = try scope.run(FetchDismissalsByNoteTransaction(kind: "split"))
        let generation = try scope.run(FetchCandidateGenerationTransaction())
        var candidates: [SplitCandidate] = []
        
        for row in rows {
            if row.tagCount < minTagDiversity { continue }
            
            let verdict = dismissalPolicy.gate(
                dismissals[row.id],
                currentWords: row.wordCount,
                currentSections: row.sectionCount,
                globalGeneration: generation
            )
            
            if !verdict.surface { continue }
            
            let sections: [SectionSketch]
            do {
                sections = try sectionSketch(scope, nid: row.id)
            } catch is NoteUnreadable {
                continue
            }
            
            let base = "size=\(row.wordCount)w sections=\(row.sectionCount) tags=\(row.tagCount)"
            
            candidates.append(
                SplitCandidate(
                    id: row.id,
                    title: row.title,
                    wordCount: row.wordCount,
                    sectionCount: row.sectionCount,
                    tagCount: row.tagCount,
                    sections: sections,
                    reason: verdict.annotation.map { note in "\(base) · 재부상: \(note)" } ?? base
                )
            )
            
            if candidates.count >= limit { break }
        }
        
        return candidates
    }
    
    func reconsolidateCandidates(
        _ scope: GRDBReadScope,
        limit: Int = 20
    ) throws -> [FlaggedCandidate] {
        try flagged(scope, flag: "reconsolidate", limit: limit)
    }
    
    func rippleCandidates(_ scope: GRDBReadScope, limit: Int = 20) throws -> [FlaggedCandidate] {
        try flagged(scope, flag: "stale_ref", limit: limit)
    }
    
    func enrichReviewCandidates(
        _ scope: GRDBReadScope,
        limit: Int = 20
    ) throws -> [FlaggedCandidate] {
        try flagged(scope, flag: EnrichmentReview.flagKind, limit: limit)
    }
    
    func neighbors(_ scope: GRDBReadScope, noteId: String, k: Int = 10) throws -> [NeighborScore] {
        guard let anchor = try scope.run(FetchNoteAnchorTransaction(nid: noteId)) else {
            throw NotesError.unknownIds([noteId])
        }
        
        let body = try noteFiles.requireNote(at: anchor.path).body
        
        return try neighbors(scope, noteId: noteId, tokens: tokenize("\(anchor.title) \(body)"), k: k)
    }

    // The scoring core — private, so every outside caller passes the anchor
    // existence gate above; a caller that already holds the body hands the
    // derived tokens, and nothing re-reads a file or keeps its text alive.
    private func neighbors(
        _ scope: GRDBReadScope,
        noteId: String,
        tokens: Set<String>,
        k: Int
    ) throws -> [NeighborScore] {
        var scores: [String: NeighborScore] = [:]
        
        if !tokens.isEmpty {
            let tokenList = tokens.sorted()
            let matchExpr = tokenList.map { token in "\"\(token)\"" }.joined(separator: " OR ")
            // The match expression is derived text — an unparsable one is a
            // miss, not a failure (same contract as the inline try? before).
            let rows = (try? scope.run(
                SearchFTSNeighborRowsTransaction(matchExpr: matchExpr, excludeId: noteId)
            )) ?? []
            let total = max(rows.count, 1)
            
            for (rank, row) in rows.enumerated() {
                let normalized = 1.0 - Double(rank) / Double(total)
                var score = scores[row.id] ?? NeighborScore(
                    id: row.id,
                    title: row.title,
                    summary: row.summary,
                    fts: 0,
                    entity: 0,
                    link: 0,
                    score: 0
                )
                score.fts = normalized
                scores[row.id] = score
            }
        }
        
        let targetEntities = try scope.run(FetchNoteEntitySetTransaction(nid: noteId))
        
        if !targetEntities.isEmpty {
            let rows = try scope.run(FetchEntityOverlapRowsTransaction(nid: noteId))
            let targetSize = targetEntities.count
            
            for row in rows {
                if row.intersection == 0 { continue }
                
                let denominator = max(targetSize + row.size - row.intersection, 1)
                let jaccard = Double(row.intersection) / Double(denominator)
                var score = scores[row.id] ?? NeighborScore(
                    id: row.id,
                    title: row.title,
                    summary: row.summary,
                    fts: 0,
                    entity: 0,
                    link: 0,
                    score: 0
                )
                score.entity = jaccard
                scores[row.id] = score
            }
        }
        
        let linkRows = try scope.run(FetchLinkNeighborRowsTransaction(nid: noteId))
        
        if !linkRows.isEmpty {
            let maxWeight = linkRows.map { row in row.value }.max() ?? 1.0
            let normalizer = maxWeight == 0 ? 1.0 : maxWeight
            
            for row in linkRows {
                var score = scores[row.id] ?? NeighborScore(
                    id: row.id,
                    title: row.title,
                    summary: row.summary,
                    fts: 0,
                    entity: 0,
                    link: 0,
                    score: 0
                )
                score.link = row.value / normalizer
                scores[row.id] = score
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
    
    func clusters(
        _ scope: GRDBReadScope,
        minSize: Int = 2,
        maxSize: Int? = nil,
        limit: Int = 20
    ) throws -> [CandidateCluster] {
        let cap = maxSize ?? Config.getInt("candidates.cluster.max_size", default: 12)
        let edges = try scope.run(FetchClusterEdgesTransaction())
        
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
        
        var clusters: [CandidateCluster] = []
        
        for (_, members) in groups where members.count >= minSize && members.count <= cap {
            let rows = try scope.run(FetchClusterMemberRowsTransaction(ids: members))
            let memberStructs = rows.map { row in
                CandidateMember(
                    id: row.id,
                    title: row.title,
                    summary: row.summary
                )
            }
            let clusterEdges = try clusterEdges(scope, memberIds: members)
            
            clusters.append(
                CandidateCluster(
                    size: members.count,
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
    
    func missingEdges(
        _ scope: GRDBReadScope,
        limit: Int = 20,
        perNote: Int = 3,
        vecCos: Double? = nil,
        ftsBm25: Double? = nil
    ) throws -> [MissingEdge] {
        let cosineThreshold = vecCos ?? Genes.double("candidates.missing_edge.vec_cos")
        let bm25Threshold = ftsBm25 ?? Genes.double("candidates.missing_edge.fts_bm25")
        var linked = Set<String>()
        var degree: [String: Int] = [:]
        
        for pair in try scope.run(FetchSurfaceLinkPairsTransaction()) {
            linked.insert(pairKey(pair.src, pair.dst))
            degree[pair.src, default: 0] += 1
            degree[pair.dst, default: 0] += 1
        }
        
        var meta: [String: CandidateMember] = [:]
        
        for row in try scope.run(FetchSurfaceMetaRowsTransaction()) {
            meta[row.id] = CandidateMember(
                id: row.id,
                title: row.title,
                summary: row.summary
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
            let raw = try scope.run(FetchNoteVectorsTransaction())
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
                    
                    let cosine = vectorMath.cosine(anchorVector, otherVector)
                    
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
                    scope,
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
    
    func nearDuplicates(
        _ scope: GRDBReadScope,
        minFts: Double = 0.85,
        minJaccard: Double = 0.6,
        minContainment: Double = 0.85,
        limit: Int = 20
    ) throws -> [NearDuplicate] {
        let rows = try scope.run(FetchSurfaceNoteRowsTransaction())
        var tokensById: [String: Set<String>] = [:]
        var summaryById: [String: String?] = [:]
        var ftsTokensById: [String: Set<String>] = [:]
        
        for row in rows {
            let bodyPath = Paths.brainRoot.appendingPathComponent(row.path)
            let body: String
            do {
                body = try noteFiles.requireNote(at: bodyPath).body
            } catch is NoteUnreadable {
                continue
            }
            
            tokensById[row.id] = tokenize(row.title + " " + (row.summary ?? "") + " " + body)
            summaryById[row.id] = row.summary
            ftsTokensById[row.id] = tokenize("\(row.title) \(body)")
        }
        
        var seen: Set<String> = []
        var duplicates: [NearDuplicate] = []
        
        for row in rows {
            let id = row.id
            let title = row.title
            let summary = row.summary
            
            guard let ownTokens = tokensById[id],
                let ftsTokens = ftsTokensById[id]
            else {
                continue
            }
            
            let neighborScores = try neighbors(scope, noteId: id, tokens: ftsTokens, k: 3)
            
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
                        a: .init(id: id, title: title, summary: summary),
                        b: .init(
                            id: neighbor.id,
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
    private func sectionSketch(_ scope: GRDBReadScope, nid: String) throws -> [SectionSketch] {
        guard let path = try scope.run(FetchNotePathTransaction(nid: nid)) else {
            return []
        }
        let (_, body) = try noteFiles.requireNote(at: path)
        let sections = sectionEdit.splitSections(body)
        let lines = body.unicodeLines()
        var sketches: [SectionSketch] = []
        
        for section in sections where section.level == 2 {
            let bodyLines = Array(lines[(section.lineStart + 1)..<section.lineEnd])
            let wordCount = sectionEdit.wordCount(bodyLines.joined(separator: "\n"))
            
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
    
    private func flagged(
        _ scope: GRDBReadScope,
        flag: String,
        limit: Int
    ) throws -> [FlaggedCandidate] {
        try scope.run(FetchFlaggedRowsTransaction(flag: flag, limit: limit)).map { row in
            FlaggedCandidate(
                id: row.noteId,
                reason: row.reason,
                createdAt: row.createdAt,
                title: row.title,
                summary: row.summary
            )
        }
    }
    
    private func pairKey(_ left: String, _ right: String) -> String {
        left < right ? "\(left)|\(right)" : "\(right)|\(left)"
    }
    
    private func clusterEdges(
        _ scope: GRDBReadScope,
        memberIds: [String]
    ) throws -> [CandidateCluster.Edge] {
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
                    scope,
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
        
        var edges: [CandidateCluster.Edge] = []
        
        for (pair, score) in edgesMap where !(score.0 == 0 && score.1 == 0 && score.2 == 0) {
            let parts = pair.split(separator: "|").map(String.init)
            
            edges.append(
                CandidateCluster.Edge(
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
    
    private func bm25Neighbors(
        _ scope: GRDBReadScope,
        noteId: String,
        limit: Int,
        maxBm25: Double
    ) throws -> [(String, Double)] {
        guard let anchor = try scope.run(FetchNoteAnchorTransaction(nid: noteId)) else {
            return []
        }
        
        let title = anchor.title
        let body = try noteFiles.requireNote(at: anchor.path).body
        let searchText = "\(title) \(body)"
        let nsSearchText = searchText as NSString
        var tokens = Set<String>()
        
        Self.wordRegex.enumerateMatches(
            in: searchText,
            range: NSRange(location: 0, length: nsSearchText.length)
        ) { match, _, _ in
            guard let match else { return }
            
            tokens.insert(nsSearchText.substring(with: match.range).lowercased())
        }
        
        guard !tokens.isEmpty else { return [] }
        
        let matchExpr = tokens.sorted().map { token in "\"\(token)\"" }.joined(separator: " OR ")
        // Derived match text — an unparsable expression is a miss, not a
        // failure (same contract as the inline try? before).
        let rows = (try? scope.run(
            SearchBM25NeighborRowsTransaction(matchExpr: matchExpr, excludeId: noteId, limit: limit * 3)
        )) ?? []
        var hits: [(String, Double)] = []
        
        for row in rows where row.score <= maxBm25 {
            hits.append((row.id, row.score))
        }
        
        return Array(hits.prefix(limit))
    }
    
    private func tokenize(_ text: String) -> Set<String> {
        let nsText = text as NSString
        var tokens = Set<String>()
        
        Self.wordRegex.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match else { return }
            
            tokens.insert(nsText.substring(with: match.range).lowercased())
        }
        
        return tokens
    }
}

