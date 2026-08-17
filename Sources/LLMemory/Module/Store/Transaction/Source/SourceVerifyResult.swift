//
//  SourceVerifyResult.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// What one pass of SourceVerifier saw. The counts are of notes, not of
// files: a note whose declaration itself changed was rebased rather than
// judged, so it appears under rechecked and never under becameStale.
public struct SourceVerifyResult: Sendable {
    // MARK: - Property
    public var total: Int
    public var rechecked: Int
    public var stillFresh: Int
    public var becameStale: Int
    public var recovered: Int
    public var missing: Int
    public var unreadable: [String] = []

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
