import Darwin
import Foundation
import MCP

public typealias RefreshProgress = @Sendable (Int, Int, String) async -> Void

/// A nonblocking OS lock survives actor reentrancy and is released if a process dies.
final class RefreshLock: @unchecked Sendable {
  private var descriptor: Int32
  init(directory: URL, app: String, country: String) throws {
    let file = directory.appendingPathComponent("refresh-\(app)-\(country).lock")
    descriptor = open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw ScopeError("lock_unavailable", "Cannot open the private refresh lock.")
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      descriptor = -1
      throw ScopeError(
        "refresh_busy",
        "Another refresh for this app/country is active. Read refresh_status and try later.")
    }
  }
  func release() {
    if descriptor >= 0 {
      close(descriptor)
      descriptor = -1
    }
  }
  deinit { release() }
}

extension AppScope {
  func loadRefresh(app: String, country: String, id: String?) async throws -> JSON? {
    let key: String
    if let id {
      key = try Validate.identifier(id)
    } else {
      guard let latest = try await database.get("refresh_latest", "\(app)|\(country)") else {
        return nil
      }
      key = latest["run_id"].text
    }
    guard let run = try await database.get("refresh_run", key), run["app_id"].text == app,
      run["country"].text == country
    else {
      throw ScopeError("run_not_found", "No matching refresh run for this app and country.")
    }
    return run
  }
  func refreshStatus(app: String, country: String, id: String?) async throws -> JSON {
    guard let run = try await loadRefresh(app: app, country: country, id: id) else { return .null }
    return summarizeRefresh(run)
  }
  func summarizeRefresh(_ run: JSON) -> JSON {
    let steps = run["steps"].list
    let complete = steps.filter { ["succeeded", "skipped"].contains($0["status"].text) }.count
    return run.setting([
      "steps": .array(steps.map { $0.setting(["seeds": .null]) }),
      "completed_steps": .int(complete), "total_steps": .int(steps.count),
      "failed_steps": .array(steps.filter { $0["status"].text == "failed" }),
      "remaining_steps": .int(steps.count - complete),
      "can_resume": .bool(run["day"].text == day() && run["status"].text != "completed"),
      "process_note":
        "Saved status is a checkpoint, not proof a process is still alive. Resume recovers interrupted steps.",
    ])
  }
  func refreshApp(
    app: String, country: String, args: JSON, progress: RefreshProgress?,
    preparedRunID: String? = nil, preparedKeywords: [String]? = nil
  ) async throws
    -> JSON
  {
    if args["run_id"] != .null && args["new_run"].boolValue == true {
      throw ScopeError("invalid_arguments", "Choose run_id or new_run, not both.")
    }
    let lock = try RefreshLock(directory: config.directory, app: app, country: country)
    defer { lock.release() }
    let latest: JSON?
    if let preparedRunID {
      latest = try await database.get("refresh_run", preparedRunID)
    } else {
      latest = try await loadRefresh(app: app, country: country, id: args["run_id"].stringValue)
    }
    let explicit = args["run_id"] != .null || (preparedRunID != nil && latest != nil)
    let resume =
      explicit
      || (args["new_run"].boolValue != true && latest?["day"].text == day()
        && latest?["status"].text != "completed")
    var run: JSON
    if resume, let latest {
      guard latest["day"].text == day() else {
        throw ScopeError(
          "run_expired", "This run is from an earlier UTC date. Start a new run for current data.")
      }
      for flag in ["include_popularity", "include_performance"] where args[flag] != .null {
        guard args[flag] == latest[flag] else {
          throw ScopeError(
            "run_options_changed", "Resume with the original options, or start new_run.")
        }
      }
      run = latest
    } else {
      let terms: [String]
      if let preparedKeywords {
        terms = preparedKeywords
      } else {
        terms = try await database.list("tracked").filter {
          $0["app_id"].text == app && $0["country"].text == country
        }.map { $0["keyword"].text }.sorted()
      }
      var steps: [JSON] = [["kind": "profile", "status": "pending"]]
      let includePopularity = args["include_popularity"].boolValue ?? true
      let includePerformance = args["include_performance"].boolValue ?? true
      if includePopularity {
        let chunks =
          terms.isEmpty
          ? [[]]
          : stride(from: 0, to: terms.count, by: 20).map {
            Array(terms[$0..<min($0 + 20, terms.count)])
          }
        for seeds in chunks {
          steps.append(["kind": "popularity", "status": "pending", "seeds": .strings(seeds)])
        }
      }
      steps += terms.map { ["kind": "ranking", "keyword": .string($0), "status": "pending"] }
      if includePerformance { steps.append(["kind": "performance", "status": "pending"]) }
      run = [
        "run_id": .string(preparedRunID ?? UUID().uuidString.lowercased()), "app_id": .string(app),
        "country": .string(country), "day": .string(day()), "started_at": .string(timestamp()),
        "status": "running", "keywords": .strings(terms), "steps": .array(steps),
        "include_popularity": .bool(includePopularity),
        "include_performance": .bool(includePerformance),
      ]
      try await database.put("refresh_run", run["run_id"].text, run)
      try await database.put("refresh_latest", "\(app)|\(country)", ["run_id": run["run_id"]])
    }
    try await database.put("refresh_latest", "\(app)|\(country)", ["run_id": run["run_id"]])
    if run["status"].text == "completed" {
      return ["run": summarizeRefresh(run), "report": try await report(app: app, country: country)]
    }
    var steps = run["steps"].list
    var completed = steps.filter { ["succeeded", "skipped"].contains($0["status"].text) }.count
    let maximum = args["max_steps"].intValue ?? 120
    var attempted = 0
    for index in steps.indices
    where !["succeeded", "skipped"].contains(steps[index]["status"].text) {
      if attempted >= maximum { break }
      guard run["day"].text == day() else { break }
      do {
        try Task.checkCancellation()
        steps[index] = steps[index].setting([
          "status": "running", "error": .null,
          "attempts": .int((steps[index]["attempts"].intValue ?? 0) + 1),
          "started_at": .string(timestamp()),
        ])
        run = run.setting([
          "status": "running", "steps": .array(steps), "updated_at": .string(timestamp()),
        ])
        try await database.put("refresh_run", run["run_id"].text, run)
        let kind = steps[index]["kind"].text
        let provider = kind == "popularity" ? "apple_ads" : "app_store_connect"
        if ["popularity", "performance"].contains(kind)
          && config.credentialStatus(provider) == "not_configured"
        {
          steps[index] = steps[index].setting([
            "status": "skipped", "reason": "provider_not_configured",
          ])
        } else {
          switch kind {
          case "profile":
            _ = try await call(
              "app_profile", ["app_id": .string(app), "country": .string(country)])
          case "popularity":
            _ = try await call(
              "keyword_suggestions",
              ["app_id": .string(app), "country": .string(country), "seeds": steps[index]["seeds"]])
          case "ranking":
            _ = try await analyze(
              app: app, country: country, keyword: steps[index]["keyword"].text, limit: 200)
          case "performance":
            let result = try await call(
              "app_performance", ["app_id": .string(app), "country": .string(country)])
            if result["sync"]["status"].text == "error" {
              throw ScopeError(result["sync"]["code"].text, result["sync"]["message"].text)
            }
            steps[index] = steps[index].setting(["data_status": result["sync"]["status"]])
          default: throw ScopeError("invalid_run", "Unknown refresh step. Start a new run.")
          }
          steps[index] = steps[index].setting(["status": "succeeded"])
        }
      } catch is CancellationError {
        steps[index] = steps[index].setting(["status": "pending"])
        run = run.setting([
          "status": "interrupted", "steps": .array(steps), "updated_at": .string(timestamp()),
        ])
        try await database.put("refresh_run", run["run_id"].text, run)
        throw CancellationError()
      } catch {
        let safe =
          (error as? ScopeError)
          ?? ScopeError("refresh_failed", "Refresh step failed. Check local setup and retry.")
        steps[index] = steps[index].setting(["status": "failed", "error": safe.json])
      }
      steps[index] = steps[index].setting(["finished_at": .string(timestamp())])
      run = run.setting(["steps": .array(steps), "updated_at": .string(timestamp())])
      try await database.put("refresh_run", run["run_id"].text, run)
      completed += 1
      attempted += 1
      if !Task.isCancelled {
        await progress?(
          completed, steps.count, "Completed \(completed) of \(steps.count) refresh steps")
      }
    }
    let pending = steps.contains { ["pending", "running"].contains($0["status"].text) }
    let failed = steps.contains { $0["status"].text == "failed" }
    let status =
      run["day"].text != day() ? "expired" : pending ? "paused" : failed ? "partial" : "completed"
    run = run.setting(["status": .string(status), "updated_at": .string(timestamp())])
    try await database.put("refresh_run", run["run_id"].text, run)
    return ["run": summarizeRefresh(run), "report": try await report(app: app, country: country)]
  }
}
