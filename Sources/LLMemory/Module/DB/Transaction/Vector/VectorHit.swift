//
//  VectorHit.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct VectorHit: Sendable {
    // MARK: - Property
    public let id: String
    public let title: String
    public let summary: String?
    public let path: String
    public let score: Double

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
