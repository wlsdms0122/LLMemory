//
//  GeneHistoryRow.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct GeneHistoryRow: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case geneId = "gene_id"
        case oldValue = "old_value"
        case newValue = "new_value"
        case cause, detail, ts
    }

    // MARK: - Property
    public let geneId: String
    public let oldValue: Double?
    public let newValue: Double
    public let cause: String
    public let detail: String?
    public let ts: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
