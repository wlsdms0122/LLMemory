//
//  TemplateFrames.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation

// The heading frame a template note declares.
//
// Two questions, one from each side: the database says whether the brain has
// such a note, the file says what shape it asks for. Neither can answer the
// other's, which is why this sits above both rather than inside a transaction
// that would have to open a file to finish its answer.
struct TemplateFrames {
    // MARK: - Property
    private let template = Template()
    private let frontmatter = Frontmatter()

    // MARK: - Initializer
    // MARK: - Public
    // nil when no such template note exists. A note that exists but cannot be
    // read throws — a template silently treated as frameless would let every
    // note that follows it drift unreported.
    func frame(
        _ scope: GRDBReadScope,
        _ brain: BrainContext,
        templateId: String
    ) throws -> [TemplateFrameNode]? {
        guard let file = try brain.notePath(scope, templateId) else { return nil }

        let (_, body) = try frontmatter.parse(try String(contentsOf: file, encoding: .utf8))

        return template.parseFrame(body)
    }

    // MARK: - Private
}
