//
//  LinkEdge.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct LinkEdge {
    // MARK: - Property
    let other: String
    let kind: String
    let weight: Double
    let createdAt: Int
    let lastActivatedAt: Int
    let provenance: String?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
