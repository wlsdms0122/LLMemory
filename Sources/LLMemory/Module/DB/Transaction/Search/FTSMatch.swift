//
//  FTSMatch.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// What a caller is asking the FTS index to match. The two ways of asking are
// different in kind, not in a flag: one hands SQLite an expression the caller
// wrote, the other is read out of free text and quoted on the way. Keeping
// them apart is what lets the reader belong to the case that has one — the
// raw path was being made to supply a keyword extractor it never reaches.
enum FTSMatch {
    // MARK: - Property
    // The caller's own FTS5 expression, passed through as written. That is
    // the point of it and also the risk: this is the only case that can
    // arrive malformed, which is why it is the only one that names an error.
    case raw(String)

    // Cues to match any of. The quoting belongs to this translation rather
    // than to each caller — a cue carrying a quote would close the phrase
    // early and change what was asked, which is what two copies of it
    // disagreed about.
    case cues([String])

    var expression: String? {
        switch self {
        case let .raw(query):
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

            return trimmed.isEmpty ? nil : trimmed

        case let .cues(cues):
            let parts = cues
                .filter { cue in !cue.isEmpty }
                .map { cue in "\"\(cue.replacingOccurrences(of: "\"", with: ""))\"" }

            return parts.isEmpty ? nil : parts.joined(separator: " OR ")
        }
    }

    // MARK: - Initializer
    // MARK: - Public
    // Free text becomes cues by whichever reader the caller was given.
    static func text(_ text: String, keywords: any KeywordExtracting) -> FTSMatch {
        .cues(keywords.keywords(in: text, limit: RetrievalCue.limit))
    }

    // Why a query SQLite refused is only answerable for an expression the
    // caller wrote — cues are quoted here and cannot come out malformed, so a
    // failure on that path is a failure of something else and says so.
    func rejection(_ expression: String) -> Error? {
        guard case .raw = self else { return nil }

        return FTSMatchError.invalidRawQuery(expression)
    }

    // MARK: - Private
}

enum FTSMatchError: LocalizedError {
    // MARK: - Property
    case invalidRawQuery(String)

    var errorDescription: String? {
        switch self {
        case let .invalidRawQuery(query):
            "invalid FTS5 expression (--raw): \(query)"
                + " — check quotes/operators (see `query search --help`)"
        }
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
