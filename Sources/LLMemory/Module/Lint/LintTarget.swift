//
//  LintTarget.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public enum LintTarget: Equatable, Hashable {
    case note(String)
    case corpus(String)
    
    public var scope: String {
        switch self {
        case .note:
            return "note"
        
        case .corpus:
            return "corpus"
        }
    }
    
    public var subject: String {
        switch self {
        case .note(let subject), .corpus(let subject):
            return subject
        }
    }
    
    var storageKey: String { "\(scope)\u{0}\(subject)" }
}
