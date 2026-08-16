//
//  TemplateDriftRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct TemplateDriftRule: NoteDBLintRule {
    // MARK: - Property
    let code = "template-drift"
    let severity = LintSeverity.warn
    
    private let template = Template()
    
    private let frames = TemplateFrames()
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope, _ brain: BrainContext, note: NoteLintInput) throws -> [LintFinding] {
        guard let templateId = note.doc.template, !templateId.isEmpty else { return [] }
        
        guard let frame = try frames.frame(scope, brain, templateId: templateId) else {
            return [.init("template note '\(templateId)' not found — cannot validate frame")]
        }
        
        if let violation = template.validate(documentBody: note.body, frame: frame) {
            return [.init("body diverges from template '\(templateId)' frame: \(violation)")]
        }
        
        return []
    }
    
    // MARK: - Private
}
