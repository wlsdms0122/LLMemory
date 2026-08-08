//
//  GenomeFeature.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum GenomeFeature {
    public struct ShadowResult: Encodable {
        public struct QueryDiff: Encodable {
            // MARK: - Property
            public let query: String
            public let baseline: [String]
            public let candidate: [String]
            public let entered: [String]
            public let dropped: [String]
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        enum CodingKeys: String, CodingKey {
            case gene
            case baselineValue = "baseline_value"
            case candidateValue = "candidate_value"
            case queriesReplayed = "queries_replayed"
            case queriesChanged = "queries_changed"
            case diffs
        }
        
        // MARK: - Property
        public let gene: String
        public let baselineValue: Double
        public let candidateValue: Double
        public let queriesReplayed: Int
        public let queriesChanged: Int
        public let diffs: [QueryDiff]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func prepare(_ home: String) throws -> any DatabaseWriter {
        Session.configure(home: home)
        
        return try GRDBStorage.session.connect()
    }
    
    public static func list(home: String) throws -> [Genome.ListRow] {
        _ = try prepare(home)
        
        return Genome.list()
    }
    
    public static func history(
        home: String,
        gene: String?,
        limit: Int
    ) throws -> [Genome.HistoryRow] {
        let queue = try prepare(home)
        
        return try queue.read { db in
            try Genome.history(db, geneId: gene, limit: limit)
        }
    }
    
    public static func shadow(
        home: String,
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) throws -> ShadowResult {
        let queue = try prepare(home)
        
        guard let definition = Genome.gene(gene) else {
            throw Genome.WriteError.unknownGene(gene)
        }
        
        guard value >= definition.min && value <= definition.max else {
            throw Genome.WriteError.outOfBounds(gene, value, definition)
        }
        
        let baselineValue = Genome.double(gene)
        
        struct LoggedQuery {
            // MARK: - Property
            let command: String
            let text: String
            let axis: String?
            let limit: Int
            let sessionId: String?
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        let logged: [LoggedQuery] = try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT payload, session_id FROM events WHERE kind = 'retrieval'
                ORDER BY id DESC LIMIT ?
                """, arguments: [limit * 4])
            var queries: [LoggedQuery] = []
            
            for row in rows {
                guard let raw = row["payload"] as String?,
                    let data = raw.data(using: .utf8),
                    let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let command = payload["cmd"] as? String
                else {
                    continue
                }
                
                let sessionId: String? = row["session_id"]
                
                if command == "search", let text = payload["query"] as? String, !text.isEmpty {
                    queries.append(
                        LoggedQuery(
                            command: "search",
                            text: text,
                            axis: payload["axis"] as? String,
                            limit: payload["limit"] as? Int ?? 5,
                            sessionId: sessionId
                        )
                    )
                } else if command == "related", let text = payload["text"] as? String, !text.isEmpty {
                    queries.append(
                        LoggedQuery(
                            command: "related",
                            text: text,
                            axis: nil,
                            limit: 5,
                            sessionId: sessionId
                        )
                    )
                }
                
                if queries.count >= limit { break }
            }
            
            return queries
        }
        
        func replayIds(_ loggedQuery: LoggedQuery) throws -> [String] {
            switch loggedQuery.command {
            case "search":
                return try queue.read { db in
                    try Search.fts(
                        db,
                        query: loggedQuery.text,
                        axis: loggedQuery.axis,
                        limit: loggedQuery.limit,
                        sessionId: loggedQuery.sessionId
                    ).map { hit in hit.id }
                }
            
            default:
                let snapshot = try Framing.snapshot(
                    userInput: loggedQuery.text,
                    agentOutput: "",
                    sessionId: loggedQuery.sessionId,
                    dryRun: true
                )
                
                return snapshot.similar.map { note in note.id }
                    + snapshot.linked.map { note in note.id }
                    + snapshot.vectorLinked.map { note in note.id }
            }
        }
        
        var diffs: [ShadowResult.QueryDiff] = []
        var changed = 0
        
        for loggedQuery in logged {
            let baseline = try replayIds(loggedQuery)
            let candidate = try Genome.withOverride(gene, value) { try replayIds(loggedQuery) }
            
            if baseline != candidate {
                changed += 1
                
                if diffs.count < sampleDiffs {
                    let baselineIds = Set(baseline)
                    let candidateIds = Set(candidate)
                    
                    diffs.append(
                        ShadowResult.QueryDiff(
                            query: "\(loggedQuery.command): \(loggedQuery.text)",
                            baseline: baseline,
                            candidate: candidate,
                            entered: candidate.filter { id in !baselineIds.contains(id) },
                            dropped: baseline.filter { id in !candidateIds.contains(id) }
                        )
                    )
                }
            }
        }
        
        return ShadowResult(
            gene: gene,
            baselineValue: baselineValue,
            candidateValue: value,
            queriesReplayed: logged.count,
            queriesChanged: changed,
            diffs: diffs
        )
    }
    
    // MARK: - Private
}
