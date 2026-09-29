import Foundation
import MCP

public typealias ConnectionLauncher = @Sendable (String, Configuration) throws -> Void

extension AppScope {
  static let terminalConnectionStates = ["completed", "cancelled", "expired"]

  func sessionLock(_ id: String) throws -> RefreshLock {
    try RefreshLock(directory: config.directory, app: "connection-\(id)", country: "local")
  }
  func loadConnection(_ id: String) async throws -> JSON {
    let id = try Validate.identifier(id)
    guard let session = try await database.get("connection_session", id) else {
      throw ScopeError(
        "session_not_found", "This setup session is unavailable. Start a new connection.")
    }
    return session
  }
  @discardableResult
  func updateConnection(_ session: JSON, _ fields: [String: JSON]) async throws -> JSON {
    let revision = session["revision"].intValue ?? 1
    let updated = session.setting(fields).setting([
      "revision": .int(revision + 1), "updated_at": .string(timestamp()),
    ])
    try await database.replaceRevision(
      "connection_session", session["session_id"].text,
      revision: revision, value: updated)
    return updated
  }
  func publicConnection(_ session: JSON) -> JSON {
    let keys = [
      "session_id", "provider", "app_id", "country", "state", "created_at", "expires_at",
      "updated_at", "verification", "result", "error", "resume_tool", "resume_arguments",
    ]
    var result = Dictionary(uniqueKeysWithValues: keys.map { ($0, session[$0]) })
    let state = session["state"].text
    result["next_action"] = [
      "kind": .string(
        state == "awaiting_user"
          ? "finish_private_setup"
          : state == "needs_attention"
            ? "review_error"
            : Self.terminalConnectionStates.contains(state) ? "none" : "check_progress"),
      "tool": Self.terminalConnectionStates.contains(state) ? .null : "connection_status",
      "arguments": ["session_id": session["session_id"]],
    ]
    if state == "needs_attention" {
      let repair =
        session["verification"]["connection_state"].text == "invalid_credentials"
        || ["invalid_private_key", "provider_http_401", "unsafe_permissions", "unsafe_file"]
          .contains(session["error"]["code"].text)
      var arguments: [String: JSON] = [
        "provider": session["provider"], "country": session["country"],
        "interaction": "interactive", "resume_tool": session["resume_tool"],
        "resume_arguments": session["resume_arguments"],
        "reopen_window": true, "retry": true,
      ]
      if session["app_id"].text != "*" { arguments["app_id"] = session["app_id"] }
      result["next_action"] = [
        "kind": .string(repair ? "repair_connection" : "review_error_then_retry"),
        "tool": .string(repair ? "start_connection" : "connection_status"),
        "arguments": repair
          ? .object(arguments) : ["session_id": session["session_id"], "retry": true],
      ]
    }
    result["message"] = .string(
      state == "awaiting_user"
        ? "Finish connecting in AppScope's private window, then the agent can continue."
        : state == "saved"
          ? "Credentials are ready. Check progress to verify access and continue."
          : state == "refreshing"
            ? "Continue checking progress to finish the saved request."
            : state == "completed"
              ? "The request finished. Report the returned coverage and any remaining gaps."
              : state == "cancelled"
                ? "Setup stopped. Any saved credentials and collected data are retained."
                : state == "expired"
                  ? "Setup expired after 24 hours. Start again when ready."
                  : "Review the reported issue; retry after addressing it.")
    return .object(result)
  }

