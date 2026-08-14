//
//  PayloadNumber.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Reading a number out of a payload that arrived as JSON.
//
// `JSONSerialization` decodes `true` to an `NSNumber`, and `NSNumber as?
// Double` succeeds with 1.0 — so every hand-rolled cast accepts a bool as the
// number one, and records a maximum as though the caller had asked for it.
// The refusal lives here, once, because it is the same refusal every time and
// a second copy is a second chance to forget it.
struct PayloadNumber {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func value(of raw: Any?) -> Double? {
        guard let raw, !(raw is Bool) else { return nil }

        if let double = raw as? Double { return double }
        if let int = raw as? Int { return Double(int) }
        if let number = raw as? NSNumber { return number.doubleValue }

        return nil
    }

    // MARK: - Private
}
