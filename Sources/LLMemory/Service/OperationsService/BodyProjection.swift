//
//  BodyProjection.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

struct BodyProjection {
    // MARK: - Property
    private let composer = NoteComposer()

    // MARK: - Initializer
    // MARK: - Public
    func advance(
        op: [String: Any],
        name: String,
        handler: any OperationHandling,
        context: inout HandlerContext,
        scope: GRDBReadScope
    ) throws -> String? {
        switch name {
        case "create_note":
            if let noteId = op["id"] as? String, !noteId.isEmpty {
                context.stagedBodies[noteId] = try composer.composeCreateBody(op, scope)
                context.opaqueBodyIds.remove(noteId)
            }
            
            return nil
        
        case "patch_section":
            guard let noteId = op["id"] as? String, !noteId.isEmpty else { return nil }
            
            if context.opaqueBodyIds.contains(noteId) { return nil }
            
            guard let body = try stagedBody(of: noteId, context: context, scope: scope) else {
                context.opaqueBodyIds.insert(noteId)
                
                return nil
            }
            
            let newBody: String
            do {
                newBody = try SectionEdit.applyPatch(
                    body,
                    section: op["section"] as? String ?? "",
                    action: op["action"] as? String ?? "",
                    content: op["content"] as? String ?? "",
                    subtree: op["subtree"] as? Bool ?? false
                )
            } catch {
                return "\(error)"
            }
            
            let collisions = SectionEdit.findPathCollisions(newBody)
            if !collisions.isEmpty {
                let existingPaths = Set(
                    SectionEdit.findPathCollisions(body).map { collision in
                        collision.path.display()
                    }
                )
                let introduced = collisions.filter { collision in
                    !existingPaths.contains(collision.path.display())
                }
                
                if !introduced.isEmpty {
                    let details = introduced
                        .map { collision in collision.display() }
                        .joined(separator: "; ")
                    
                    return "section invariant violated — \(noteId): section path collision: \(details)"
                }
            }
            
            context.stagedBodies[noteId] = newBody
            
            return nil
        
        default:
            if try !handler.touches(op, scope).isEmpty {
                for noteId in handler.schema.mentionedNoteIds(in: op) {
                    context.opaqueBodyIds.insert(noteId)
                    context.stagedBodies.removeValue(forKey: noteId)
                }
            }
            
            return nil
        }
    }
    
    // MARK: - Private
    private func stagedBody(
        of noteId: String,
        context: HandlerContext,
        scope: GRDBReadScope
    ) throws -> String? {
        if let staged = context.stagedBodies[noteId] { return staged }
        
        guard let path = try scope.run(FetchNotePathTransaction(nid: noteId)) else { return nil }
        
        return (try? Notes.readNoteIfPresent(at: path))??.body
    }
}
