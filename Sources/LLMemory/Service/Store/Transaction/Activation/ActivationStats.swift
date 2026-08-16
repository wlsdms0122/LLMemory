//
//  ActivationStats.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Activation transactions — succession of raw retrieval events into the
// persistent traces (activity_windows / retrieval_hits) and their
// observation.
public struct ActivationStats: Encodable, Sendable {
    public struct PrefixRow: Encodable, Sendable {
        // MARK: - Property
        public let prefix: String
        public let surfaced: Int
        public let used: Int

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    public let windows: Int
    public let labeledWindows: Int
    public let surfaced: Int
    public let used: Int
    public let byPrefix: [PrefixRow]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
