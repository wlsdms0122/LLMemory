//
//  SplitNoteHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct SplitNoteHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "split a note into ≥2 children by section paths; routes the source's links/aliases/meta across new ids",
        fields: [
            .required("from_id", role: .noteId, "source note id"),
            .required("into", role: .childSpecs, "list (≥2) of child specs: each requires {id, title, tags, summary, sections}; optional {priority, source, content_prefix}"),
            .optional("remainder", ##"{"keep": bool} — if true and remainder is non-empty, keep src note with leftover sections; default false (delete src)"##),
            .optional("routing", ##"list resolving a split conflict — each {type:"link"|"term", <identity>, to:[child ids]}. identity: link→{kind,neighbor}, term→{term}. to=["a"] assign, ["a","b"] copy, []=drop; omitted artifacts drop. cooccur/reference are auto-handled. A source-deleting split with unrouted assoc/lineage links or active aliases returns a `conflict` listing them."##)
        ],
        example: ###"{"op":"split_note","from_id":"persona.big-note","into":[{"id":"persona.big-note.a","title":"A","tags":["persona"],"summary":"...","sections":["## A"]},{"id":"persona.big-note.b","title":"B","tags":["persona"],"summary":"...","sections":["## B"]}]}"###
    )
    
    private let noteExistence = NoteExistence()
    private let sourceInput = NoteSourceInput()
    
    private let sectionEdit = SectionEdit()
    
    private let frontmatter = Frontmatter()
    
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let fromId = op["from_id"] as? String ?? ""
        
        if let rejection = try noteExistence.rejectionForUnknown(fromId, context: context, scope: scope) {
            return rejection
        }
        
        guard let into = op["into"] as? [[String: Any]], into.count >= 2 else {
            return "into must be a list of at least 2 child specs"
        }
        
        var newIds = Set<String>()
        var normalized: [[String: Any]] = into
        var allPaths: [SectionEdit.SectionPath] = []
        
        for index in 0..<into.count {
            let child = into[index]
            
            for field in ["id", "title", "tags", "summary", "sections"] {
                if child[field] == nil {
                    return "into[\(index)] missing/empty field: \(field)"
                }
                
                if let value = child[field] as? String, value.isEmpty {
                    return "into[\(index)] missing/empty field: \(field)"
                }
            }
            
            let childId = child["id"] as! String
            let nsChildId = childId as NSString
            
            if NoteAddress.idRegex.firstMatch(
                in: childId,
                range: NSRange(location: 0, length: nsChildId.length)
            ) == nil {
                return "into[\(index)] invalid id: \(childId)"
            }
            
            if childId != fromId,
                try noteExistence.isTaken(childId, context: context, scope: scope) {
                return "into[\(index)] id collision: \(childId)"
            }
            
            if newIds.contains(childId) { return "into[\(index)] duplicate id: \(childId)" }
            
            newIds.insert(childId)
            
            guard let tags = child["tags"] as? [Any], !tags.isEmpty else {
                return "into[\(index)] tags must be non-empty list"
            }
            
            guard let sections = child["sections"] as? [Any], !sections.isEmpty else {
                return "into[\(index)] sections must be non-empty list"
            }
            
            if let rejection = sourceInput.sourceInputError(child["source"]) {
                return "into[\(index)] \(rejection)"
            }
            
            var normalizedSections: [String] = []
            
            for rawSection in sections {
                var section = (rawSection as? String ?? "")
                    .trimmingCharacters(in: .whitespaces)
                
                if !section.isEmpty && !section.hasPrefix("#") {
                    section = "## \(section)"
                }
                
                let parsed: SectionEdit.SectionPath
                do {
                    parsed = try sectionEdit.parsePath(section)
                } catch {
                    return "into[\(index)] invalid section path '\(section)': \(error)"
                }
                
                allPaths.append(parsed)
                normalizedSections.append(section)
            }
            
            normalized[index]["sections"] = normalizedSections
        }
        
        if let srcPath = try scope.run(FetchNotePathTransaction(nid: fromId)),
            let raw = try? String(contentsOf: srcPath, encoding: .utf8) {
            let (_, srcBody) = try frontmatter.parse(raw)
            
            do {
                _ = try sectionEdit.resolveDisjoint(srcBody, paths: allPaths)
            } catch {
                return "into sections do not form a valid split of '\(fromId)': \(error)"
            }
        }
        
        let routing = parseRouting(op)
        
        for (_, targets) in routing {
            for target in targets where !newIds.contains(target) {
                return "routing target '\(target)' is not one of the new children"
            }
        }
        
        let keepSrc = (op["remainder"] as? [String: Any])?["keep"] as? Bool ?? false
        
        if !keepSrc {
            let uncovered = try uncoveredRouteArtifacts(scope, fromId: fromId, routing: routing)
            
            if !uncovered.isEmpty {
                throw SplitConflict(fromId: fromId, unresolved: uncovered)
            }
        }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let fromId = op["from_id"] as! String
        
        guard let srcPath = try scope.run(FetchNotePathTransaction(nid: fromId)),
            FileManager.default.fileExists(atPath: srcPath.path)
        else {
            throw OperationError.noteFileMissing(op: "split_note", id: fromId)
        }
        
        let (srcDoc, srcBody) = try frontmatter.parse(
            try String(contentsOf: srcPath, encoding: .utf8)
        )
        let (outboundEdges, inboundEdges) = try scope.run(FetchLinkFanTransaction(fromId: fromId))
        let routing = parseRouting(op)
        let srcTerms = try scope.run(FetchActiveTermRowsTransaction(noteId: fromId))
        var written: [URL] = []
        var newIds: [String] = []
        let now = context.now
        var remaining = srcBody
        let intoChildren = (op["into"] as? [[String: Any]]) ?? []
        
        for child in intoChildren {
            let rawSections = (child["sections"] as? [Any])?
                .compactMap { section in section as? String } ?? []
            let normalizedSections = rawSections.map { section -> String in
                let trimmed = section.trimmingCharacters(in: .whitespaces)
                
                return (trimmed.hasPrefix("#") || trimmed.isEmpty) ? trimmed : "## \(trimmed)"
            }
            let sectionPaths = try normalizedSections.map { section in
                try sectionEdit.parsePath(section)
            }
            let (extracted, rest) = try sectionEdit.extract(remaining, paths: sectionPaths)
            remaining = rest
            
            let childId = child["id"] as! String
            let childPath = scope.brain.path.file(forId: childId)
            
            try FileManager.default.createDirectory(
                at: childPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            var childDoc = FrontmatterDocument(
                title: child["title"] as? String ?? "",
                priority: child["priority"] as? String ?? "lazy",
                summary: child["summary"] as? String ?? "",
                tags: (child["tags"] as? [Any])?.compactMap { tag in tag as? String } ?? []
            )
            childDoc.source = child["source"] != nil
                ? try sourceInput.finalizeSource(child["source"])
                : srcDoc.source
            
            let prefix = (child["content_prefix"] as? String).map { text in
                String(
                    text.reversed().drop(while: { character in character.isWhitespace }).reversed()
                ) + "\n\n"
            } ?? ""
            let content = prefix + extracted
            
            try (frontmatter.dump(childDoc) + content).write(
                to: childPath,
                atomically: true,
                encoding: .utf8
            )
            try scope.run(ReindexNoteFileTransaction(path: childPath))
            try scope.run(InheritSourceObservationTransaction(from: fromId, to: childId))
            try scope.run(StampNoteLifecycleTransaction(nid: childId, now: now, isNew: true))
            
            written.append(childPath)
            newIds.append(childId)
        }
        
        let keepRemainder = ((op["remainder"] as? [String: Any])?["keep"] as? Bool) ?? false
        let sourceSurvives = keepRemainder
            && !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if keepRemainder && !sourceSurvives {
            let uncovered = try uncoveredRouteArtifacts(scope.readOnly, fromId: fromId, routing: routing)
            
            if !uncovered.isEmpty {
                throw SplitConflict(fromId: fromId, unresolved: uncovered)
            }
        }
        
        if sourceSurvives {
            try (frontmatter.dump(srcDoc) + remaining).write(
                to: srcPath,
                atomically: true,
                encoding: .utf8
            )
            try scope.run(ReindexNoteFileTransaction(path: srcPath))
            try scope.run(StampNoteLifecycleTransaction(nid: fromId, now: now, isNew: false))
        } else {
            _ = try scope.run(FlagInboundReferrersTransaction(
                targetId: fromId,
                reason: "split into \(newIds.joined(separator: ", "))",
                now: now
            ))
            try scope.run(DeleteNoteRowTransaction(nid: fromId))
            try Trash(path: scope.brain.path).file(
                srcPath,
                reason: "split into \(newIds.joined(separator: ", "))",
                now: now
            )
        }
        
        let share = Double(max(1, newIds.count))
        
        func insertEdge(
            child: String,
            other: String,
            outbound: Bool,
            _ edge: LinkEdge,
            weight: Double
        ) throws {
            let src = outbound ? child : other
            let dst = outbound ? other : child
            
            try scope.run(AddLinkTransaction(
                src: src,
                dst: dst,
                kind: edge.kind,
                weight: weight,
                createdAt: edge.createdAt,
                lastActivatedAt: edge.lastActivatedAt,
                provenance: edge.provenance
            ))
        }
        
        func redistribute(_ edges: [LinkEdge], outbound: Bool) throws {
            for edge in edges where edge.other != fromId {
                // An edge whose kind this binary does not know redistributes
                // like a learned one — the reading that neither rebuilds it
                // from a source it has no reader for nor throws it away.
                let policy = LinkKind(rawValue: edge.kind)
                    .map { kind in NoteArtifactPolicy.splitPolicy(for: kind) }

                switch policy ?? .autoRedistribute {
                case .rebuild, .drop:
                    continue
                
                case .route, .routeRevalidate:
                    if let targets = routing[routingKey(
                        type: "link",
                        kind: edge.kind,
                        neighbor: edge.other,
                        term: nil
                    )] {
                        for noteId in targets {
                            try insertEdge(
                                child: noteId,
                                other: edge.other,
                                outbound: outbound,
                                edge,
                                weight: edge.weight
                            )
                        }
                    } else {
                        for noteId in newIds {
                            try insertEdge(
                                child: noteId,
                                other: edge.other,
                                outbound: outbound,
                                edge,
                                weight: edge.weight / share
                            )
                        }
                    }
                
                case .autoRedistribute:
                    for noteId in newIds {
                        try insertEdge(
                            child: noteId,
                            other: edge.other,
                            outbound: outbound,
                            edge,
                            weight: edge.weight / share
                        )
                    }
                
                case .autoCopy:
                    for noteId in newIds {
                        try insertEdge(
                            child: noteId,
                            other: edge.other,
                            outbound: outbound,
                            edge,
                            weight: edge.weight
                        )
                    }
                }
            }
        }
        
        try redistribute(outboundEdges, outbound: true)
        try redistribute(inboundEdges, outbound: false)
        
        for noteId in newIds { try scope.run(NormalizeUndirectedLinksTransaction(nodeId: noteId)) }
        
        try scope.run(LinkSiblingsTransaction(
            ids: sourceSurvives ? newIds + [fromId] : newIds,
            now: now
        ))
        
        if !sourceSurvives {
            for row in srcTerms {
                let kind = row.kind
                let term = row.term
                let provenance = row.provenance
                
                guard let targets = routing[routingKey(
                    type: "term",
                    kind: nil,
                    neighbor: nil,
                    term: term
                )] else {
                    continue
                }
                
                for noteId in targets {
                    try scope.run(InsertPendingTermIfAbsentTransaction(
                        noteId: noteId,
                        kind: kind,
                        term: term,
                        provenance: provenance,
                        now: now
                    ))
                }
            }
            
            try scope.run(DeleteNoteLinksTransaction(noteId: fromId))
        }
        
        return [
            "status": "ok",
            "paths": written.map { path in path.path },
            "ids": newIds,
            "note": "split \(fromId) -> \(newIds.count) children"
        ]
    }
    
    func effect(_ op: [String: Any]) -> [String: [String]] {
        let into = (op["into"] as? [[String: Any]]) ?? []
        let newIds = into.compactMap { child in child["id"] as? String }
        let keep = ((op["remainder"] as? [String: Any])?["keep"] as? Bool) ?? false
        let fromId = op["from_id"] as? String ?? ""
        var effects: [String: [String]] = ["creates": newIds]
        
        if !keep && !newIds.contains(fromId) {
            effects["removes"] = [fromId]
        }
        
        return effects
    }
    
    func touches(_ op: [String: Any], _ scope: GRDBReadScope) throws -> [URL] {
        var paths: [URL] = []
        
        if let fromId = op["from_id"] as? String, let src = try scope.run(FetchNotePathTransaction(nid: fromId)) {
            paths.append(src)
            
            if let trashPath = Trash(path: scope.brain.path).destination(of: src) { paths.append(trashPath) }
        }
        
        for child in (op["into"] as? [[String: Any]]) ?? [] {
            if let childId = child["id"] as? String {
                paths.append(scope.brain.path.file(forId: childId))
            }
        }
        
        return paths
    }
    
    // MARK: - Private
    private func routingKey(
        type: String,
        kind: String?,
        neighbor: String?,
        term: String?
    ) -> String {
        switch type {
        case "link":
            return "link\u{1}\(kind ?? "")\u{1}\(neighbor ?? "")"
        
        case "term":
            return "term\u{1}\(term ?? "")"
        
        default:
            return "?\u{1}\(type)"
        }
    }
    
    private func routeArtifactKey(_ artifact: RouteArtifact) -> String {
        routingKey(
            type: artifact.type,
            kind: artifact.kind,
            neighbor: artifact.neighbor,
            term: artifact.term
        )
    }
    
    private func parseRouting(_ op: [String: Any]) -> [String: [String]] {
        var map: [String: [String]] = [:]
        
        for entry in (op["routing"] as? [[String: Any]]) ?? [] {
            let type = entry["type"] as? String ?? ""
            let targets = (entry["to"] as? [Any])?.compactMap { target in target as? String } ?? []
            
            map[routingKey(
                type: type,
                kind: entry["kind"] as? String,
                neighbor: entry["neighbor"] as? String,
                term: entry["term"] as? String
            )] = targets
        }
        
        return map
    }
    
    private func uncoveredRouteArtifacts(
        _ scope: GRDBReadScope,
        fromId: String,
        routing: [String: [String]]
    ) throws -> [RouteArtifact] {
        try scope.run(FetchSplitRouteTargetsTransaction(noteId: fromId)).filter { artifact in
            routing[routeArtifactKey(artifact)] == nil
        }
    }
}
