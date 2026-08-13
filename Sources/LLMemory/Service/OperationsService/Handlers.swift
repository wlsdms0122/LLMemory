//
//  Handlers.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

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
    case childSpecs
}

public struct OperationSchema: Sendable, Encodable {
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
            
            case .plain:
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

public struct OperationHandler: @unchecked Sendable {
    // MARK: - Property
    public let schema: OperationSchema
    public let validate: (_ op: [String: Any], _ context: HandlerContext, _ scope: GRDBReadScope) throws -> String?
    public let write: (_ op: [String: Any], _ context: HandlerContext, _ scope: GRDBScope) throws -> [String: Any]
    public let effect: (_ op: [String: Any]) -> [String: [String]]
    public let touches: (_ op: [String: Any], _ scope: GRDBReadScope) throws -> [URL]
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct HandlerContext {
    // MARK: - Property
    // The batch's ambient facts — resolved once at the apply/dry-run entry
    // so no handler re-derives them from process globals. The initializer
    // requires them: an unseeded context does not compile.
    public let sessionId: String?
    public let now: Int

    public var inFlightIds: Set<String> = []
    public var invalidatedIds: Set<String> = []
    public var removedIds: Set<String> = []
    public var lockedInFlightIds: Set<String> = []
    public var stagedBodies: [String: String] = [:]
    public var opaqueBodyIds: Set<String> = []
    
    // MARK: - Initializer
    public init(sessionId: String?, now: Int) {
        self.sessionId = sessionId
        self.now = now
    }

    // MARK: - Public
    // MARK: - Private
}

public struct ExistingState {
    // MARK: - Property
    public let ids: Set<String>
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

// A field that exists but is not this op's to set. Each has an op of its own,
// and the message says which — the whole point of refusing rather than merging.
struct ReservedFieldError: Error, CustomStringConvertible {
    // MARK: - Property
    let field: String

