//
//  ExpandedNote.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct ExpandedNote: Sendable {
    // MARK: - Property
    public let id: String
    public let title: String
    public let summary: String?
    public let weight: Double
    public let rankWeight: Double

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
