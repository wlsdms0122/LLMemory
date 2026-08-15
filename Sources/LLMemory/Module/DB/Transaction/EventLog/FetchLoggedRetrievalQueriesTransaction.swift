//
//  FetchLoggedRetrievalQueriesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Replays the retention-window retrieval log — the offline-reranking input
// for genome shadow runs.
struct FetchLoggedRetrievalQueriesTransaction: GRDBReadTransaction {
    struct LoggedQuery {
        // Which retrieval to re-run, carrying the inputs that belong to it
        // alone. Text and the session are common ground; tags and a limit
        // are search's, and were being filled with stand-in values on the
        // related path where they mean nothing.
        enum Replay {
            case search(tags: [String], limit: Int)
            case related

            var command: RetrievalCommand {
                switch self {
                case .search: .search
                case .related: .related
                }
            }
        }

        // MARK: - Property
        let replay: Replay
        let text: String
        let sessionId: SessionId?

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
            SELECT payload, session_id FROM events WHERE kind = ?
            ORDER BY id DESC LIMIT ?
            """, arguments: [EventKind.retrieval.rawValue, limit * 4])
        var queries: [LoggedQuery] = []

        for row in rows {
            guard let raw = row["payload"] as String?,
                let data = raw.data(using: .utf8),
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let raw = payload["cmd"] as? String
            else {
                continue
            }

            let sessionId = SessionId(row["session_id"])

            // neighbors and get log no query text, so there is nothing of
            // theirs to run again — they fall through unrecognised, as does
            // a command written by a binary this one does not know.
            switch RetrievalCommand(rawValue: raw) {
            case .search:
                guard let text = payload["query"] as? String, !text.isEmpty else { continue }

                queries.append(
                    LoggedQuery(
                        replay: .search(
                            tags: payload["tags"] as? [String] ?? [],
                            limit: payload["limit"] as? Int ?? 5
                        ),
                        text: text,
                        sessionId: sessionId
                    )
                )

            case .related:
                guard let text = payload["text"] as? String, !text.isEmpty else { continue }

                queries.append(LoggedQuery(replay: .related, text: text, sessionId: sessionId))

            case .neighbors, .get, nil:
                continue
            }

            if queries.count >= limit { break }
        }

        return queries
    }

    // MARK: - Private
}
