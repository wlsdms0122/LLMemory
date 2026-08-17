//
//  VectorBuildResult.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// note_vectors operations — building the PPMI+SVD projection from the
// link graph and expanding by cosine neighborhood. The numerics live in
// VectorMath.
public struct VectorBuildResult: Sendable {
    // MARK: - Property
    public let noteCount: Int
    public let dim: Int
    public let builtAt: Int
    public let skipped: Bool
    public let reason: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
