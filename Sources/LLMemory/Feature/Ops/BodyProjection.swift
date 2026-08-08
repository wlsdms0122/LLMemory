//
//  BodyProjection.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

enum BodyProjection {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func advance(
        op: [String: Any],
        name: String,
        handler: OpHandler,
        context: inout HandlerContext,
        db: Database
    ) throws -> String? {
        switch name {
        case "create_note":
            if let noteId = op["id"] as? String, !noteId.isEmpty {
                context.stagedBodies[noteId] = try Handlers.composeCreateBody(op, db)
                context.opaqueBodyIds.remove(noteId)
            }
            
            return nil
        
        case "patch_section":
            guard let noteId = op["id"] as? String, !noteId.isEmpty else { return nil }
            
            if context.opaqueBodyIds.contains(noteId) { return nil }
            
            guard let body = try stagedBody(of: noteId, context: context, db: db) else {
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
            if try !handler.touches(op, db).isEmpty {
                for noteId in OpsTransaction.targetIds(op, schema: handler.schema) {
                    context.opaqueBodyIds.insert(noteId)
                    context.stagedBodies.removeValue(forKey: noteId)
                }
            }
            
            return nil
        }
    }
    
    // MARK: - Private
    private static func stagedBody(
        of noteId: String,
        context: HandlerContext,
        db: Database
    ) throws -> String? {
        if let staged = context.stagedBodies[noteId] { return staged }
        
        guard let path = try Notes.pathOf(db, nid: noteId) else { return nil }
        
        return (try? Notes.readNoteIfPresent(at: path))??.body
    }
}
