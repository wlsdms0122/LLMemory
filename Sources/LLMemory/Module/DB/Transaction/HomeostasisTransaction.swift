//
//  HomeostasisTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct HomeostasisTransaction: LegacyWriteTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    private func perform(_ connection: Connection) throws -> Result {
        let now = Int(Date().timeIntervalSince1970)
        var report: Homeostasis.Report!

        try connection.write { db in
            _ = try DeriveActivityWindowsTransaction(now: now).perform(db)
            report = try Homeostasis.tick(db, now: now)
        }

        Events.record(
            connection,
            kind: Events.kindConsolidation,
            payload: [
                "action": "homeostasis",
                "windows_processed": report.windowsProcessed,
                "adjusted_gene": report.adjustedGene as Any?,
                "note": report.note
            ],
            ts: now
        )

        return report
    }
}

public extension HomeostasisTransaction {
    typealias Parameter = Void
    typealias Result = Homeostasis.Report
}
