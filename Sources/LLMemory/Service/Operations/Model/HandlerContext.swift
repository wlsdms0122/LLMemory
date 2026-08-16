//
//  HandlerContext.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct HandlerContext {
    // MARK: - Property
    // The batch's ambient facts — resolved once at the apply/dry-run entry
    // so no handler re-derives them from process globals. The initializer
    // requires them: an unseeded context does not compile.
    public let sessionId: SessionId?
    public let now: Int
    
    public var inFlightIds: Set<String> = []
    public var invalidatedIds: Set<String> = []
    public var removedIds: Set<String> = []
    public var lockedInFlightIds: Set<String> = []
    public var stagedBodies: [String: String] = [:]
    public var opaqueBodyIds: Set<String> = []
    
    // MARK: - Initializer
    public init(sessionId: SessionId?, now: Int) {
        self.sessionId = sessionId
        self.now = now
    }
    
    // MARK: - Public
    // MARK: - Private
}