    var description: String {
        let owner: String

        switch field {
        case "id":
            owner = "migrate_note moves it"

        case "stale", "invalidated_at", "invalidated_reason":
            owner = "invalidate/revalidate own it"

        case "trashed_at", "trashed_reason":
            owner = "delete_note/restore_note own it"

        default:
            owner = "it is edited in the file only"
        }

        return "reserved field '\(field)' — \(owner)"
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public enum Handlers {
    // MARK: - Property
    public static let namespaceRegex = try! NSRegularExpression(pattern: #"^[a-z][a-z0-9_-]*$"#)
    public static let tagRegex = try! NSRegularExpression(pattern: #"^[a-z0-9][a-z0-9-]*$"#)
    public static let dateTailRegex = try! NSRegularExpression(pattern: #"(\d{6})(?:-\d+)?$"#)
    public static let headingMarkerRegex = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.+?)\s*$"#)
    
    public static let validPriority: Set<String> = ["eager", "lazy"]
    public static let creatableFlagKinds: Set<String> = ["reconsolidate", "stale_ref"]
    public static let resolvableFlagKinds: Set<String> = creatableFlagKinds.union(["enrich_review"])
    public static let validPatchActions: Set<String> = ["replace", "append", "prepend", "remove"]
    // Frontmatter is the SSoT of a note's knowledge, so set_frontmatter is open by
    // default: any key it does not recognise lands in `extra` and is projected to
    // note_extra. Only the fields below stay closed — each is either identity/path
    // (moved by migrate_note), a lifecycle state owned by its own op, or human-only.
    public static let frontmatterReserved: Set<String> = [
        "id", "template", "locked",
        "stale", "invalidated_at", "invalidated_reason",
        "trashed_at", "trashed_reason"
    ]
    public static let extraKeyRegex = try! NSRegularExpression(pattern: #"^[A-Za-z_]\w*$"#)
    
    // MARK: - Initializer
    // MARK: - Public
    // Whatever an op carries that its own schema does not name. For the ops that
    // author a note that is a custom frontmatter field — the caller means it for
    // the note, not for the op, and the note is where it belongs.
    public static func customFields(
        of op: [String: Any],
        declaredBy schema: OperationSchema
    ) -> [String: Any] {
        let declared = Set(schema.fields.map(\.name)).union(["op", "rationale"])

        return op.filter { entry in !declared.contains(entry.key) }
    }

    public static func existingState(_ scope: GRDBReadScope) throws -> ExistingState {
        ExistingState(ids: try scope.run(FetchNoteIdsTransaction()))
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
        scope: GRDBReadScope
    ) throws -> String? {
        if context.inFlightIds.contains(nid) { return nil }
        if try scope.run(NoteExistsTransaction(nid: nid)) { return nil }
        
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
        _ scope: GRDBScope,
        nid: String,
        opLabel: String,
        now: Int
    ) throws {
        try scope.run(RecordNoteLifecycleEventTransaction(nid: nid, kind: "edited", reason: opLabel, now: now))
    }
    
    public static func seedInitialLinks(_ scope: GRDBScope, nid: String, tags: [String]) throws {
        try scope.run(SeedInitialLinksTransaction(nid: nid, tags: tags))
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
    
    static func composeCreateBody(_ op: [String: Any], _ scope: GRDBReadScope) throws -> String {
        let raw = op["content"] as? String ?? ""
        var content = String(raw.reversed().drop(while: { character in character.isWhitespace }).reversed())
        let templateId = (op["template"] as? String).flatMap { value in value.isEmpty ? nil : value }
        
        if let templateId, content.isEmpty,
            let frame = try scope.run(LoadTemplateFrameTransaction(templateId: templateId)) {
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
    
    // The trash mirrors the cortex layout, so a trashed file's id is its path
    // under .trash/ read the same way — leaf label alone would only be the last
    // label of a dotted address.
    static func trashStemId(_ url: URL) -> String {
        guard let relative = Paths.relative(of: url) else { return trashName(url).nid }
        
        var labels = relative.split(separator: "/").map(String.init)
        
        guard labels.count > 2, labels[0] == "cortex", labels[1] == ".trash" else {
            return trashName(url).nid
        }
        
        labels[labels.count - 1] = trashName(url).nid
        
        return labels.dropFirst(2).joined(separator: ".")
    }
    
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
            
            guard trashStemId(url) == nid else { continue }
            
            let key = (doc.trashedAt ?? 0, trashName(url).counter)
            
            if best == nil || key > best!.key { best = (url, doc, body, key) }
        }
        
        if !unreadable.isEmpty {
            throw NotesError.trashUnreadable(nid: nid, files: unreadable, matched: best != nil)
        }
        
        return best.map { found in (url: found.url, doc: found.doc, body: found.body) }
    }
    
    static func mergeFields(_ doc: inout FrontmatterDoc, _ fields: [String: Any]) throws {
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

        // A custom field is one frontmatter line, so its value must be a scalar that
        // survives the `key: value` round trip — no newlines, no nesting.
        func scalar(_ key: String, _ value: Any) throws -> String {
            let text: String

            switch value {
            case let bool as Bool:
                text = bool ? "true" : "false"

            case let int as Int:
                text = String(int)

            case let double as Double:
                text = String(double)

            case let string as String:
                text = string

            default:
                throw FieldTypeError(field: key, expected: "string, number or bool", got: value)
            }

            let trimmed = text.trimmingCharacters(in: .whitespaces)

            guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else {
                throw FieldTypeError(
                    field: key,
                    expected: "a non-empty single-line value (null removes the field)",
                    got: value
                )
            }

            return trimmed
        }

        for (key, value) in fields {
            switch key {
            case "title":
                doc.title = try string(key, value)

            case "summary":
                doc.summary = try string(key, value)

            case "tags":
                doc.tags = try list(key, value)

            case "priority":
                doc.priority = try string(key, value)

            case "source":
                doc.source = try Frontmatter.decodeSource(value)

            case "promoted_from":
                let promotedFrom = try list(key, value)
                doc.promotedFrom = promotedFrom.isEmpty ? nil : promotedFrom

            case "entities":
                let entities = try list(key, value)
                doc.entities = entities.isEmpty ? nil : entities

            default:
                guard frontmatterReserved.contains(key) == false else {
                    throw ReservedFieldError(field: key)
                }

                guard extraKeyRegex.firstMatch(
                    in: key,
                    range: NSRange(location: 0, length: (key as NSString).length)
                ) != nil else {
                    throw FieldTypeError(
                        field: key,
                        expected: "a frontmatter key ([A-Za-z_]\\w*)",
                        got: value
                    )
                }

                if value is NSNull {
                    doc.extra.removeValue(forKey: key)
                } else {
                    doc.extra[key] = try scalar(key, value)
                }
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
