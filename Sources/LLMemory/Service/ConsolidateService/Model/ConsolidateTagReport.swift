//
//  ConsolidateTagReport.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct ConsolidateTagReport: Encodable, Sendable {
    // MARK: - Property
    public let rare: [TagCount]
    public let unused: [String]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
