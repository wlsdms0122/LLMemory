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
//
// The refusal asks CoreFoundation what the value *is*, not what it can be read
// as. `raw is Bool` answers by value, not by type: an `NSNumber` holding 0 or 1
// satisfies it, so that spelling refuses the integers 0 and 1 along with the
// bools — which is a bound nobody can set and a confidence nobody can state.
struct PayloadNumber {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func value(of raw: Any?) -> Double? {
        guard let raw, CFGetTypeID(raw as CFTypeRef) != CFBooleanGetTypeID() else {
            return nil
        }

        if let double = raw as? Double { return double }
        if let int = raw as? Int { return Double(int) }
        if let number = raw as? NSNumber { return number.doubleValue }

        return nil
    }

    // MARK: - Private
}
