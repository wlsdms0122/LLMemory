//
//  MetaTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
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

struct SetConfigValueTransaction: GRDBTransaction {
    // MARK: - Property
    let key: String
    let value: String

    // MARK: - Initializer
    init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try Config.set(key, value: value, txDB: db)
    }

    // MARK: - Private
}
