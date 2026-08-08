//
//  Ruleset.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum Ruleset {
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
    
    public enum ConsolidateMode: String, Encodable {
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
    
    struct Row: Encodable {
        // MARK: - Property
        let id: String
        let name: String
        let description: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
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
    
    public struct Effective: Encodable {
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
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func effective(
        _ db: Database,
        axis: String,
        rulesetIds: [String]
    ) throws -> Effective {
        var effective = Effective()
        effective.appliedRulesets = rulesetIds
        var whitelistInitialized = false
        
        for rulesetId in rulesetIds {
            let rules = try fetchRules(db, rulesetId: rulesetId)
            
            for rule in rules {
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
    
    static func listRulesets(_ db: Database) throws -> [Row] {
        try RulesetRecord.order(Column("id")).fetchAll(db).map { record in
            Row(id: record.id, name: record.name, description: record.description)
        }
    }
    
    static func getRuleset(_ db: Database, id: String) throws -> Row? {
        try RulesetRecord.fetchOne(db, key: id).map { record in
            Row(id: record.id, name: record.name, description: record.description)
        }
    }
    
    static func fetchRules(_ db: Database, rulesetId: String) throws -> [Rule] {
        let records = try RuleRecord
            .filter(Column("ruleset_id") == rulesetId && Column("enabled") == true)
            .order(Column("id"))
            .fetchAll(db)
        
        return try records.map { record in
            let id = record.id
            let rulesetId = record.rulesetId
            let paramsRaw = record.params
            
            guard let data = paramsRaw.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data),
                let params = parsed as? [String: Any]
            else {
                throw RulesetError.malformedParams(
                    ruleId: id,
                    rulesetId: rulesetId,
                    detail: "params is not a JSON object: \(paramsRaw)"
                )
            }
            
            return Rule(
                id: id,
                rulesetId: rulesetId,
                kind: record.kind,
                params: params,
                paramsRaw: paramsRaw
            )
        }
    }
    
    static func rulesetExists(_ db: Database, id: String) throws -> Bool {
        try RulesetRecord.exists(db, key: id)
    }
    
    // MARK: - Private
}

public extension Ruleset {
    struct Summary {
        // MARK: - Property
        public let id: String
        public let name: String
        public let description: String?
        public let ruleCount: Int

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    struct RuleView {
        // MARK: - Property
        public let id: Int64
        public let kind: String
        public let paramsJSON: String

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    struct ShowResult {
        // MARK: - Property
        public let id: String
        public let name: String
        public let description: String?
        public let rules: [RuleView]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
}
