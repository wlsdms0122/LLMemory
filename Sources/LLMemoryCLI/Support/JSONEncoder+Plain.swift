//
//  JSONEncoder+Plain.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The encoder every command's JSON goes through. Slashes are left unescaped
// because the output is read by people as often as by programs, and `\/` in a
// path is noise in both.
extension JSONEncoder {
    static let plain: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        
        return encoder
    }()
}
