//
//  RulesetService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Ruleset-domain service — owns mutation-policy interpretation: rule params
// typing, precedence folding into an Effective policy, and the observation
// surfaces. Row access rides ruleset transactions.
public enum RulesetService {
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

    enum Kind {
        static let opsWhitelist = "ops.whitelist"
        static let opsDeny = "ops.deny"
        static let consolidateMode = "consolidate.mode"
        static let mergeAuto = "merge.auto"
        static let staleAutoMark = "stale.auto_mark"
        static let frontmatterSchema = "frontmatter.schema"
        static let noteOwnerRequired = "note.owner_required"
    }

    public enum ConsolidateMode: String, Encodable, Sendable {
        case auto
        case signalOnly = "signal_only"
        case off

        fileprivate var severity: Int {
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

    struct Rule {
        // MARK: - Property
        let id: Int64
        let rulesetId: String
        let kind: String
        let params: [String: Any]
        let paramsRaw: String

        // MARK: - Initializer
        // MARK: - Public
        func axisScope() throws -> String? {
            try string("axis").flatMap { axis in axis.isEmpty ? nil : axis }
        }

        func stringList(_ key: String) throws -> [String]? {
            guard let raw = params[key] else { return nil }

            guard let list = raw as? [String] else {
                throw RulesetError.malformedParams(
                    ruleId: id,
                    rulesetId: rulesetId,
                    detail: "'\(key)' must be a string array"
                )
            }

            return list
        }

        func string(_ key: String) throws -> String? {
            guard let raw = params[key] else { return nil }

            guard let value = raw as? String else {
                throw RulesetError.malformedParams(
                    ruleId: id,
                    rulesetId: rulesetId,
                    detail: "'\(key)' must be a string"
                )
            }

            return value
        }

        func bool(_ key: String) throws -> Bool? {
            guard let raw = params[key] else { return nil }

            guard let value = raw as? Bool else {
                throw RulesetError.malformedParams(
                    ruleId: id,
                    rulesetId: rulesetId,
                    detail: "'\(key)' must be a boolean"
                )
            }

            return value
        }

        func require<T>(_ value: T?, _ key: String) throws -> T {
            guard let value else {
                throw RulesetError.malformedParams(
                    ruleId: id,
                    rulesetId: rulesetId,
                    detail: "kind '\(kind)' requires '\(key)'"
                )
            }

            return value
        }

        // MARK: - Private
    }

    public struct Effective: Encodable, Sendable {
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

    public struct Summary: Sendable {
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

    public struct ShowResult: Sendable {
        // MARK: - Property
        public let id: String
        public let name: String
        public let description: String?
        public let rules: [RuleView]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func list(_ storage: GRDBStorage) async throws -> [Summary] {
        try await storage.read { scope in
            try scope.run(FetchRulesetsTransaction()).map { ruleset in
                Summary(
                    id: ruleset.id,
                    name: ruleset.name,
                    description: ruleset.description,
                    ruleCount: try rules(scope, rulesetId: ruleset.id).count
                )
            }
        }
    }

    public static func show(_ storage: GRDBStorage, id: String) async throws -> ShowResult? {
        try await storage.read { scope in
            guard let ruleset = try scope.run(FetchRulesetTransaction(id: id)) else { return nil }

            let views = try rules(scope, rulesetId: id).map { rule in
                RuleView(id: rule.id, kind: rule.kind, paramsJSON: rule.paramsRaw)
            }

            return ShowResult(
                id: ruleset.id,
                name: ruleset.name,
                description: ruleset.description,
                rules: views
            )
        }
    }

    public static func effective(
        _ storage: GRDBStorage,
        ruleset: String,
        axis: String
    ) async throws -> Effective? {
        try await storage.read { scope in
            guard try scope.run(RulesetExistsTransaction(id: ruleset)) else { return nil }

            return try effective(scope, axis: axis, rulesetIds: [ruleset])
        }
    }

    // MARK: - Internal
    // Folds the rulesets' rules into one effective policy — precedence is
    // "the stricter wins" per kind.
    static func effective(
        _ scope: GRDBReadScope,
        axis: String,
        rulesetIds: [String]
    ) throws -> Effective {
        var effective = Effective()
        effective.appliedRulesets = rulesetIds
        var whitelistInitialized = false

        for rulesetId in rulesetIds {
            for rule in try rules(scope, rulesetId: rulesetId) {
                if let ruleAxis = try rule.axisScope(), ruleAxis != "*", ruleAxis != axis {
                    continue
                }

                switch rule.kind {
                case Kind.opsWhitelist:
                    let ops = Set(try rule.require(rule.stringList("ops"), "ops"))

                    if !whitelistInitialized {
                        effective.opsWhitelist = ops
                        whitelistInitialized = true
                    } else {
                        let previous = effective.opsWhitelist ?? []

                        if ops.contains("*") {
                        } else if previous.contains("*") {
                            effective.opsWhitelist = ops
                        } else {
                            effective.opsWhitelist = previous.intersection(ops)
                        }
                    }

                case Kind.opsDeny:
                    effective.opsDeny.formUnion(try rule.require(rule.stringList("ops"), "ops"))

                case Kind.consolidateMode:
                    let raw = try rule.require(rule.string("mode"), "mode")

                    guard let mode = ConsolidateMode(rawValue: raw) else {
                        throw RulesetError.malformedParams(
                            ruleId: rule.id,
                            rulesetId: rule.rulesetId,
                            detail: "unknown consolidate mode '\(raw)'"
                        )
                    }

                    if mode.severity > effective.consolidateMode.severity {
                        effective.consolidateMode = mode
                    }

                case Kind.mergeAuto:
                    if !(try rule.require(rule.bool("enabled"), "enabled")) {
                        effective.mergeAuto = false
                    }

                case Kind.staleAutoMark:
                    if !(try rule.require(rule.bool("enabled"), "enabled")) {
                        effective.staleAutoMark = false
                    }

                case Kind.noteOwnerRequired:
                    if try rule.require(rule.bool("enabled"), "enabled") {
                        effective.ownerRequired = true
                    }

                case Kind.frontmatterSchema:
                    let schemaId = try rule.string("schema_id")
                    let required = try rule.stringList("required")

                    if schemaId == nil && required == nil {
                        throw RulesetError.malformedParams(
                            ruleId: rule.id,
                            rulesetId: rule.rulesetId,
                            detail: "kind 'frontmatter.schema' requires 'schema_id' or 'required'"
                        )
                    }

                    if let schemaId { effective.frontmatterSchemas.append(schemaId) }
                    if let required { effective.frontmatterRequired.formUnion(required) }

                default:
                    continue
                }
            }
        }

        return effective
    }

    static func rules(_ scope: GRDBReadScope, rulesetId: String) throws -> [Rule] {
        try scope.run(FetchRulesTransaction(rulesetId: rulesetId)).map { record in
            let paramsRaw = record.params

            guard let data = paramsRaw.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data),
                let params = parsed as? [String: Any]
            else {
                throw RulesetError.malformedParams(
                    ruleId: record.id,
                    rulesetId: record.rulesetId,
                    detail: "params is not a JSON object: \(paramsRaw)"
                )
            }

            return Rule(
                id: record.id,
                rulesetId: record.rulesetId,
                kind: record.kind,
                params: params,
                paramsRaw: paramsRaw
            )
        }
    }

    // MARK: - Private
}