  func startConnection(_ args: JSON) async throws -> JSON {
    let provider = args["provider"].text
    let app = try args["app_id"].stringValue.map(Validate.appID) ?? "*"
    let country = try Validate.country(args["country"].stringValue ?? "us")
    guard args["interaction"].text == "interactive" else {
      return [
        "state": "deferred", "reason": "background",
        "message":
          "Continue with available data. Setup can be offered in a live user conversation.",
      ]
    }
    let preferenceKey = "\(provider)|\(app)"
    let preference = try await connectionPreference(provider: provider, app: app)
    let suppressed =
      preference?["decision"].text == "decline"
      || (preference?["decision"].text == "later"
        && (preference?["until"].text ?? "") > timestamp())
    if suppressed && args["retry"].boolValue != true {
      return [
        "state": "deferred", "reason": "saved_user_choice",
        "message":
          "The user chose to continue without this account. Retry only when they explicitly ask.",
      ]
    }
    var resume =
      args["resume_arguments"].objectValue
      ?? ["app_id": .string(app), "country": .string(country)]
    let tool = args["resume_tool"].stringValue ?? (app == "*" ? "owned_apps" : "daily_report")
    if tool == "owned_apps" && args["resume_arguments"] == .null { resume = [:] }
    guard Onboarding.continuationTools.contains(tool),
      app != "*" || ["owned_apps", "search_term_popularity"].contains(tool),
      resume["app_id"] == nil || resume["app_id"]?.text == app,
      resume["country"] == nil || resume["country"]?.text.lowercased() == country,
      Onboarding.provider(for: tool) == nil || Onboarding.provider(for: tool) == provider
    else {
      throw ScopeError(
        "invalid_continuation", "Continue the same app, country and relevant provider.")
    }
    try ToolCatalog.validate(tool, resume)
    // A completed old refresh may contain credential-related skips. Always reserve a fresh run.
    var frozenKeywords: [JSON] = []
    if ["refresh_app", "daily_report", "aso_strategy"].contains(tool) {
      frozenKeywords = try await database.list("tracked").filter {
        $0["app_id"].text == app && $0["country"].text == country
      }.map { $0["keyword"] }.sorted { $0.text < $1.text }
    }
    if tool == "refresh_app", let oldID = resume["run_id"]?.text {
      let old = try await loadRefresh(app: app, country: country, id: oldID)
      for flag in ["include_popularity", "include_performance"] {
        if let selected = resume[flag], selected != old?[flag] {
          throw ScopeError("run_options_changed", "Continue with the original refresh options.")
        }
        resume[flag] = old?[flag]
      }
      frozenKeywords = old?["keywords"].list ?? []
    }
    if tool == "refresh_app" {
      guard
        resume[provider == "apple_ads" ? "include_popularity" : "include_performance"]?.boolValue
          != false
      else {
        throw ScopeError("invalid_continuation", "This request excludes the selected provider.")
      }
    }
    let startLock = try RefreshLock(
      directory: config.directory, app: "setup-\(provider)-\(app)", country: country)
    defer { startLock.release() }
    let key = evidenceKey(provider, app, country)
    if let latest = try await database.get("connection_latest", key),
      let previous = try await database.get("connection_session", latest["session_id"].text),
      !Self.terminalConnectionStates.contains(previous["state"].text),
      previous["expires_at"].text > timestamp()
    {
      guard previous["resume_tool"].text == tool, previous["resume_arguments"] == .object(resume)
      else {
        throw ScopeError(
          "connection_busy",
          "A setup session already owns another request for this app. Finish or cancel that session first."
        )
      }
      if args["reopen_window"].boolValue == true
        && ["awaiting_user", "needs_attention"].contains(previous["state"].text)
      {
        return try await launchConnectionWindow(previous)
      }
      return publicConnection(previous)
    }
    let evidence = try await connectionEvidence(provider: provider, app: app, country: country)
    let ready =
      config.credentialStatus(provider) != "not_configured"
      && evidence?["connection_state"].text != "invalid_credentials"
    let id = UUID().uuidString.lowercased()
    let session: JSON = [
      "session_id": .string(id), "revision": 1, "provider": .string(provider),
      "app_id": .string(app), "country": .string(country),
      "state": .string(ready ? "saved" : "awaiting_user"),
      "created_at": .string(timestamp()),
      "expires_at": .string(timestamp(Date().addingTimeInterval(86400))),
      "initial_fingerprint": .string(config.credentialFingerprint(provider)),
      "resume_tool": .string(tool), "resume_arguments": .object(resume),
      "continuation_run_id": .string(UUID().uuidString.lowercased()),
      "continuation_keywords": .array(frozenKeywords),
    ]
    try await database.put("connection_session", id, session)
    try await database.put("connection_latest", key, ["session_id": .string(id)])
    if args["retry"].boolValue == true {
      try await database.remove("connection_preference", preferenceKey)
    }
    return ready ? publicConnection(session) : try await launchConnectionWindow(session)
  }

  func launchConnectionWindow(_ session: JSON) async throws -> JSON {
    do {
      guard let connectionLauncher else {
        throw ScopeError(
          "setup_window_unavailable", "The private setup window could not be opened on this host.")
      }
      try connectionLauncher(session["session_id"].text, config)
      return publicConnection(session)
    } catch {
      // Remain resumable: the user can open the same session locally, or use configure.
      return publicConnection(session).setting([
        "window": "unavailable",
        "fallback": [
          "command": .string("appscope connection-window \(session["session_id"].text)"),
          "message":
            "Open this command on the Mac running AppScope. You can also use appscope configure for this provider. Never paste credentials into chat.",
        ],
      ])
    }
  }

