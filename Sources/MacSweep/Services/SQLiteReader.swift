import Foundation
import SQLite3

/// Lettore SQLite minimale, solo lettura.
final class SQLiteReader {
    private var db: OpaquePointer?

    init?(path: String) {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
    }

    deinit { sqlite3_close(db) }

    /// Esegue una query e restituisce ogni riga come array di stringhe opzionali.
    /// Se la tabella non esiste (versioni diverse di WhatsApp) non restituisce nulla.
    func rows(_ sql: String) -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String?]] = []
        let columns = sqlite3_column_count(statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append((0..<columns).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) }
            })
        }
        return result
    }
}
