//
//  DecayAndPruneLinksOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct DecayAndPruneLinksOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (Double, Double)
    let factor: Double
    let floor: Double

    // MARK: - Initializer
    init(factor: Double, floor: Double) {
        self.factor = factor
        self.floor = floor
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> (decayed: Int, pruned: Int) {
        let learned = LinkKind.rawValues { kind in kind.isLearned }
        let kindPlaceholders = Array(repeating: "?", count: learned.count).joined(separator: ",")
        let kinds = learned as [DatabaseValueConvertible?]

        try db.execute(
            sql: "UPDATE note_links SET weight = weight * ? WHERE kind IN (\(kindPlaceholders))",
            arguments: StatementArguments([factor as DatabaseValueConvertible?] + kinds)
        )

        let decayed = db.changesCount

        try db.execute(
            sql: "DELETE FROM note_links WHERE weight < ? AND kind IN (\(kindPlaceholders))",
            arguments: StatementArguments([floor as DatabaseValueConvertible?] + kinds)
        )

        let pruned = db.changesCount

        return (decayed, pruned)
    }

    // MARK: - Private
}
