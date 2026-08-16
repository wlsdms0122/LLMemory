//
//  SessionId.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Which conversation a call belongs to. Activity windows are grouped by this
// value and an absent one is its own group, so "no session" needs exactly one
// spelling — and the empty string was a second one, which the read paths
// checked for and the write paths did not.
//
// Nothing can hold it now, so the check has nowhere left to be forgotten.
public struct SessionId: Sendable, Hashable {
    // MARK: - Property
    public let rawValue: String

    // MARK: - Initializer
    // Failable on both counts: a caller with nothing to say and a caller that
    // says nothing are the same caller.
    public init?(_ rawValue: String?) {
        guard let rawValue, !rawValue.isEmpty else { return nil }

        self.rawValue = rawValue
    }

    // MARK: - Public
    // MARK: - Private
}
