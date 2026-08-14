//
//  SetConfigValueTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

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
