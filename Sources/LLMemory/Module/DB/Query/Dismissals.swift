//
//  Dismissals.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

enum Dismissals {
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
    static func lintKind(_ code: String, fingerprint: String? = nil) -> String {
        guard let fingerprint else { return lintPrefix + code }
        
        return "\(lintPrefix)\(code)#\(digest(fingerprint))"
    }
    
    static func digest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        
        return String(hash, radix: 36)
    }
    
    static func isLintKind(_ kind: String) -> Bool { kind.hasPrefix(lintPrefix) }
    
    static func lintFingerprint(of kind: String) -> String? {
        guard isLintKind(kind) else { return nil }
        
        let body = String(kind.dropFirst(lintPrefix.count))
        
        guard let cut = body.firstIndex(of: "#") else { return nil }
        
        return String(body[body.index(after: cut)...])
    }
    
    static func lintCode(of kind: String) -> String? {
        guard isLintKind(kind) else { return nil }
        
        let body = String(kind.dropFirst(lintPrefix.count))
        
        guard let cut = body.firstIndex(of: "#") else { return body }
        
        return String(body[body.startIndex..<cut])
    }
    
    static func generation(_ db: Database) throws -> Int {
        (try Int.fetchOne(
            db,
            sql: "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'candidate_generation'"
        )) ?? 0
    }
    
    static func bumpGeneration(_ db: Database) throws {
        let generation = try generation(db)
        
        try db.execute(sql: """
            INSERT INTO meta (key, value) VALUES ('candidate_generation', ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """, arguments: [String(generation + 1)])
    }
    
    static func record(
        _ db: Database,
        target: LintTarget,
        kind: String,
        reason: String?,
        now: Int
    ) throws {
        switch target {
        case .note(let noteId):
            try record(db, noteId: noteId, kind: kind, reason: reason, now: now)
        
        case .corpus(let key):
            try db.execute(sql: """
                INSERT INTO corpus_dismissals
                    (target_key, kind, dismiss_count, generation, reason, last_dismissed_at)
                VALUES (?, ?, 1, ?, ?, ?)
                ON CONFLICT(target_key, kind) DO UPDATE SET
                    dismiss_count = dismiss_count + 1,
                    generation = excluded.generation,
                    reason = excluded.reason,
                    last_dismissed_at = excluded.last_dismissed_at
                """, arguments: [key, kind, try generation(db), reason, now])
        }
    }
    
    static func record(
        _ db: Database,
        noteId: String,
        kind: String,
        reason: String?,
        now: Int
    ) throws {
        let shape = try Row.fetchOne(
            db,
            sql: "SELECT word_count, section_count FROM notes WHERE id = ?",
            arguments: [noteId]
        )
        let wordCount = (shape?["word_count"] as Int?) ?? 0
        let sectionCount = (shape?["section_count"] as Int?) ?? 0
        let generation = try generation(db)
        
        try db.execute(sql: """
            INSERT INTO candidate_dismissals
                (note_id, kind, dismiss_count, word_count, section_count, generation, reason, last_dismissed_at)
            VALUES (?, ?, 1, ?, ?, ?, ?, ?)
            ON CONFLICT(note_id, kind) DO UPDATE SET
                dismiss_count = dismiss_count + 1,
                word_count = excluded.word_count,
                section_count = excluded.section_count,
                generation = excluded.generation,
                reason = excluded.reason,
                last_dismissed_at = excluded.last_dismissed_at
            """, arguments: [noteId, kind, wordCount, sectionCount, generation, reason, now])
    }
    
    static func lintLookupKey(_ target: LintTarget, _ kind: String) -> String {
        "\(target.storageKey)\u{0}\(kind)"
    }
    
    static func lintDismissals(_ db: Database) throws -> [String: Dismissal] {
        var dismissals: [String: Dismissal] = [:]
        let noteRows = try Row.fetchAll(db, sql: """
            SELECT note_id, kind, dismiss_count, word_count, section_count, generation
            FROM candidate_dismissals WHERE kind LIKE ?
            """, arguments: [lintPrefix + "%"])
        
        for row in noteRows {
            let kind: String = row["kind"]
            
            guard lintCode(of: kind) != nil else { continue }
            
            dismissals[lintLookupKey(.note(row["note_id"]), kind)] = Dismissal(
                kind: kind,
                dismissCount: row["dismiss_count"] as Int? ?? 1,
                wordCount: row["word_count"] as Int? ?? 0,
                sectionCount: row["section_count"] as Int? ?? 0,
                generation: row["generation"] as Int? ?? 0
            )
        }
        
        let corpusRows = try Row.fetchAll(db, sql: """
            SELECT target_key, kind, dismiss_count, generation
            FROM corpus_dismissals WHERE kind LIKE ?
            """, arguments: [lintPrefix + "%"])
        
        for row in corpusRows {
            let kind: String = row["kind"]
            
            guard lintCode(of: kind) != nil else { continue }
            
            dismissals[lintLookupKey(.corpus(row["target_key"]), kind)] = Dismissal(
                kind: kind,
                dismissCount: row["dismiss_count"] as Int? ?? 1,
                wordCount: 0,
                sectionCount: 0,
                generation: row["generation"] as Int? ?? 0
            )
        }
        
        return dismissals
    }
    
    static func byNote(_ db: Database, kind: String) throws -> [String: Dismissal] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT note_id, dismiss_count, word_count, section_count, generation
            FROM candidate_dismissals WHERE kind = ?
            """, arguments: [kind])
        var dismissals: [String: Dismissal] = [:]
        
        for row in rows {
            dismissals[row["note_id"]] = Dismissal(
                kind: kind,
                dismissCount: row["dismiss_count"] as Int? ?? 1,
                wordCount: row["word_count"] as Int? ?? 0,
                sectionCount: row["section_count"] as Int? ?? 0,
                generation: row["generation"] as Int? ?? 0
            )
        }
        
        return dismissals
    }
    
    static func gate(
        _ dismissal: Dismissal?,
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
        
        let growthFactor = max(1.0, Config.getDouble("habituation.growth_factor", default: 1.5))
        let factor = pow(growthFactor, Double(max(dismissal.dismissCount - 1, 0)))
        let wordGrowth = max(0.0, Config.getDouble("habituation.word_growth", default: 0.5))
            * factor
        let sectionGrowth = max(0.0, Config.getDouble("habituation.section_growth", default: 2.0))
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
    
    static func corpusGate(_ dismissal: Dismissal?, globalGeneration: Int) -> Verdict {
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