  func advanceConnection(_ args: JSON, progress: RefreshProgress?) async throws -> JSON {
    let id = try Validate.identifier(args["session_id"].text)
    var session = try await loadConnection(id)
    // Do not hold the session lock while the user is entering credentials.
    let deadline = Date().addingTimeInterval(Double(args["wait_seconds"].intValue ?? 0))
    while session["state"].text == "awaiting_user", Date() < deadline,
      session["expires_at"].text > timestamp(),
      try await database.get("connection_cancel", id) == nil
    {
      try await Task.sleep(for: .milliseconds(250))
      try reloadConfiguration()
      if config.credentialStatus(session["provider"].text) != "not_configured",
        config.credentialFingerprint(session["provider"].text)
          != session["initial_fingerprint"].text
      {
        break
      }
      session = try await loadConnection(id)
    }
    let lock: RefreshLock
    do { lock = try sessionLock(id) } catch let error as ScopeError
      where error.code == "refresh_busy"
    {
      let cancelled = try await database.get("connection_cancel", id) != nil
      return publicConnection(session).setting([
        "busy": true, "cancellation_requested": .bool(cancelled),
      ])
    }
    defer { lock.release() }
    session = try await loadConnection(id)
    if let stopped = try await stoppedConnection(session) { return publicConnection(stopped) }
    if session["state"].text == "needs_attention" {
      guard args["retry"].boolValue == true else { return publicConnection(session) }
      session = try await updateConnection(session, ["state": "saved", "error": .null])
    }
    if session["state"].text == "awaiting_user" {
      let provider = session["provider"].text
      guard config.credentialStatus(provider) != "not_configured",
        config.credentialFingerprint(provider) != session["initial_fingerprint"].text
      else { return publicConnection(session) }
      // Also recovers a helper that exited after the atomic config write, before its checkpoint.
      session = try await updateConnection(session, ["state": "saved"])
    }
    do {
      if session["app_id"].text == "*" && session["provider"].text == "apple_ads" {
        // This demand query has no app scope; the original read is its verification.
        let result = try await continueConnection(session, maxSteps: 1, progress: progress)
        if let stopped = try await stoppedConnection(session) { return publicConnection(stopped) }
        session = try await updateConnection(
          session,
          [
            "state": "completed", "result": result,
            "verification": [
              "status": "ok", "connection_state": "verified",
              "scope": "requested_search_term_popularity_query",
            ],
          ])
        return publicConnection(session)
      }
      if ["saved", "verifying"].contains(session["state"].text) {
        session = try await updateConnection(session, ["state": "verifying"])
        let fingerprint = config.credentialFingerprint(session["provider"].text)
        let verification = try await verifyConnection(
          provider: session["provider"].text,
          app: session["app_id"].text, country: session["country"].text)
        try reloadConfiguration()
        guard config.credentialFingerprint(session["provider"].text) == fingerprint else {
          throw ScopeError(
            "configuration_changed",
            "Credentials changed during verification. Retry to check the current account.")
        }
        if let stopped = try await stoppedConnection(session) { return publicConnection(stopped) }
        guard verification["status"].text == "ok" else {
          session = try await updateConnection(
            session,
            [
              "state": "needs_attention", "verification": verification,
              "error": [
                "code": verification["code"],
                "message":
                  "Apple access is not verified. Review the connection result, then retry or reopen setup.",
              ],
            ])
          return publicConnection(session)
        }
        session = try await updateConnection(
          session, ["state": "refreshing", "verification": verification])
      }
      if let stopped = try await stoppedConnection(session) { return publicConnection(stopped) }
      let result = try await continueConnection(
        session, maxSteps: args["max_steps"].intValue ?? 5, progress: progress)
      if let stopped = try await stoppedConnection(session) { return publicConnection(stopped) }
      let state = result["run"]["status"].text
      session = try await updateConnection(
        session,
        [
          "state": .string(
            ["paused", "running", "interrupted"].contains(state) ? "refreshing" : "completed"),
          "result": result, "error": .null,
        ])
      return publicConnection(session)
    } catch is CancellationError {
      // Keep the saved checkpoint; a later status call resumes the same run.
      throw CancellationError()
    } catch {
      let safe =
        error as? ScopeError
        ?? ScopeError(
          "continuation_failed",
          "The saved request could not finish. Retry after checking the connection.")
      session = try await updateConnection(
        session, ["state": "needs_attention", "error": safe.json])
      return publicConnection(session)
    }
  }

