//
//  NoteHistoryEvent.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct NoteHistoryEvent: Encodable, Sendable {
    // MARK: - Property
    public let kind: String
    public let reason: String?
    public let at: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
