import CSQLite
import Foundation
import MCP

/// One connection serialized by actor isolation; WAL permits independent CLI/MCP processes.
private final class SQLiteConnection: @unchecked Sendable {
  let pointer: OpaquePointer
  init(_ pointer: OpaquePointer) { self.pointer = pointer }
  deinit { sqlite3_close(pointer) }
}

public actor Database {
  private let connection: SQLiteConnection
  private var handle: OpaquePointer { connection.pointer }
  public init(directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let path = directory.appendingPathComponent("appscope.sqlite3").path
    var db: OpaquePointer?
    guard
      sqlite3_open_v2(
        path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK, let db
    else { throw ScopeError("database_error", "Unable to open AppScope's local database.") }
    connection = SQLiteConnection(db)
    sqlite3_busy_timeout(db, 5000)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    guard
      sqlite3_exec(
        db,
        "PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS records (kind TEXT NOT NULL, key TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(kind,key)); CREATE TABLE IF NOT EXISTS snapshots (id INTEGER PRIMARY KEY, app TEXT NOT NULL, country TEXT NOT NULL, keyword TEXT NOT NULL, observed TEXT NOT NULL, body TEXT NOT NULL); CREATE INDEX IF NOT EXISTS rank_history ON snapshots(app,country,keyword,observed);",
        nil, nil, nil) == SQLITE_OK
    else { throw ScopeError("database_error", "Unable to initialize the database.") }
  }
  private func run(_ sql: String, _ args: [String] = []) throws -> [[String]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ScopeError("database_error", "Unable to prepare database operation.")
    }
    defer { sqlite3_finalize(statement) }
    for (index, arg) in args.enumerated() {
      let status = arg.withCString {
        sqlite3_bind_text(
          statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      }
      guard status == SQLITE_OK else {
        throw ScopeError("database_error", "Unable to bind database value.")
      }
    }
    var rows: [[String]] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return rows }
      guard status == SQLITE_ROW else {
        throw ScopeError(
          "database_error",
          "Database operation failed. Retry after other AppScope processes finish.")
      }
      rows.append(
        (0..<sqlite3_column_count(statement)).map {
          sqlite3_column_text(statement, $0).map { String(cString: $0) } ?? ""
        })
    }
  }
  public func get(_ kind: String, _ key: String) throws -> JSON? {
    guard let row = try run("SELECT body FROM records WHERE kind=? AND key=?", [kind, key]).first
    else { return nil }
    return try JSON.decode(Data(row[0].utf8))
  }
  public func put(_ kind: String, _ key: String, _ value: JSON) throws {
    _ = try run(
      "INSERT INTO records(kind,key,body) VALUES(?,?,?) ON CONFLICT(kind,key) DO UPDATE SET body=excluded.body",
      [kind, key, value.jsonText()])
  }
  public func list(_ kind: String) throws -> [JSON] {
    try run("SELECT body FROM records WHERE kind=? ORDER BY key", [kind]).map {
      try JSON.decode(Data($0[0].utf8))
    }
  }
  public func remove(_ kind: String, _ key: String) throws {
    _ = try run("DELETE FROM records WHERE kind=? AND key=?", [kind, key])
  }
  /// Cancellation must not race another process into overwriting an explicit decline.
  func snoozeConnectionInvitations(provider: String, app: String, at: String, until: String) throws
  {
    _ = try run("BEGIN IMMEDIATE")
    do {
      let keys = Set(["\(provider)|\(app)", "\(provider)|*"])
      let existing = try keys.compactMap { try get("connection_preference", $0) }
      if !existing.contains(where: {
        $0["decision"].text == "decline"
          || ($0["decision"].text == "later" && $0["until"].text > at)
      }) {
        try put(
          "connection_preference", "\(provider)|\(app)",
          [
            "provider": .string(provider), "app_id": .string(app),
            "decision": "later", "reason": "cancelled_setup",
            "recorded_at": .string(at), "until": .string(until),
          ])
      }
      _ = try run("COMMIT")
    } catch {
      _ = try? run("ROLLBACK")
      throw error
    }
  }
  public func updateTracking(app: String, country: String, terms: [String], remove: Bool) throws {
    _ = try run("BEGIN IMMEDIATE")
    do {
      let existing = try list("tracked").filter {
        $0["app_id"].text == app && $0["country"].text == country
      }
      guard remove || Set(existing.map { $0["keyword"].text } + terms).count <= 100 else {
        throw ScopeError("tracking_limit", "Track up to 100 keywords per app and country.")
      }
      for term in Set(terms) {
        let key = "\(app)|\(country)|\(term)"
        if remove {
          try self.remove("tracked", key)
        } else {
          try put(
            "tracked", key,
            ["app_id": .string(app), "country": .string(country), "keyword": .string(term)])
        }
      }
      _ = try run("COMMIT")
    } catch {
      _ = try? run("ROLLBACK")
      throw error
    }
  }
  public func saveSnapshot(_ value: JSON) throws {
    _ = try run(
      "INSERT INTO snapshots(app,country,keyword,observed,body) VALUES(?,?,?,?,?)",
      [
        value["app_id"].text, value["country"].text, value["keyword"].text,
        value["observed_at"].text, value.jsonText(),
      ])
  }
  /// One latest observation per UTC date, with source and depth fixed before grouping.
  public func dailySnapshots(
    app: String, country: String, keyword: String, start: String, end: String
  ) throws -> [JSON] {
    try run(
      """
      SELECT body FROM (
        SELECT body, observed, ROW_NUMBER() OVER (
          PARTITION BY substr(observed,1,10) ORDER BY observed DESC,id DESC
        ) AS day_row FROM snapshots
        WHERE app=? AND country=? AND keyword=? AND observed>=? AND observed<?
          AND json_extract(body,'$.source')='itunes_search'
          AND json_extract(body,'$.requested_limit')=200
      ) WHERE day_row=1 ORDER BY observed
      """, [app, country, keyword, start + "T00:00:00Z", dateOffset(end, days: 1) + "T00:00:00Z"]
    ).map { try JSON.decode(Data($0[0].utf8)) }
  }
  public func putIfAbsent(_ kind: String, _ key: String, _ value: JSON) throws -> JSON {
    _ = try run(
      "INSERT INTO records(kind,key,body) VALUES(?,?,?) ON CONFLICT(kind,key) DO NOTHING",
      [kind, key, value.jsonText()])
    return try get(kind, key)!
  }
  public func replaceRevision(_ kind: String, _ key: String, revision: Int, value: JSON) throws {
    _ = try run(
      "UPDATE records SET body=? WHERE kind=? AND key=? AND json_extract(body,'$.revision')=CAST(? AS INTEGER)",
      [value.jsonText(), kind, key, String(revision)])
    guard sqlite3_changes(handle) == 1 else {
      throw ScopeError("revision_conflict", "This record changed. Read it again before updating.")
    }
  }
  public func history(app: String, country: String, keyword: String, limit: Int = 30) throws
    -> [JSON]
  {
    try run(
      "SELECT body FROM snapshots WHERE app=? AND country=? AND keyword=? ORDER BY observed DESC,id DESC LIMIT ?",
      [app, country, keyword, String(limit)]
    ).map { try JSON.decode(Data($0[0].utf8)) }
  }
  /// All segments of an instance must be parsed before this atomic replacement.
  public func saveAnalytics(
    app: String, report: String, processingDate: String, instanceID: String, rows: [JSON]
  ) throws {
    let grouped = Dictionary(grouping: rows, by: { $0["Date"].text })
    _ = try run("BEGIN IMMEDIATE")
    do {
      for (date, values) in grouped {
        let key = "\(app)|\(report)|\(date)"
        let existing = try get("analytics", key)
        if let existing, existing["processing_date"].text > processingDate { continue }
        try put(
          "analytics", key,
          [
            "app_id": .string(app), "report": .string(report), "date": .string(date),
            "processing_date": .string(processingDate), "instance_id": .string(instanceID),
            "rows": .array(values), "source": "app_store_connect",
          ])
      }
      _ = try run("COMMIT")
    } catch {
      _ = try? run("ROLLBACK")
      throw error
    }
  }
}
