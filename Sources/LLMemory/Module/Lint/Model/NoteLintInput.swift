//
//  NoteLintInput.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct NoteLintInput {
    // MARK: - Property
    let nid: String
    // An `id:` the parser ignored, kept only so a rule can say it is there.
    let declaredId: String?
    let doc: FrontmatterDoc
    let body: String
    let document: LintDocument
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
