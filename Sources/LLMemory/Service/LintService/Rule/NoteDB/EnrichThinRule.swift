//
//  EnrichThinRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct EnrichThinRule: NoteDBLintRule {
    // MARK: - Property
    let code = "enrich-thin"
    let severity = LintSeverity.warn
    
    private static let longIdentRegex = try! NSRegularExpression(pattern: #"[A-Za-z]{12,}"#)
    private static let camelHumpRegex = try! NSRegularExpression(pattern: #"[a-z][A-Z]"#)
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope, note: NoteLintInput) throws -> [LintFinding] {
        let haystack = "\(note.doc.title)\n\(note.body)"
        
        guard hasHangul(haystack) else { return [] }
        
        let compounds = hiddenCompounds(haystack)
        
        guard !compounds.isEmpty else { return [] }
        
        let active = try scope.run(CountActiveRetrievalTermsTransaction(noteId: note.nid))
        
        guard active == 0 else { return [] }
        
        let sample = compounds.prefix(5).joined(separator: ", ")
        let more = compounds.count > 5 ? " +\(compounds.count - 5) more" : ""
        
        return [
            .init(
                "Korean body + 0 active aliases + \(compounds.count) CamelCase identifier(s) unreachable by keyword search: \(sample)\(more)"
            )
        ]
    }
    
    // MARK: - Private
    private static let hangulRegex = try! NSRegularExpression(pattern: #"[가-힣]"#)

    // Korean text is what the alias/cue vocabulary is thin against — the
    // particle-agglutinating half of the corpus is where a lexical index
    // misses most, so the rule only speaks where that half is present.
    private func hasHangul(_ text: String) -> Bool {
        let nsText = text as NSString

        return Self.hangulRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) != nil
    }

    private func hiddenCompounds(_ text: String) -> [String] {
        let nsText = text as NSString
        var found: [String] = []
        var seen = Set<String>()

        Self.longIdentRegex.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match else { return }

            let token = nsText.substring(with: match.range)
            let nsToken = token as NSString

            if Self.camelHumpRegex.firstMatch(
                in: token,
                range: NSRange(location: 0, length: nsToken.length)
            ) != nil, seen.insert(token).inserted {
                found.append(token)
            }
        }

        return found
    }
}
