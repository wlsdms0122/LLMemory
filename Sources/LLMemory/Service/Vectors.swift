//
//  Vectors.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import Accelerate

public enum Vectors {
    public struct BuildResult {
        // MARK: - Property
        public let noteCount: Int
        public let dim: Int
        public let builtAt: Int
        public let skipped: Bool
        public let reason: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct VectorHit {
        // MARK: - Property
        public let id: String
        public let axis: String
        public let title: String
        public let summary: String?
        public let path: String
        public let score: Double
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    // Caller holds the write lock (run's write marker or an explicit writeLock).
    @discardableResult
    static func build(_ queue: any DatabaseWriter) throws -> BuildResult {
        let now = Int(Date().timeIntervalSince1970)
        let noteIds: [String] = try queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT id FROM notes WHERE \(Policy.surface("")) ORDER BY id"
            )
        }
        let noteCount = noteIds.count
            
        if noteCount < 2 {
            return BuildResult(
                noteCount: noteCount,
                dim: 0,
                builtAt: now,
                skipped: true,
                reason: "too few notes (\(noteCount))"
            )
        }
            
        let dim = min(Config.getInt("vectors.dim", default: 48), noteCount - 1)
        var indexById: [String: Int] = [:]
            
        for (index, id) in noteIds.enumerated() { indexById[id] = index }
            
        var matrix = [Double](repeating: 0, count: noteCount * noteCount)
            
        try queue.read { db in
            let links = try Row.fetchAll(db, sql: "SELECT src, dst, weight FROM note_links")
                
            for link in links {
                guard let source = indexById[link["src"] as String],
                    let destination = indexById[link["dst"] as String]
                else {
                    continue
                }
                    
                let weight: Double = link["weight"]
                matrix[source * noteCount + destination] += weight
                matrix[destination * noteCount + source] += weight
            }
                
            var tagsOf: [Int: Set<String>] = [:]
            let tagRows = try Row.fetchAll(db, sql: "SELECT note_id, tag FROM tags")
                
            for row in tagRows {
                guard let index = indexById[row["note_id"] as String] else { continue }
                    
                tagsOf[index, default: []].insert(row["tag"])
            }
                
            for left in 0..<noteCount {
                guard let leftTags = tagsOf[left], !leftTags.isEmpty else { continue }
                    
                for right in (left + 1)..<noteCount {
                    guard let rightTags = tagsOf[right], !rightTags.isEmpty else { continue }
                        
                    let intersection = leftTags.intersection(rightTags).count
                        
                    if intersection == 0 { continue }
                        
                    let jaccard = Double(intersection) / Double(leftTags.union(rightTags).count)
                    let floor = jaccard * 0.3
                        
                    if matrix[left * noteCount + right] < floor {
                        matrix[left * noteCount + right] = floor
                        matrix[right * noteCount + left] = floor
                    }
                }
            }
        }
            
        let ppmi = computePPMI(matrix, n: noteCount)
        let projection = try truncatedSVD(ppmi, n: noteCount, k: dim)
            
