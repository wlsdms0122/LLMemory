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
struct LoadTemplateFrameTransaction: GRDBBrainReadTransaction {
    // MARK: - Property
    let templateId: String

    private let template = Template()

    // MARK: - Initializer
    init(templateId: String) {
        self.templateId = templateId
    }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws -> [TemplateFrameNode]? {
        guard let (_, _, body) = try FetchNoteTransaction(nid: templateId).perform(db, brain)
        else {
            return nil
        }

        return template.parseFrame(body)
    }

    // MARK: - Private
}
