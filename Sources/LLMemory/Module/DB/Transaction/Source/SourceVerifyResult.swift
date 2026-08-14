//
//  SourceVerifyResult.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// note_source transactions — projection, rebase, and drift verification of
// a note's declared source files. Hashing mechanics live in
// SourceFingerprint; these own the rows.
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
