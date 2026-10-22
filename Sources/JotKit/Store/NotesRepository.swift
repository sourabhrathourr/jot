import Foundation

public struct Note: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var text: String
    public var rawContent: String?
    public var pinned: Double?
    public var caretPosition: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var lastAccessedAt: Date

    public var isPinned: Bool { pinned != nil }

    public var blocks: [Block] {
        if let rawContent, let blocks = TiptapCodec.decodeString(rawContent) { return blocks }
        return text.components(separatedBy: "\n").map(Block.paragraph)
    }
}

/// Persistence for notes. Mirrors Raycast's `notes` table (see docs/DESIGN.md).
final class NotesRepository {
    private let db: SQLiteDatabase
    /// Image files, in `Attachments/` beside the database.
    let attachments: AttachmentStore

    init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        attachments = AttachmentStore(directory: AttachmentStore.directory(forDatabase: path))
        try migrate()
    }

    static func defaultPath() throws -> String {
        if let override = ProcessInfo.processInfo.environment["JOT_DB"] { return override }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Jot", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jot.db").path
    }

    private func migrate() throws {
        if db.userVersion < 1 {
            try db.execute("""
                CREATE TABLE IF NOT EXISTS notes (
                  id TEXT NOT NULL PRIMARY KEY,
                  title TEXT,
                  text TEXT NOT NULL,
                  raw_content TEXT,
                  pinned REAL,
                  caret_position INTEGER NOT NULL DEFAULT 0,
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL,
                  deleted_at TEXT,
                  last_accessed_at TEXT NOT NULL
                ) STRICT, WITHOUT ROWID
                """)
            try db.execute("CREATE INDEX IF NOT EXISTS notes_updated_at ON notes (updated_at DESC)")
            db.userVersion = 1
        }
    }

    // MARK: Reads

    func note(id: String) -> Note? {
        (try? db.query("SELECT * FROM notes WHERE id = ?", [.text(id)]))?.first.flatMap(Self.note)
    }

    /// Live notes: pinned first (by pin order), then most recently updated.
    func list(search: String = "") -> [Note] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var sql = "SELECT * FROM notes WHERE deleted_at IS NULL"
        var bindings: [SQLiteDatabase.Value] = []
        if !term.isEmpty {
            sql += " AND (title LIKE ? ESCAPE '\\' OR text LIKE ? ESCAPE '\\')"
            let pattern = "%" + term.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
            bindings = [.text(pattern), .text(pattern)]
        }
        sql += " ORDER BY pinned IS NULL, pinned ASC, updated_at DESC"
        return ((try? db.query(sql, bindings)) ?? []).compactMap(Self.note)
    }

    /// Recently Deleted, newest first.
    func listDeleted(search: String = "") -> [Note] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows = (try? db.query("SELECT * FROM notes WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC")) ?? []
        let notes = rows.compactMap(Self.note)
        return term.isEmpty ? notes : notes.filter { $0.title.lowercased().contains(term) || $0.text.lowercased().contains(term) }
    }

    func deleteAll() {
        try? db.execute("UPDATE notes SET deleted_at = ?, pinned = NULL WHERE deleted_at IS NULL", [.text(Self.format(.now))])
    }

    func mostRecentlyAccessed() -> Note? {
        (try? db.query("SELECT * FROM notes WHERE deleted_at IS NULL ORDER BY last_accessed_at DESC LIMIT 1"))?
            .first.flatMap(Self.note)
    }

    // MARK: Writes

    @discardableResult
    func create(blocks: [Block] = [Block(kind: .paragraph)]) -> Note {
        let now = Date.now
        let note = Note(
            id: ULID.make(date: now),
            title: blocks.title,
            text: blocks.plainText,
            rawContent: TiptapCodec.encodeString(blocks),
            pinned: nil,
            caretPosition: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            lastAccessedAt: now
        )
        try? db.execute(
            "INSERT INTO notes (id, title, text, raw_content, caret_position, created_at, updated_at, last_accessed_at) VALUES (?, ?, ?, ?, 0, ?, ?, ?)",
            [.text(note.id), .text(note.title), .text(note.text), .text(note.rawContent ?? ""),
             .text(Self.format(now)), .text(Self.format(now)), .text(Self.format(now))]
        )
        return note
    }

    func save(id: String, blocks: [Block], caret: Int) {
        try? db.execute(
            "UPDATE notes SET title = ?, text = ?, raw_content = ?, caret_position = ?, updated_at = ? WHERE id = ?",
            [.text(blocks.title), .text(blocks.plainText), .text(TiptapCodec.encodeString(blocks)),
             .int(Int64(caret)), .text(Self.format(.now)), .text(id)]
        )
    }

    func saveCaret(id: String, caret: Int) {
        try? db.execute("UPDATE notes SET caret_position = ? WHERE id = ?", [.int(Int64(caret)), .text(id)])
    }

    func touchAccessed(id: String) {
        try? db.execute("UPDATE notes SET last_accessed_at = ? WHERE id = ?", [.text(Self.format(.now)), .text(id)])
    }

    func setPinned(id: String, _ pinned: Bool) {
        if pinned {
            let next = ((try? db.query("SELECT MAX(pinned) AS m FROM notes"))?.first?["m"]?.doubleValue ?? 0) + 1
            try? db.execute("UPDATE notes SET pinned = ? WHERE id = ?", [.real(next), .text(id)])
        } else {
            try? db.execute("UPDATE notes SET pinned = NULL WHERE id = ?", [.text(id)])
        }
    }

    /// Soft delete, like Raycast's trash.
    func delete(id: String) {
        try? db.execute("UPDATE notes SET deleted_at = ?, pinned = NULL WHERE id = ?", [.text(Self.format(.now)), .text(id)])
    }

    func restore(id: String) {
        try? db.execute("UPDATE notes SET deleted_at = NULL WHERE id = ?", [.text(id)])
    }

    // MARK: Row mapping

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func format(_ date: Date) -> String { formatter.string(from: date) }
    private static func parse(_ value: SQLiteDatabase.Value?) -> Date? { value?.stringValue.flatMap(formatter.date(from:)) }

    private static func note(_ row: [String: SQLiteDatabase.Value]) -> Note? {
        guard let id = row["id"]?.stringValue else { return nil }
        return Note(
            id: id,
            title: row["title"]?.stringValue ?? "Untitled",
            text: row["text"]?.stringValue ?? "",
            rawContent: row["raw_content"]?.stringValue,
            pinned: row["pinned"]?.doubleValue,
            caretPosition: row["caret_position"]?.intValue ?? 0,
            createdAt: parse(row["created_at"]) ?? .now,
            updatedAt: parse(row["updated_at"]) ?? .now,
            deletedAt: parse(row["deleted_at"]),
            lastAccessedAt: parse(row["last_accessed_at"]) ?? .now
        )
    }
}
