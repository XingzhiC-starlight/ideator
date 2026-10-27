import Foundation

/// The card folder: one `<CardID>.md` per card in ~/Documents/Ideator/ plus the hidden sidecar
/// `.cards.json` (a `SavedDesk`). Owns file naming, the sidecar encoding, atomic writes, and
/// the snapshot that makes saving idempotent. Nothing outside this file touches the folder.
///
/// Saves are a projection of the desk, never a log of edits: `save` compares the desk with what
/// it last read or wrote and applies only the difference. So a crash, a double save or an
/// outside edit can't leave the folder in a state the next save doesn't repair. `save` also
/// reports whether the folder now matches the desk, so a caller never mistakes a failed write
/// for a folder that is merely behind.
final class Library {
    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Documents/Ideator", directoryHint: .isDirectory)

    let folder: URL
    /// What the folder held after our last read or write. `save` writes only what differs.
    private var notesOnDisk: [CardID: Note] = [:]
    private var savedOnDisk: SavedDesk?
    /// The sidecar was written by a newer Ideator (its `version` is above ours), as when two Macs
    /// share the folder and one is not updated yet. This build can't know what that file holds, so
    /// it places cards as best it can and never overwrites it. Card files are still saved.
    private(set) var sidecarIsNewer = false
    /// `load` could not list the folder (macOS refused, a volume was not mounted), so the desk
    /// started empty while the sidecar on disk still describes the real arrangement. This run
    /// never writes the sidecar; the next launch reads it. Card files are still saved, and a
    /// rescan still takes the folder's cards in, into the stack.
    private(set) var folderUnread = false

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(folder: URL) {
        self.folder = folder
    }

    /// Creates the folder if needed, reads every card file and the sidecar, rebuilds the desk.
    /// A missing or corrupt sidecar is not an error: every card simply starts in the stack. A
    /// folder that can't be listed opens empty and sets `folderUnread`.
    func load() -> Desk {
        createFolder()
        let notes: [CardID: Note]
        do {
            notes = try readNotes()
            folderUnread = false
        } catch {
            log("Could not list \(folder.path): \(error.localizedDescription)")
            notes = [:]
            folderUnread = true
        }
        let data = try? Data(contentsOf: sidecarURL)
        sidecarIsNewer = Self.isNewer(data)
        let saved = data.flatMap { try? JSONDecoder().decode(SavedDesk.self, from: $0) } ?? SavedDesk()
        notesOnDisk = notes
        savedOnDisk = saved
        return Desk(notes: notes, saved: saved)
    }

    /// Makes the folder match `desk` and returns whether it now does:
    /// - a missing folder (deleted or unmounted since `load`) → create it and forget the snapshot,
    ///   which no longer describes the disk, so every card and the sidecar are written again;
    /// - a card whose note differs from `notesOnDisk` (or is new) → write `<id>.md` atomically;
    /// - an id in `notesOnDisk` the desk no longer has → move that file to the Trash
    ///   (recoverable; a file already gone is fine);
    /// - `desk.saved != savedOnDisk` → read the sidecar's version again, since another Mac may have
    ///   written the file while this one ran, then write the sidecar atomically, unless it is
    ///   newer or `folderUnread`: then it is left alone and counts as matching, since not writing
    ///   it is the point.
    /// Each successful step updates the snapshot; a failed one leaves it, so the next save retries,
    /// and the result is false.
    @discardableResult
    func save(_ desk: Desk) -> Bool {
        if !FileManager.default.fileExists(atPath: folder.path) {
            guard createFolder() else { return false }
            notesOnDisk = [:]
            savedOnDisk = nil
            sidecarIsNewer = false   // the newer sidecar went with the folder
            folderUnread = false     // and the new folder is known to be empty
        }
        var matches = true
        let current = Dictionary(desk.allCards.map { ($0.id, $0.note) }, uniquingKeysWith: { first, _ in first })
        for (id, note) in current where notesOnDisk[id] != note {
            do {
                try Data(note.markdown.utf8).write(to: url(of: id), options: .atomic)
                notesOnDisk[id] = note
            } catch {
                log("Could not save \(id.rawValue).md: \(error.localizedDescription)")
                matches = false
            }
        }
        for id in notesOnDisk.keys where current[id] == nil {
            let file = url(of: id)
            if FileManager.default.fileExists(atPath: file.path) {
                do {
                    try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                } catch {
                    log("Could not move \(id.rawValue).md to the Trash: \(error.localizedDescription)")
                    matches = false
                    continue
                }
            }
            notesOnDisk[id] = nil
        }
        let saved = desk.saved
        if saved != savedOnDisk, !folderUnread {
            // Another Mac may have arranged the folder since we read it: check the version again.
            sidecarIsNewer = Self.isNewer(try? Data(contentsOf: sidecarURL))
            if !sidecarIsNewer {
                do {
                    try encoder.encode(saved).write(to: sidecarURL, options: .atomic)
                    savedOnDisk = saved
                } catch {
                    log("Could not save the sidecar: \(error.localizedDescription)")
                    matches = false
                }
            }
        }
        return matches
    }

    /// Re-reads the card files to pick up files added, removed or edited outside the app. Not the
    /// sidecar: the app is its only writer. Returns nil when the folder can't be listed, so a
    /// transient failure never looks like "every card was deleted". Resets the note snapshot to
    /// what it read, so the following `save` doesn't write those notes straight back.
    /// The caller saves first, so anything that differs now was changed outside the app.
    /// `folderUnread` stays: the cards found go to the stack, not to the places the sidecar
    /// holds for them, so writing it now would still lose that arrangement.
    func rescan() -> [CardID: Note]? {
        guard let notes = try? readNotes() else { return nil }
        notesOnDisk = notes
        return notes
    }

    @discardableResult
    private func createFolder() -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return true
        } catch {
            log("Could not create \(folder.path): \(error.localizedDescription)")
            return false
        }
    }

    private var sidecarURL: URL { folder.appending(path: ".cards.json") }

    /// Whether sidecar `data` was written by a newer Ideator. Reads the version on its own: a
    /// newer sidecar may not decode as a SavedDesk at all. No file, or no version, is not newer.
    private static func isNewer(_ data: Data?) -> Bool {
        let version = data.flatMap { try? JSONDecoder().decode(SidecarVersion.self, from: $0) }?.version
        return (version ?? 0) > SavedDesk().version
    }

    private func url(of id: CardID) -> URL { folder.appending(path: id.rawValue + ".md") }

    /// Every non-hidden `*.md` file directly in the folder (no subfolders), read as UTF-8.
    /// The id is the file name minus ".md". Unreadable single files are skipped, not fatal.
    private func readNotes() throws -> [CardID: Note] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles])
        var notes: [CardID: Note] = [:]
        for url in urls where url.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            notes[CardID(rawValue: url.deletingPathExtension().lastPathComponent)] = Note(markdown: text)
        }
        return notes
    }

    private func log(_ message: String) {
        NSLog("Ideator: %@", message)
    }
}

/// Just the sidecar's `version`, readable whatever else a newer build put in the file.
private struct SidecarVersion: Decodable {
    var version: Int
}