        try queue.write { db in
            try db.execute(sql: "DELETE FROM note_vectors")
                
            for (index, id) in noteIds.enumerated() {
                var vector = [Float](repeating: 0, count: dim)
                    
                for component in 0..<dim {
                    vector[component] = Float(projection[index * dim + component])
                }
                    
                let blob = vector.withUnsafeBufferPointer { buffer in Data(buffer: buffer) }
                    
                try db.execute(sql: """
                    INSERT INTO note_vectors (note_id, dim, vec, built_at)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [id, dim, blob, now])
            }
                
            for (key, value) in [
                ("vectors.built_at", String(now)),
                ("vectors.dim", String(dim)),
                ("vectors.model", "ppmi-svd")
            ] {
                try db.execute(sql: """
                    INSERT INTO meta (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """, arguments: [key, value])
            }
        }
            
        return BuildResult(
            noteCount: noteCount,
            dim: dim,
            builtAt: now,
            skipped: false,
            reason: ""
        )

    }
    
    static func computePPMI(_ matrix: [Double], n: Int) -> [Double] {
        var rowSum = [Double](repeating: 0, count: n)
        var total = 0.0
        
        for row in 0..<n {
            var sum = 0.0
            
            for column in 0..<n { sum += matrix[row * n + column] }
            
            rowSum[row] = sum
            total += sum
        }
        
        if total <= 0 { return [Double](repeating: 0, count: n * n) }
        
        var ppmi = [Double](repeating: 0, count: n * n)
        
        for row in 0..<n {
            if rowSum[row] <= 0 { continue }
            
            for column in 0..<n {
                let cell = matrix[row * n + column]
                
                if cell <= 0 { continue }
                
                let pointwise = log((cell * total) / (rowSum[row] * rowSum[column]))
                ppmi[row * n + column] = max(0, pointwise)
            }
        }
        
        return ppmi
    }
    
    static func truncatedSVD(_ matrix: [Double], n: Int, k: Int) throws -> [Double] {
        var columnMajor = matrix
        var rowCount = __CLPK_integer(n)
        var columnCount = __CLPK_integer(n)
        var lda = __CLPK_integer(n)
        var singularValues = [Double](repeating: 0, count: n)
        var leftVectors = [Double](repeating: 0, count: n * n)
        var ldu = __CLPK_integer(n)
        var rightVectors = [Double](repeating: 0, count: n * n)
        var ldvt = __CLPK_integer(n)
        var jobu = Int8(UInt8(ascii: "A"))
        var jobvt = Int8(UInt8(ascii: "N"))
        var info = __CLPK_integer(0)
        var workQuery = Double(0)
        var lwork = __CLPK_integer(-1)
        
        dgesvd_(
            &jobu, &jobvt, &rowCount, &columnCount, &columnMajor, &lda,
            &singularValues, &leftVectors, &ldu, &rightVectors, &ldvt,
            &workQuery, &lwork, &info
        )
        
        lwork = __CLPK_integer(max(1, Int(workQuery)))
        
        var work = [Double](repeating: 0, count: Int(lwork))
        
        dgesvd_(
            &jobu, &jobvt, &rowCount, &columnCount, &columnMajor, &lda,
            &singularValues, &leftVectors, &ldu, &rightVectors, &ldvt,
            &work, &lwork, &info
        )
        
        if info != 0 {
            throw VectorsError.svdFailed(info: Int(info))
        }
        
        var projection = [Double](repeating: 0, count: n * k)
        
        for row in 0..<n {
            for component in 0..<k {
                projection[row * k + component] = leftVectors[component * n + row]
                    * singularValues[component]
            }
        }
        
        return projection
    }
    
    static func expand(
        _ queue: any DatabaseWriter,
        seedIds: [String],
        limit: Int = 10,
        excludeIds: Set<String> = []
    ) throws -> [VectorHit] {
        guard !seedIds.isEmpty else { return [] }
        
        return try queue.read { db -> [VectorHit] in
            let vectors = try EnrichmentReview.loadVectors(db)
            
            guard !vectors.isEmpty else { return [] }
            
            let seedVectors = seedIds.compactMap { id in vectors[id] }
            
            guard !seedVectors.isEmpty else { return [] }
            
            let dim = seedVectors[0].count
            var centroid = [Double](repeating: 0, count: dim)
            
            for vector in seedVectors {
                for index in 0..<min(dim, vector.count) { centroid[index] += Double(vector[index]) }
            }
            
            for index in 0..<dim { centroid[index] /= Double(seedVectors.count) }
            
            let centroidVector = centroid.map { value in Float(value) }
            var excluded = excludeIds
            excluded.formUnion(seedIds)
            
            let inactive = try Set(String.fetchAll(db, sql: """
                SELECT id FROM notes WHERE \(Policy.notSurface(""))
                """))
            excluded.formUnion(inactive)
            
            var scored: [(id: String, score: Double)] = []
            
            for (id, vector) in vectors where !excluded.contains(id) {
                let similarity = EnrichmentReview.cosine(centroidVector, vector)
                
                if similarity > 0 { scored.append((id, similarity)) }
            }
            
            scored.sort { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.id < rhs.id
            }
            
            let top = scored.prefix(limit)
            
            guard !top.isEmpty else { return [] }
            
            let ids = top.map { hit in hit.id }
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, axis, title, summary, path FROM notes
                WHERE id IN (\(placeholders)) AND \(Policy.surface(""))
                """, arguments: StatementArguments(ids))
            var metaById: [String: Row] = [:]
            
            for row in rows { metaById[row["id"] as String] = row }
            
            return top.compactMap { hit -> VectorHit? in
                guard let row = metaById[hit.id] else { return nil }
                
                return VectorHit(
                    id: hit.id,
                    axis: row["axis"],
                    title: row["title"],
                    summary: row["summary"] as String?,
                    path: row["path"],
                    score: hit.score
                )
            }
        }
    }
    
    // MARK: - Private
}

enum VectorsError: Error, CustomStringConvertible {
    case svdFailed(info: Int)
    
    var description: String {
        switch self {
        case .svdFailed(let info):
            return "SVD failed (LAPACK dgesvd info=\(info))"
        }
    }
}
