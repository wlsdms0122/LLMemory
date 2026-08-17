//
//  TemplateDriftRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct TemplateDriftRule: NoteDBLintRule {
    // MARK: - Property
    let code = "template-drift"
    let severity = LintSeverity.warn
    
    private let template = Template()
    
    private let frames = TemplateFrames()
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ db: Database, _ brain: BrainContext, note: NoteLintInput) throws -> [LintFinding] {
        guard let templateId = note.doc.template, !templateId.isEmpty else { return [] }
        
        guard let frame = try frames.frame(db, brain, templateId: templateId) else {
            return [.init("template note '\(templateId)' not found — cannot validate frame")]
        }
        
        if let violation = template.validate(documentBody: note.body, frame: frame) {
            return [.init("body diverges from template '\(templateId)' frame: \(violation)")]
        }
        
        return []
    }
    
    // MARK: - Private
}
