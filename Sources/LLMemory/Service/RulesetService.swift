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
public struct RulesetService: Sendable {
    enum Kind {
        static let opsWhitelist = "ops.whitelist"
        static let opsDeny = "ops.deny"
        static let consolidateMode = "consolidate.mode"
        static let mergeAuto = "merge.auto"
        static let staleAutoMark = "stale.auto_mark"
        static let frontmatterSchema = "frontmatter.schema"
        static let noteOwnerRequired = "note.owner_required"
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

    // MARK: - Property
    let storage: GRDBStorage

    // MARK: - Initializer
    init(storage: GRDBStorage) {
        self.storage = storage
    }

    // MARK: - Public
    public func list() async throws -> [RulesetSummary] {
        try await storage.read { scope in
            try scope.run(FetchRulesetsTransaction()).map { ruleset in
                RulesetSummary(
                    id: ruleset.id,
                    name: ruleset.name,
                    description: ruleset.description,
                    ruleCount: try rules(scope, rulesetId: ruleset.id).count
                )
            }
        }
    }

    public func show(id: String) async throws -> RulesetShowResult? {
        try await storage.read { scope in
            guard let ruleset = try scope.run(FetchRulesetTransaction(id: id)) else { return nil }

            let views = try rules(scope, rulesetId: id).map { rule in
                RuleView(id: rule.id, kind: rule.kind, paramsJSON: rule.paramsRaw)
            }

            return RulesetShowResult(
                id: ruleset.id,
                name: ruleset.name,
                description: ruleset.description,
                rules: views
            )
        }
    }

    public func effective(
        ruleset: String,
        axis: String
    ) async throws -> RulesetEffective? {
        try await storage.read { scope in
            guard try scope.run(RulesetExistsTransaction(id: ruleset)) else { return nil }

            return try effective(scope, axis: axis, rulesetIds: [ruleset])
        }
    }

    // MARK: - Internal
    // Folds the rulesets' rules into one effective policy — precedence is
    // "the stricter wins" per kind.
    func effective(
        _ scope: GRDBReadScope,
        axis: String,
        rulesetIds: [String]
    ) throws -> RulesetEffective {
        var effective = RulesetEffective()
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

    func rules(_ scope: GRDBReadScope, rulesetId: String) throws -> [Rule] {
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
