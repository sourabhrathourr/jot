import Foundation
import SQLite3

nonisolated enum SQLiteError: Error, CustomStringConvertible {
    case open(String), prepare(String, sql: String), step(String)

    var description: String {
        switch self {
        case .open(let m): "open: \(m)"
        case .prepare(let m, let sql): "prepare: \(m) — \(sql)"
        case .step(let m): "step: \(m)"
        }
    }
}

/// A deliberately tiny wrapper over the sqlite3 C API. One connection, main actor.
nonisolated final class SQLiteDatabase {
    enum Value {
        case text(String), int(Int64), real(Double), null
    }

    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw SQLiteError.open(String(cString: sqlite3_errmsg(handle)))
        }
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String, _ bindings: [Value] = []) throws {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.step(String(cString: sqlite3_errmsg(handle)))
        }
    }

    func query(_ sql: String, _ bindings: [Value] = []) throws -> [[String: Value]] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: Value]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw SQLiteError.step(String(cString: sqlite3_errmsg(handle))) }
            var row: [String: Value] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                row[name] = switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: .int(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(statement, column)))
                default: .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    var userVersion: Int {
        get { (try? query("PRAGMA user_version").first?["user_version"]?.intValue).flatMap { $0 } ?? 0 }
        set { try? execute("PRAGMA user_version = \(newValue)") }
    }

    private func prepare(_ sql: String, _ bindings: [Value]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(handle)), sql: sql)
        }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let s): sqlite3_bind_text(statement, index, s, -1, Self.transient)
            case .int(let i): sqlite3_bind_int64(statement, index, i)
            case .real(let d): sqlite3_bind_double(statement, index, d)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }
}

nonisolated extension SQLiteDatabase.Value {
    var stringValue: String? { if case .text(let s) = self { s } else { nil } }
    var intValue: Int? { if case .int(let i) = self { Int(i) } else { nil } }
    var doubleValue: Double? {
        switch self {
        case .real(let d): d
        case .int(let i): Double(i)
        default: nil
        }
    }
}
