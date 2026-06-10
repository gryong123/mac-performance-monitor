import CSQLite
import Foundation

final class HistoryStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "PerformanceMonitor.HistoryStore")
    private var database: OpaquePointer?

    init(databaseURL: URL? = nil) {
        let url = databaseURL ?? Self.defaultDatabaseURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if sqlite3_open(url.path, &database) == SQLITE_OK {
            createSchema()
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func upsertMinute(_ snapshot: MetricSnapshot) {
        queue.async { [weak self] in
            guard let self, let database = self.database else { return }
            let bucket = Int(snapshot.timestamp.timeIntervalSince1970 / 60) * 60
            let sql = """
            INSERT INTO metric_history(timestamp, cpu, memory, samples)
            VALUES (?, ?, ?, 1)
            ON CONFLICT(timestamp) DO UPDATE SET
                cpu = ((cpu * samples) + excluded.cpu) / (samples + 1),
                memory = ((memory * samples) + excluded.memory) / (samples + 1),
                samples = samples + 1;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, sqlite3_int64(bucket))
            sqlite3_bind_double(statement, 2, snapshot.cpuPercent)
            sqlite3_bind_double(statement, 3, snapshot.memoryPercent)
            sqlite3_step(statement)
        }
    }

    func samples(since date: Date, completion: @escaping @Sendable ([HistoricalSample]) -> Void) {
        queue.async { [weak self] in
            guard let self, let database = self.database else {
                completion([])
                return
            }

            let sql = """
            SELECT timestamp, cpu, memory
            FROM metric_history
            WHERE timestamp >= ?
            ORDER BY timestamp ASC;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                completion([])
                return
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, sqlite3_int64(date.timeIntervalSince1970))

            var result: [HistoricalSample] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(
                    HistoricalSample(
                        timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0))),
                        cpuPercent: sqlite3_column_double(statement, 1),
                        memoryPercent: sqlite3_column_double(statement, 2)
                    )
                )
            }
            completion(result)
        }
    }

    func deleteOlderThanSevenDays() {
        queue.async { [weak self] in
            guard let database = self?.database else { return }
            let cutoff = Int64(Date().addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "DELETE FROM metric_history WHERE timestamp < ?;",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, cutoff)
            sqlite3_step(statement)
        }
    }

    private func createSchema() {
        let sql = """
        CREATE TABLE IF NOT EXISTS metric_history(
            timestamp INTEGER PRIMARY KEY,
            cpu REAL NOT NULL,
            memory REAL NOT NULL,
            samples INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_metric_history_timestamp
        ON metric_history(timestamp);
        """
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private static func defaultDatabaseURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        return support
            .appendingPathComponent("PerformanceMonitor", isDirectory: true)
            .appendingPathComponent("history.sqlite")
    }
}
