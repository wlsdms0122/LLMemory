//
//  FetchConfigValueTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// meta-table access for services — Config owns the key encoding.
struct FetchConfigValueTransaction: GRDBReadTransaction {
    // MARK: - Property
    let key: String
    let defaultValue: String

    // MARK: - Initializer
    init(key: String, default defaultValue: String) {
        self.key = key
        self.defaultValue = defaultValue
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> String {
        Config.getStringTx(key, default: defaultValue, txDB: db)
    }

    // MARK: - Private
}
