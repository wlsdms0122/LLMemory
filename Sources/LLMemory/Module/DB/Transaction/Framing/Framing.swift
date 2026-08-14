//
//  Framing.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct Framing: Sendable {
    // MARK: - Property
    static let stopwords: Set<String> = [
        "그리고", "하지만", "그런데", "그래서", "그러면", "이게", "저게", "이거",
        "저거", "뭐야", "있어", "없어", "해줘", "해봐", "하자", "이렇게", "저렇게",
        "이런", "저런", "정도", "우리", "너가", "니가", "내가", "근데",
        "the", "and", "for", "with", "this", "that", "are", "was", "were", "will",
        "have", "has", "had", "been", "from", "not", "but", "can", "get", "got",
        "you", "your", "they", "them", "their", "our", "out", "off", "about",
        "just", "into", "what", "when", "where", "which", "than", "then"
    ]

    private static let wordRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9_가-힣]{2,}"#)

    // MARK: - Initializer
    // MARK: - Public
    func extractKeywords(_ text: String, limit: Int = 15) -> [String] {
        var frequency: [String: Int] = [:]
        let nsText = text as NSString

        Self.wordRegex.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match else { return }

            let word = nsText.substring(with: match.range).lowercased()

            if Self.stopwords.contains(word) { return }

            frequency[word, default: 0] += 1
        }

        let ranked = frequency.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }

            return lhs.key < rhs.key
        }

        return ranked.prefix(limit).map { entry in entry.key }
    }

    // MARK: - Private
    func ftsQuery(_ keywords: [String]) -> String {
        let parts = keywords
            .filter { keyword in !keyword.isEmpty }
            .map { keyword in "\"\(keyword)\"" }

        return parts.isEmpty ? "" : parts.joined(separator: " OR ")
    }
}
