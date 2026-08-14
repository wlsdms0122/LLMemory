//
//  LoadTemplateFrameTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Loads a template note's body and parses its heading frame — nil when the
// template note does not exist.
struct LoadTemplateFrameTransaction: GRDBReadTransaction {
    // MARK: - Property
    let templateId: String

    private let template = Template()

    // MARK: - Initializer
    init(templateId: String) {
        self.templateId = templateId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [TemplateFrameNode]? {
        guard let (_, _, body) = try FetchNoteTransaction(nid: templateId).perform(db) else { return nil }

        return template.parseFrame(body)
    }

    // MARK: - Private
}
