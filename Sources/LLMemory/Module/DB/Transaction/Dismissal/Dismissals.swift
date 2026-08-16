//
//  Dismissals.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct Dismissals: Sendable {
    struct Dismissal {
        // MARK: - Property
        let kind: String
        let dismissCount: Int
        let wordCount: Int
        let sectionCount: Int
        let generation: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Verdict {
        // MARK: - Property
        let surface: Bool
        let annotation: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let dismissibleKinds: Set<String> = ["split"]
    static let lintPrefix = "lint:"
    
    // MARK: - Initializer
    // MARK: - Public
    func lintKind(_ code: String, fingerprint: String? = nil) -> String {
        guard let fingerprint else { return Self.lintPrefix + code }
        
        return "\(Self.lintPrefix)\(code)#\(digest(fingerprint))"
    }
    
    func digest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        
        return String(hash, radix: 36)
    }
    
    func isLintKind(_ kind: String) -> Bool { kind.hasPrefix(Self.lintPrefix) }
    
    func lintFingerprint(of kind: String) -> String? {
        guard isLintKind(kind) else { return nil }
        
        let body = String(kind.dropFirst(Self.lintPrefix.count))
        
        guard let cut = body.firstIndex(of: "#") else { return nil }
        
        return String(body[body.index(after: cut)...])
    }
    
    func lintCode(of kind: String) -> String? {
        guard isLintKind(kind) else { return nil }
        
        let body = String(kind.dropFirst(Self.lintPrefix.count))
        
        guard let cut = body.firstIndex(of: "#") else { return body }
        
        return String(body[body.startIndex..<cut])
    }

    func lintLookupKey(_ target: LintTarget, _ kind: String) -> String {
        "\(target.storageKey)\u{0}\(kind)"
    }

    // Habituation grows the bar a re-opened finding has to clear, and by how
    // much is configuration — so it arrives with the question.
    func gate(
        _ dismissal: Dismissal?,
        config: Config,
        currentWords: Int,
        currentSections: Int,
        globalGeneration: Int
    ) -> Verdict {
        guard let dismissal else { return Verdict(surface: true, annotation: nil) }
        
        if dismissal.generation < globalGeneration {
            return Verdict(
                surface: true,
                annotation: "\(dismissal.dismissCount)회 기각됨 → corpus 재편으로 재개방"
            )
        }
        
        let growthFactor = max(1.0, config.getDouble("habituation.growth_factor", default: 1.5))
        let factor = pow(growthFactor, Double(max(dismissal.dismissCount - 1, 0)))
        let wordGrowth = max(0.0, config.getDouble("habituation.word_growth", default: 0.5))
            * factor
        let sectionGrowth = max(0.0, config.getDouble("habituation.section_growth", default: 2.0))
            * factor
        let baseWords = max(dismissal.wordCount, 1)
        let wordRatio = Double(currentWords) / Double(baseWords)
        let sectionDelta = currentSections - dismissal.sectionCount
        let neededRatio = 1.0 + wordGrowth
        
        if wordRatio >= neededRatio || Double(sectionDelta) >= sectionGrowth {
            let percent = Int((wordRatio - 1.0) * 100)
            
            return Verdict(
                surface: true,
                annotation: "\(dismissal.dismissCount)회 기각(\(dismissal.wordCount)w/\(dismissal.sectionCount)s) → "
                    + "현재 \(currentWords)w/\(currentSections)s (\(percent >= 0 ? "+" : "")\(percent)%w)"
            )
        }
        
        return Verdict(surface: false, annotation: nil)
    }
    
    func corpusGate(_ dismissal: Dismissal?, globalGeneration: Int) -> Verdict {
        guard let dismissal else { return Verdict(surface: true, annotation: nil) }
        
        if dismissal.generation < globalGeneration {
            return Verdict(
                surface: true,
                annotation: "\(dismissal.dismissCount)회 기각됨 → corpus 재편으로 재개방"
            )
        }
        
        return Verdict(surface: false, annotation: nil)
    }
    
    // MARK: - Private
}
