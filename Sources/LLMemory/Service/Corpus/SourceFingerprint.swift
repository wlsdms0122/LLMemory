//
//  SourceFingerprint.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import CryptoKit

// Content fingerprints for a note's declared source files — the pure
// hashing mechanics behind source-drift detection. DB rows are the source
// transactions' business.
public struct SourceFingerprint: Sendable {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public func isDriftCheckable(_ ref: String) -> Bool {
        (ref as NSString).expandingTildeInPath.hasPrefix("/")
    }

    func computeSha(path: URL) -> String? {
        guard let data = try? Data(contentsOf: path) else { return nil }

        let digest = SHA256.hash(data: data)
        let hex = digest.map { byte in String(format: "%02x", byte) }.joined()

        return String(hex.prefix(16))
    }

    func computeFingerprint(_ paths: [String]) -> String? {
        let checkable = paths.filter(isDriftCheckable)

        if checkable.isEmpty { return nil }

        let parts = checkable.map { path in
            "\(path):\(computeSha(path: resolve(path)) ?? "")"
        }
        let payload = parts.joined(separator: "\n").data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: payload)

        return String(digest.map { byte in String(format: "%02x", byte) }.joined().prefix(16))
    }

    func computeDeclHash(_ paths: [String]) -> String? {
        let checkable = paths.filter(isDriftCheckable)

        if checkable.isEmpty { return nil }

        let payload = checkable.joined(separator: "\n").data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: payload)

        return String(digest.map { byte in String(format: "%02x", byte) }.joined().prefix(16))
    }

    func resolve(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    // MARK: - Private
}
