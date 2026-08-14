//
//  LintSeverity.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// How loudly a rule speaks: an error is an integrity violation and is not a
// matter of opinion; a warn is a request for judgement and can be answered.
enum LintSeverity: String {
    case error
    case warn
}
