//
//  FieldTypeError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct FieldTypeError: Error, CustomStringConvertible {
    // MARK: - Property
    let field: String
    let expected: String
    let got: Any
    
    var description: String {
        "field '\(field)' must be a \(expected), got \(type(of: got)): \(got)"
    }
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
