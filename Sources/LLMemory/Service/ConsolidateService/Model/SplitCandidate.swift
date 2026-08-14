//
//  SplitCandidate.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct SplitCandidate: Sendable {
    // MARK: - Property
    public let id: String
    public let title: String
    public let wordCount: Int
    public let sectionCount: Int
    public let tagCount: Int
    public let sections: [SectionSketch]
    public let reason: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
