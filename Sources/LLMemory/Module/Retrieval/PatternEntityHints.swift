//
//  PatternEntityHints.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public enum PatternEntityHints {
    // MARK: - Property
    private static let ticketRegex = try! NSRegularExpression(pattern: #"\b[A-Z][A-Z0-9]+-\d+\b"#)
    private static let titleCaseRegex = try! NSRegularExpression(
        pattern: #"\b[A-Z][a-z]+(?:\s[A-Z][a-z]+){0,3}\b"#
    )
    
    // MARK: - Initializer
    // MARK: - Public
    static func extractEntityHints(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        
        var seen = Set<String>()
        var hints: [String] = []
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        
        ticketRegex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            
            let hint = nsText.substring(with: match.range)
            
            if !seen.contains(hint) {
                seen.insert(hint)
                hints.append(hint)
            }
        }
        
        titleCaseRegex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            
            let hint = nsText.substring(with: match.range)
            
            if !seen.contains(hint) {
                seen.insert(hint)
                hints.append(hint)
            }
        }
        
        return Array(hints.prefix(20))
    }
    
    // MARK: - Private
}
