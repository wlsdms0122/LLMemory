//
//  Handlers.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public struct OpField: Sendable, Encodable {
    enum CodingKeys: String, CodingKey {
        case name
        case required
        case description
        case requiredUnless = "required_unless"
    }
    
    // MARK: - Property
    public let name: String
    public let required: Bool
    public let description: String
    public let requiredUnless: String?
    public let role: OpFieldRole
    
    // MARK: - Initializer
    // MARK: - Public
    public static func required(
        _ name: String,
        role: OpFieldRole = .plain,
        _ description: String
    ) -> OpField {
        OpField(
            name: name,
            required: true,
            description: description,
            requiredUnless: nil,
            role: role
        )
    }
    
    public static func optional(
        _ name: String,
        role: OpFieldRole = .plain,
        _ description: String
    ) -> OpField {
        OpField(
            name: name,
            required: false,
            description: description,
            requiredUnless: nil,
            role: role
        )
    }
    
    public static func required(
        _ name: String,
        unless waiver: String,
        role: OpFieldRole = .plain,
        _ description: String
    ) -> OpField {
        OpField(
            name: name,
            required: true,
            description: description,
            requiredUnless: waiver,
            role: role
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        try container.encode(required, forKey: .required)
        try container.encode(description, forKey: .description)
        
        if let requiredUnless {
            try container.encode(requiredUnless, forKey: .requiredUnless)
        }
    }
    
    // MARK: - Private
}

public enum OpFieldRole: Sendable, Equatable {
    case plain
    case noteId
    case noteIdList
    case axis
    case childSpecs
}

public struct OpSchema: Sendable, Encodable {
    // MARK: - Property
    public let summary: String
    public let fields: [OpField]
    public let example: String
    
    public var requiredNames: [String] { fields.filter(\.required).map(\.name) }
    
    // MARK: - Initializer
    // MARK: - Public
    public func mentionedNoteIds(in op: [String: Any]) -> Set<String> {
        var mentioned: Set<String> = []
        
        for field in fields {
            switch field.role {
            case .noteId:
                if let noteId = op[field.name] as? String, !noteId.isEmpty {
                    mentioned.insert(noteId)
                }
            
            case .noteIdList:
                for value in (op[field.name] as? [Any]) ?? [] {
                    if let noteId = value as? String, !noteId.isEmpty {
                        mentioned.insert(noteId)
                    }
                }
            
            case .childSpecs:
                for spec in (op[field.name] as? [[String: Any]]) ?? [] {
                    if let noteId = spec["id"] as? String, !noteId.isEmpty {
                        mentioned.insert(noteId)
                    }
                }
            
            case .axis, .plain:
                break
            }
        }
        
        return mentioned
    }
    
    public func mentionedAxes(in op: [String: Any]) -> Set<String> {
        var mentioned: Set<String> = []
        
        for field in fields {
            switch field.role {
            case .axis:
                if let axis = op[field.name] as? String, !axis.isEmpty {
                    mentioned.insert(axis)
                }
            
            case .childSpecs:
                for spec in (op[field.name] as? [[String: Any]]) ?? [] {
                    if let axis = spec["axis"] as? String, !axis.isEmpty {
                        mentioned.insert(axis)
                    }
                }
            
            case .noteId, .noteIdList, .plain:
                break
            }
        }
        
        return mentioned
    }
    
    public func requiredNames(given op: [String: Any]) -> [String] {
        fields.filter { field in
            guard field.required else { return false }
            
            if let waiver = field.requiredUnless,
                let value = op[waiver] as? String, !value.isEmpty {
                return false
            }
            
            return true
        }.map(\.name)
    }
    
    // MARK: - Private
}

struct FieldTypeError: Error, CustomStringConvertible {
    // MARK: - Property
    let field: String
    let expected: String
    let got: Any
    
