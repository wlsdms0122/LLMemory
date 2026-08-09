//
//  GeneShadowTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct GeneShadowTransaction: LegacyReadTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Internal
    // Sync body — also the direct surface for synchronous unit tests.
    func perform(_ connection: Connection) throws -> Result {
        guard let definition = Genome.gene(parameter.gene) else {
            throw GenomeService.WriteError.unknownGene(parameter.gene)
        }
        
        guard parameter.value >= definition.min && parameter.value <= definition.max else {
            throw GenomeService.WriteError.outOfBounds(parameter.gene, parameter.value, definition)
        }
        
        let baselineValue = Genome.double(parameter.gene)
        
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
        
        let logged: [LoggedQuery] = try connection.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT payload, session_id FROM events WHERE kind = 'retrieval'
                ORDER BY id DESC LIMIT ?
                """, arguments: [parameter.limit * 4])
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
                
                if queries.count >= parameter.limit { break }
            }
            
            return queries
        }
        
        func replayIds(_ loggedQuery: LoggedQuery) throws -> [String] {
            switch loggedQuery.command {
            case "search":
                return try connection.read { db in
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
                    connection,
                    userInput: loggedQuery.text,
                    agentOutput: "",
                    sessionId: loggedQuery.sessionId
                )
                
                return snapshot.similar.map { note in note.id }
                    + snapshot.linked.map { note in note.id }
                    + snapshot.vectorLinked.map { note in note.id }
            }
        }
        
        var diffs: [GenomeService.ShadowResult.QueryDiff] = []
        var changed = 0
        
        for loggedQuery in logged {
            let baseline = try replayIds(loggedQuery)
            let candidate = try Genome.withOverride(parameter.gene, parameter.value) { try replayIds(loggedQuery) }
            
            if baseline != candidate {
                changed += 1
                
                if diffs.count < parameter.sampleDiffs {
                    let baselineIds = Set(baseline)
                    let candidateIds = Set(candidate)
                    
                    diffs.append(
                        GenomeService.ShadowResult.QueryDiff(
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
        
        return GenomeService.ShadowResult(
            gene: parameter.gene,
            baselineValue: baselineValue,
            candidateValue: parameter.value,
            queriesReplayed: logged.count,
            queriesChanged: changed,
            diffs: diffs
        )
    }
}

public extension GeneShadowTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let gene: String
        public let value: Double
        public let limit: Int
        public let sampleDiffs: Int

        // MARK: - Initializer
        public init(gene: String, value: Double, limit: Int, sampleDiffs: Int) {
            self.gene = gene
            self.value = value
            self.limit = limit
            self.sampleDiffs = sampleDiffs
        }
    }

    typealias Result = GenomeService.ShadowResult
}
