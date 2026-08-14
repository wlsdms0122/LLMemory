//
//  FrontmatterError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

enum FrontmatterError: Error, CustomStringConvertible, Equatable {
    case missing
    case malformedList(key: String, value: String)
    case malformedSource(value: String)
    case malformedSourceElement(value: String, element: String)
    case malformedLine(line: String)
    
    var description: String {
        switch self {
        case .missing:
            return "frontmatter missing"
        
        case .malformedList(let key, let value):
            return "frontmatter list field '\(key)' must be bracketed (e.g. \(key): [a, b]) — got: \(value)"
        
        case .malformedSource(let value):
            return "frontmatter 'source' bracketed form must be a JSON array (e.g. source: [\"/abs/a.swift\"]) — got: \(value)"
        
        case .malformedSourceElement(let value, let element):
            return "frontmatter 'source' element must be a non-empty string or {\"path\": \"...\"} — got \(element) in: \(value)"
        
        case .malformedLine(let line):
            return "frontmatter line is not single-line 'key: value' form: \(line)"
        }
    }
}
