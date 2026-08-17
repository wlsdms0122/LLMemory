//
//  BodyProjection.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

struct BodyProjection {
    // MARK: - Property
    private let composer = NoteComposer()
    
    private let sectionEdit = SectionEdit()
    
    private let noteFile = NoteFile()
    
    // MARK: - Initializer
    // MARK: - Public
    func advance(
        op: [String: Any],
        name: String,
        handler: any OperationHandling,
        context: inout HandlerContext,
        db: Database
    ) throws -> String? {
        switch name {
        case "create_note":
            if let noteId = op["id"] as? String, !noteId.isEmpty {
                context.stagedBodies[noteId] = try composer.composeCreateBody(op, db, context.brain)
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
                newBody = try sectionEdit.applyPatch(
                    body,
                    section: op["section"] as? String ?? "",
                    action: op["action"] as? String ?? "",
                    content: op["content"] as? String ?? "",
                    subtree: op["subtree"] as? Bool ?? false
                )
            } catch {
                return "\(error)"
            }
            
            let collisions = sectionEdit.findPathCollisions(newBody)
            if !collisions.isEmpty {
                let existingPaths = Set(
                    sectionEdit.findPathCollisions(body).map { collision in
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
            if try !handler.touches(op, context, db).isEmpty {
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
        db: Database
    ) throws -> String? {
        if let staged = context.stagedBodies[noteId] { return staged }
        
        guard let path = try context.brain.notePath(db, noteId) else { return nil }
        
        return (try? noteFile.readNoteIfPresent(at: path))??.body
    }
}
