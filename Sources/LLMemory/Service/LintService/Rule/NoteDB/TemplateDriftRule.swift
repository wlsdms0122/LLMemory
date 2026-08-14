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

    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope, note: NoteLintInput) throws -> [LintFinding] {
        guard let templateId = note.doc.template, !templateId.isEmpty else { return [] }
        
        guard let frame = try scope.run(LoadTemplateFrameTransaction(templateId: templateId)) else {
            return [.init("template note '\(templateId)' not found — cannot validate frame")]
        }
        
        if let violation = template.validate(documentBody: note.body, frame: frame) {
            return [.init("body diverges from template '\(templateId)' frame: \(violation)")]
        }
        
        return []
    }
    
    // MARK: - Private
}