    var description: String {
        "field '\(field)' must be a \(expected), got \(type(of: got)): \(got)"
    }
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct OpHandler: @unchecked Sendable {
    // MARK: - Property
    public let schema: OpSchema
    public let validate: (_ op: [String: Any], _ context: HandlerContext, _ db: Database) throws -> String?
    public let write: (_ op: [String: Any], _ db: Database) throws -> [String: Any]
    public let effect: (_ op: [String: Any]) -> [String: [String]]
    public let touches: (_ op: [String: Any], _ db: Database) throws -> [URL]
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct HandlerContext {
    // MARK: - Property
    public var inFlightIds: Set<String> = []
    // Axes an earlier op in the same transaction introduces (create_note with axis_description).
    // Later ops must see them as existing even though nothing is committed yet.
    public var inFlightAxes: Set<String> = []
    public var invalidatedIds: Set<String> = []
    public var removedIds: Set<String> = []
    public var lockedInFlightIds: Set<String> = []
    public var stagedBodies: [String: String] = [:]
    public var opaqueBodyIds: Set<String> = []
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct ExistingState {
    // MARK: - Property
    public let ids: Set<String>
    public let axes: Set<String>
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public enum Handlers {
    // MARK: - Property
    public static let idRegex = try! NSRegularExpression(pattern: #"^[a-z0-9][a-z0-9-]*$"#)
    public static let axisRegex = idRegex
    public static let namespaceRegex = try! NSRegularExpression(pattern: #"^[a-z][a-z0-9_-]*$"#)
    public static let tagRegex = try! NSRegularExpression(pattern: #"^[a-z0-9][a-z0-9-]*$"#)
    public static let dateTailRegex = try! NSRegularExpression(pattern: #"(\d{6})(?:-\d+)?$"#)
    public static let headingMarkerRegex = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.+?)\s*$"#)
    
    public static let validPriority: Set<String> = ["eager", "lazy"]
    public static let creatableFlagKinds: Set<String> = ["reconsolidate", "stale_ref"]
    public static let resolvableFlagKinds: Set<String> = creatableFlagKinds.union(["enrich_review"])
    public static let validPatchActions: Set<String> = ["replace", "append", "prepend", "remove"]
    public static let frontmatterMutable: Set<String> = [
        "title", "summary", "tags", "priority", "source", "promoted_from"
    ]
    
    static let registry: [String: OpHandler] = HandlersRegistry.build()
    
    // MARK: - Initializer
    // MARK: - Public
    public static func pathFor(axis: String, nid: String) -> URL {
        let nsNoteId = nid as NSString
        
        if let match = dateTailRegex.firstMatch(
            in: nid,
            range: NSRange(location: 0, length: nsNoteId.length)
        ) {
            let dateTail = nsNoteId.substring(with: match.range(at: 1))
            let year = "20" + String(dateTail.prefix(2))
            let month = String(dateTail.dropFirst(2).prefix(2))
            
            return Paths.notes.appendingPathComponent(axis)
                .appendingPathComponent(year)
                .appendingPathComponent(month)
                .appendingPathComponent("\(nid).md")
        }
        
        return Paths.notes.appendingPathComponent(axis).appendingPathComponent("\(nid).md")
    }
    
    public static func existingState(_ db: Database) throws -> ExistingState {
        ExistingState(
            ids: try Notes.existingIds(db),
            axes: try FetchAxisNamesTransaction().perform(db)
        )
    }
    
    public static func checkRequired(_ op: [String: Any], fields: [String]) -> String? {
        for field in fields {
            if op[field] == nil { return "missing/empty field: \(field)" }
            
            if let value = op[field] as? String, value.isEmpty {
                return "missing/empty field: \(field)"
            }
            
            if op[field] is NSNull { return "missing/empty field: \(field)" }
        }
        
        return nil
    }
    
    public static func asDouble(_ raw: Any) -> Double? {
        if raw is Bool { return nil }
        if let double = raw as? Double { return double }
        if let int = raw as? Int { return Double(int) }
        if let number = raw as? NSNumber { return number.doubleValue }
        
        return nil
    }
    
    public static func checkIDKnown(
        _ nid: String,
        context: HandlerContext,
        db: Database
    ) throws -> String? {
        if context.inFlightIds.contains(nid) { return nil }
        if try Notes.exists(db, nid: nid) { return nil }
        
        return "unknown id: \(nid)"
    }
    
    public static func finalizeSource(_ items: Any?) throws -> [String] {
        guard let items else { return [] }
        
        return try Frontmatter.decodeSource(items)
    }
    
    public static func sourceInputError(_ items: Any?) -> String? {
        guard let items else { return nil }
        
        do {
            _ = try Frontmatter.decodeSource(items)
            
            return nil
        } catch {
            return "\(error)"
        }
    }
    
    public static func recordEdit(
        _ db: Database,
        nid: String,
        opLabel: String,
        now: Int
    ) throws {
        try Notes.recordLifecycleEvent(db, nid: nid, kind: "edited", reason: opLabel, now: now)
    }
    
    public static func seedInitialLinks(_ db: Database, nid: String, tags: [String]) throws {
        if tags.isEmpty { return }
        
        let placeholders = Array(repeating: "?", count: tags.count).joined(separator: ",")
        var arguments: [DatabaseValueConvertible] = []
        arguments.append(contentsOf: tags)
        arguments.append(nid)
        
        let rows = try Row.fetchAll(db, sql: """
            SELECT n.id, COUNT(*) AS shared,
                   (SELECT COUNT(*) FROM tags WHERE note_id = n.id) AS other_total
            FROM tags t JOIN notes n ON n.id = t.note_id
            WHERE t.tag IN (\(placeholders)) AND n.id != ?
            GROUP BY n.id
            ORDER BY shared DESC, n.id ASC
            LIMIT 5
            """, arguments: StatementArguments(arguments))
        
        if rows.isEmpty { return }
        
        let now = Int(Date().timeIntervalSince1970)
        let kind = Links.kindCooccur
        let newTotal = tags.count
        
        for row in rows {
            let candidateId: String = row["id"]
            let shared: Int = row["shared"]
            let otherTotal: Int = row["other_total"] as Int? ?? 0
            
            guard let (source, destination) = Links.normalize(
                src: nid,
                dst: candidateId,
                kind: kind
            ) else {
                continue
            }
            
            let union = max(newTotal + otherTotal - shared, 1)
            let weight = max(Double(shared) / Double(union), 0.1)
            
            try db.execute(sql: """
                INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(src, dst, kind) DO UPDATE SET
                  weight = MIN(1.0, weight + excluded.weight),
                  last_activated_at = excluded.last_activated_at
                """, arguments: [source, destination, kind, weight, now, now])
        }
    }
    
    public static func trashPathFor(_ rel: String) throws -> URL {
        Paths.trash.appendingPathComponent(try relativeToNotes(rel))
    }
    
    public static func resolveTrashPath(_ rel: String) throws -> URL {
        let base = try trashPathFor(rel)
        
        if !FileManager.default.fileExists(atPath: base.path) { return base }
        
        let directory = base.deletingLastPathComponent()
        let pathExtension = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        var counter = 1
        
        while true {
            let candidate = directory.appendingPathComponent(
                pathExtension.isEmpty ? "\(stem).\(counter)" : "\(stem).\(counter).\(pathExtension)"
            )
            
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            
            counter += 1
        }
    }
    
    @discardableResult
    public static func trashNoteFile(_ src: URL, reason: String, now: Int) throws -> URL? {
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        
        let relativePath = try Notes.relativeToBrainRoot(src)
        var (doc, body) = try Frontmatter.parse(try String(contentsOf: src, encoding: .utf8))
        doc.trashedAt = now
        doc.trashedReason = reason.unicodeScalarPrefix(200)
        
        let trashPath = try resolveTrashPath(relativePath)
        try FileManager.default.createDirectory(
            at: trashPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (Frontmatter.dump(doc) + body).write(to: trashPath, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: src)
        
        return trashPath
    }
    
    public static func trashDestination(_ src: URL) -> URL? {
        guard let relativePath = try? Notes.relativeToBrainRoot(src) else { return nil }
        
        return try? resolveTrashPath(relativePath)
    }
    
    public static func opNames() -> [String] {
        registry.keys.sorted()
    }
    
    public static func opSchema(_ name: String) -> OpSchema? {
        registry[name]?.schema
    }
    
    static func composeCreateBody(_ op: [String: Any], _ db: Database) throws -> String {
        let raw = op["content"] as? String ?? ""
        var content = String(raw.reversed().drop(while: { character in character.isWhitespace }).reversed())
        let templateId = (op["template"] as? String).flatMap { value in value.isEmpty ? nil : value }
        
        if let templateId, content.isEmpty,
            let frame = try Template.loadFrame(db, templateId: templateId) {
            content = Template.scaffold(frame)
        }
        
        return content + "\n"
    }
    
    static func trashName(_ url: URL) -> (nid: String, counter: Int) {
        let stem = url.deletingPathExtension().lastPathComponent
        
        if let last = stem.split(separator: ".").last, let counter = Int(last) {
            return (String(stem.dropLast(last.count + 1)), counter)
        }
        
        return (stem, 0)
    }
    
    static func trashStemId(_ url: URL) -> String { trashName(url).nid }
    
    static func findTrashedFile(
        _ nid: String
    ) throws -> (url: URL, doc: FrontmatterDoc, body: String)? {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: Paths.trash.path) else { return nil }
        
        guard let iterator = fileManager.enumerator(
            at: Paths.trash,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        
        var best: (url: URL, doc: FrontmatterDoc, body: String, key: (Int, Int))?
        var unreadable: [String] = []
        
        for case let url as URL in iterator {
            guard url.pathExtension == "md" else { continue }
            
            let doc: FrontmatterDoc
            let body: String
            do {
                guard let read = try Notes.readNoteIfPresent(at: url) else { continue }
                
                (doc, body) = read
            } catch let error as NoteUnreadable {
                if trashStemId(url) == nid {
                    unreadable.append("\(url.lastPathComponent): \(error.reason)")
                }
                
                continue
            }
            
            guard doc.id == nid else { continue }
            
            let key = (doc.trashedAt ?? 0, trashName(url).counter)
            
            if best == nil || key > best!.key { best = (url, doc, body, key) }
        }
        
        if !unreadable.isEmpty {
            throw NotesError.trashUnreadable(nid: nid, files: unreadable, matched: best != nil)
        }
        
        return best.map { found in (url: found.url, doc: found.doc, body: found.body) }
    }
    
    static func mergeFields(_ doc: inout FrontmatterDoc, _ fields: [String: Any]) throws {
        let axis = doc.axis
        
        func string(_ key: String, _ value: Any) throws -> String {
            guard let string = value as? String else {
                throw FieldTypeError(field: key, expected: "string", got: value)
            }
            
            return string
        }
        
        func list(_ key: String, _ value: Any) throws -> [String] {
            guard let array = value as? [Any] else {
                throw FieldTypeError(field: key, expected: "list of strings", got: value)
            }
            
            guard array.count == array.compactMap({ element in element as? String }).count else {
                throw FieldTypeError(field: key, expected: "list of strings", got: value)
            }
            
            return array.compactMap { element in element as? String }
        }
        
        for (key, value) in fields {
            switch key {
            case "title":
                doc.title = try string(key, value)
            
            case "summary":
                doc.summary = try string(key, value)
            
            case "tags":
                let tags = try list(key, value)
                
                if !axis.isEmpty, !tags.contains(axis) {
                    throw FieldTypeError(
                        field: key,
                        expected: "list containing the axis tag '\(axis)'",
                        got: value
                    )
                }
                
                doc.tags = tags
            
            case "priority":
                doc.priority = try string(key, value)
            
            case "source":
                doc.source = try Frontmatter.decodeSource(value)
            
            case "promoted_from":
                let promotedFrom = try list(key, value)
                doc.promotedFrom = promotedFrom.isEmpty ? nil : promotedFrom
            
            default:
                throw FieldTypeError(
                    field: key,
                    expected: "a known frontmatter field",
                    got: value
                )
            }
        }
    }
    
    // MARK: - Private
    private static func relativeToNotes(_ rel: String) throws -> String {
        let absolutePath = Paths.brainRoot.appendingPathComponent(rel).path
        let notesPrefix = Paths.notes.path + "/"
        
        guard absolutePath.hasPrefix(notesPrefix) else {
            throw NSError(domain: "Handlers", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "not under cortex/: \(rel)"
            ])
        }
        
        return String(absolutePath.dropFirst(notesPrefix.count))
    }
}
