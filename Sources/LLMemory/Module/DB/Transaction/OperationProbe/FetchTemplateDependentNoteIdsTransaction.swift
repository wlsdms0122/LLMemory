//
//  FetchTemplateDependentNoteIdsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchTemplateDependentNoteIdsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let templateIds: [String]

    // MARK: - Initializer
    init(templateIds: [String]) {
        self.templateIds = templateIds
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        guard !templateIds.isEmpty else { return [] }

        let placeholders = templateIds.map { _ in "?" }.joined(separator: ",")

        return try String.fetchAll(
            db,
            sql: "SELECT id FROM notes WHERE template IN (\(placeholders))",
            arguments: StatementArguments(templateIds)
        )
    }

    // MARK: - Private
}
