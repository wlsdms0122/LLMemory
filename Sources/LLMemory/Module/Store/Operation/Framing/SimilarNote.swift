//
//  SimilarNote.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct SimilarNote: Sendable {
    // MARK: - Property
    public let id: String
    public let title: String
    public let summary: String?
    public let tags: [String]
    public let section: String?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
