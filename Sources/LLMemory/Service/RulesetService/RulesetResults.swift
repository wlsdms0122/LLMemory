//
//  RulesetResults.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The ruleset surface vocabulary — flat top-level models with a domain
// prefix (owner call: a caller must not need the service's name to spell
// a return type).
enum RulesetError: Error, CustomStringConvertible {
    case malformedParams(ruleId: Int64, rulesetId: String, detail: String)

    var description: String {
        switch self {
        case .malformedParams(let ruleId, let rulesetId, let detail):
            return "rule #\(ruleId) in ruleset '\(rulesetId)' is malformed: \(detail) — "
                + "fix or disable the row (a broken policy must not fail open)"
        }
    }
}

public enum ConsolidateMode: String, Encodable, Sendable {
    case auto
    case signalOnly = "signal_only"
    case off

    var severity: Int {
        switch self {
        case .auto:
            return 0

        case .signalOnly:
            return 1

        case .off:
            return 2
        }
    }
}

public struct RulesetEffective: Encodable, Sendable {
    // MARK: - Property
    public var opsWhitelist: Set<String>?
    public var opsDeny: Set<String>
    public var consolidateMode: ConsolidateMode
    public var mergeAuto: Bool
    public var staleAutoMark: Bool
    public var ownerRequired: Bool
    public var frontmatterSchemas: [String]
    public var frontmatterRequired: Set<String>
    public var appliedRulesets: [String]

    // MARK: - Initializer
    public init() {
        self.opsWhitelist = nil
        self.opsDeny = []
        self.consolidateMode = .auto
        self.mergeAuto = true
        self.staleAutoMark = true
        self.ownerRequired = false
        self.frontmatterSchemas = []
        self.frontmatterRequired = []
        self.appliedRulesets = []
    }

    // MARK: - Public
    func allows(op: String) -> (ok: Bool, reason: String?) {
        if opsDeny.contains("*") {
            return (false, "op '\(op)' blocked by ops.deny ['*']")
        }

        if opsDeny.contains(op) {
            return (false, "op '\(op)' is in ops.deny")
        }

        if let opsWhitelist, !opsWhitelist.contains("*"), !opsWhitelist.contains(op) {
            let list = opsWhitelist.sorted().joined(separator: ",")

            return (false, "op '\(op)' not in ops.whitelist [\(list)]")
        }

        return (true, nil)
    }

    // MARK: - Private
}

public struct RulesetSummary: Sendable {
    // MARK: - Property
    public let id: String
    public let name: String
    public let description: String?
    public let ruleCount: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct RuleView: Sendable {
    // MARK: - Property
    public let id: Int64
    public let kind: String
    public let paramsJSON: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct RulesetShowResult: Sendable {
    // MARK: - Property
    public let id: String
    public let name: String
    public let description: String?
    public let rules: [RuleView]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