  func stoppedConnection(_ session: JSON) async throws -> JSON? {
    if Self.terminalConnectionStates.contains(session["state"].text) { return session }
    if try await database.get("connection_cancel", session["session_id"].text) != nil {
      return try await updateConnection(session, ["state": "cancelled"])
    }
    if session["expires_at"].text <= timestamp() {
      return try await updateConnection(session, ["state": "expired"])
    }
    return nil
  }
  func continueConnection(_ session: JSON, maxSteps: Int, progress: RefreshProgress?) async throws
    -> JSON
  {
    let tool = session["resume_tool"].text
    var args = session["resume_arguments"].objectValue ?? [:]
    let app = session["app_id"].text
    let country = session["country"].text
    if ["daily_report", "aso_strategy", "refresh_app"].contains(tool) {
      args.removeValue(forKey: "run_id")
      args["new_run"] = true
      args["max_steps"] = .int(min(maxSteps, args["max_steps"]?.intValue ?? maxSteps))
      if tool != "refresh_app" {
        args["include_popularity"] = .bool(session["provider"].text == "apple_ads")
        args["include_performance"] = .bool(session["provider"].text == "app_store_connect")
      }
      let result = try await refreshApp(
        app: app, country: country, args: .object(args), progress: progress,
        preparedRunID: session["continuation_run_id"].text,
        preparedKeywords: session["continuation_keywords"].list.map(\.text))
      return result.setting([
        "onboarding": try await onboarding(
          name: tool,
          args: ["app_id": .string(app), "country": .string(country), "interaction": "interactive"])
      ])
    }
    return try await call(tool, args, progress: progress)
  }

  func recordConnectionDecision(_ args: JSON) async throws -> JSON {
    let app = try args["app_id"].stringValue.map(Validate.appID) ?? "*"
    let provider = args["provider"].text
    let result: JSON = [
      "provider": .string(provider), "app_id": .string(app),
      "decision": args["decision"], "recorded_at": .string(timestamp()),
      "until": args["decision"].text == "later"
        ? .string(timestamp(Date().addingTimeInterval(7 * 86400))) : .null,
    ]
    try await database.put("connection_preference", "\(provider)|\(app)", result)
    for session in try await database.list("connection_session")
    where (app == "*" || session["app_id"].text == app) && session["provider"].text == provider
      && !Self.terminalConnectionStates.contains(session["state"].text)
    { _ = try await cancelConnection(session["session_id"].text) }
    return result
  }
  func cancelConnection(_ id: String) async throws -> JSON {
    let session = try await loadConnection(id)
    if Self.terminalConnectionStates.contains(session["state"].text) {
      return publicConnection(session)
    }
    try await database.put(
      "connection_cancel", session["session_id"].text, ["requested_at": .string(timestamp())])
    return try await advanceConnection(["session_id": session["session_id"]], progress: nil)
  }

  /// Local helper entry points; deliberately absent from MCP's tool catalog.
  public func privateSetupSession(_ id: String) async throws -> JSON {
    let session = try await loadConnection(id)
    guard ["awaiting_user", "needs_attention"].contains(session["state"].text),
      session["expires_at"].text > timestamp(),
      try await database.get("connection_cancel", session["session_id"].text) == nil
    else {
      throw ScopeError("setup_closed", "This setup session is no longer waiting for credentials.")
    }
    return publicConnection(session)
  }
  public func savePrivateConnection(
    sessionID: String, fields: [String: JSON], keyFile: URL, expectedProvider: JSON
  ) async throws {
    let id = try Validate.identifier(sessionID)
    let lock = try sessionLock(id)
    defer { lock.release() }
    _ = try await privateSetupSession(id)
    let session = try await loadConnection(id)
    try CredentialSetup.importAndSave(
      provider: session["provider"].text, fields: fields,
      keyFile: keyFile, expectedProvider: expectedProvider, environment: config.environment)
    try reloadConfiguration()
    try await updateConnection(session, ["state": "saved", "error": .null])
  }

  /// Called only by the running MCP server. It completes already authorized setup requests;
  /// it never starts a window, schedules a report, or retries a needs_attention session.
  public func advanceReadyConnections() async throws {
    try reloadConfiguration()
    let sessions = try await database.list("connection_session")
    for session in sessions
    where ["saved", "verifying", "refreshing"].contains(session["state"].text)
      || (session["state"].text == "awaiting_user"
        && config.credentialStatus(session["provider"].text) != "not_configured"
        && config.credentialFingerprint(session["provider"].text)
          != session["initial_fingerprint"].text)
    {
      try Task.checkCancellation()
      _ = try await advanceConnection(
        ["session_id": session["session_id"], "max_steps": 5], progress: nil)
    }
  }
}
