//
//  TrashedNoteLookup.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Reading cortex/.trash/. A trashed file keeps the note's address in its name
// and gains a counter when the address was already taken, so finding "the
// trashed copy of this id" means picking the most recently trashed of
// however many share it.
//
// It sits beside Trash for the same reason Trash does: this is filesystem and
// markdown and nothing else, and restore is not more entitled to it than
// anything else that needs to look.
struct TrashedNoteLookup {
    // MARK: - Property
    private let layout: BrainLayout

    private let noteFile = NoteFile()

    // MARK: - Initializer
    init(layout: BrainLayout) {
        self.layout = layout
    }

    // MARK: - Public
    func trashName(_ url: URL) -> (nid: String, counter: Int) {
        let stem = url.deletingPathExtension().lastPathComponent
        
        if let last = stem.split(separator: ".").last, let counter = Int(last) {
            return (String(stem.dropLast(last.count + 1)), counter)
        }
        
        return (stem, 0)
    }

    // The trash mirrors the cortex layout, so a trashed file's id is its path
    // under .trash/ read the same way — leaf label alone would only be the last
    // label of a dotted address.
    func trashStemId(_ url: URL) -> String {
        guard let relative = layout.relative(of: url) else { return trashName(url).nid }
        
        var labels = relative.split(separator: "/").map(String.init)
        
        guard labels.count > 2, labels[0] == "cortex", labels[1] == ".trash" else {
            return trashName(url).nid
        }
        
        labels[labels.count - 1] = trashName(url).nid
        
        return labels.dropFirst(2).joined(separator: ".")
    }

    func findTrashedFile(
        _ nid: String
    ) throws -> (url: URL, doc: FrontmatterDocument, body: String)? {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: layout.trash.path) else { return nil }
        
        guard let iterator = fileManager.enumerator(
            at: layout.trash,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        
        var best: (url: URL, doc: FrontmatterDocument, body: String, key: (Int, Int))?
        var unreadable: [String] = []
        
        for case let url as URL in iterator {
            guard url.pathExtension == "md" else { continue }
            
            let doc: FrontmatterDocument
            let body: String
            do {
                guard let read = try noteFile.readNoteIfPresent(at: url) else { continue }
                
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

    // MARK: - Private
}
