//
//  EventLogTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Replays the retention-window retrieval log — the offline-reranking input
// for genome shadow runs.
struct FetchLoggedRetrievalQueriesTransaction: GRDBTransaction {
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

    // MARK: - Property
    let limit: Int

    // MARK: - Initializer
    init(limit: Int) {
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [LoggedQuery] {
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

    // MARK: - Private
}
