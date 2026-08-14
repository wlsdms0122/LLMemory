//
//  NoteFrontmatter.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct NoteFrontmatter: Encodable, Sendable {
    // MARK: - Property
    private let doc: FrontmatterDoc

    // MARK: - Initializer
    init(_ doc: FrontmatterDoc) {
        self.doc = doc
    }

    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        try doc.encode(to: encoder)
    }

    // MARK: - Private
}
