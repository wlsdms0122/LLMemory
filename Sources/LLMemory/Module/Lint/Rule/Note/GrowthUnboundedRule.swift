//
//  GrowthUnboundedRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct GrowthUnboundedRule: NoteLintRule {
    // MARK: - Property
    let code = "growth-unbounded"
    let severity = LintSeverity.warn
    
    private static let datedHeadingRegex = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}"#
    )
    private static let periodIdRegex = try! NSRegularExpression(
        pattern: #"-\d{6}(-\d{2,6})?(-(am|pm))?$"#
    )
    
    private let sectionEdit = SectionEdit()
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        guard note.doc.template == nil, !note.doc.locked else { return [] }
        guard !matches(Self.periodIdRegex, note.nid) else { return [] }
        
        let dated = note.document.sections.filter { section in
            matches(Self.datedHeadingRegex, section.title)
        }
        let minEntries = index.config.getInt("lint.growth_min_dated_sections", default: 8)
        
        guard dated.count >= minEntries else { return [] }
        
        return [
            .init(
                "\(dated.count) dated sections (\(sectionEdit.wordCount(note.body)) words) — "
                    + "append-only buffer, so size tracks time not subject; roll to a new period note "
                    + "and keep an index of periods"
            )
        ]
    }
    
    // MARK: - Private
    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let nsText = text as NSString
        
        return regex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) != nil
    }
}
