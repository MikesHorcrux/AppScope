import CryptoKit
import Foundation
import MCP
import Testing

@testable import AppScopeCore

private func item(_ result: JSON, _ provider: String) -> JSON {
  result["onboarding"]["providers"].list.first { $0["provider"].text == provider } ?? .null
}
private func startArgs(_ provider: String = "apple_ads") -> [String: JSON] {
  ["provider": .string(provider), "app_id": "12", "country": "us", "interaction": "interactive"]
}

@Test func invitationsRespectIntentPersistedDecisionsAndBackgroundWork() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(
    config: Configuration(directory: dir),
    connectionLauncher: { _, _ in
      Issue.record("This test should never open a setup window")
    })
  let report = try await scope.call("daily_report", ["app_id": "12", "interaction": "interactive"])
  #expect(item(report, "apple_ads")["should_invite"].boolValue == true)
  #expect(
    item(report, "apple_ads")["next_action"]["arguments"]["resume_tool"].text == "daily_report")
  #expect(report["health"] != .null)
  _ = try await scope.call(
    "connection_decision", ["provider": "apple_ads", "app_id": "12", "decision": "decline"])
  let restarted = try AppScope(config: Configuration(directory: dir))
  let next = try await restarted.call(
    "daily_report", ["app_id": "12", "interaction": "interactive"])
  #expect(item(next, "apple_ads")["should_invite"].boolValue == false)
  #expect(item(next, "apple_ads")["prompt_suppression"].text == "declined")
  #expect(item(next, "app_store_connect")["should_invite"].boolValue == true)
  #expect(try await restarted.call("start_connection", startArgs())["state"].text == "deferred")
  var background = startArgs("app_store_connect")
  background["interaction"] = "background"
  #expect(try await scope.call("start_connection", background)["reason"].text == "background")
  #expect(try await scope.database.list("connection_session").isEmpty)
  let scheduled = try await scope.call("daily_report", ["app_id": "12"])
  #expect(
    scheduled["onboarding"]["providers"].list.allSatisfy { $0["should_invite"].boolValue == false })
  var retry = startArgs()
  retry["retry"] = true
  let connection = try await restarted.call("start_connection", retry)
  #expect(connection["state"].text == "awaiting_user")
  #expect(connection["window"].text == "unavailable")
  #expect(
    try await restarted.call("start_connection", retry)["session_id"] == connection["session_id"])
  #expect(try await restarted.database.list("connection_session").count == 1)
}

@Test func onboardingHonorsFrozenRefreshOptionsAndCachedOnlyRequests() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(
    config: Configuration(directory: dir),
    http: HTTP(transport: MockHTTP([(searchFixture(), 200)]), searchInterval: 0))
  let first = try await scope.call("refresh_app", ["app_id": "12", "include_performance": false])
  let resumed = try await scope.call(
    "refresh_app", ["app_id": "12", "run_id": first["run"]["run_id"], "interaction": "interactive"])
  #expect(resumed["onboarding"]["providers"].list.count == 1)
  #expect(item(resumed, "apple_ads")["should_invite"].boolValue == true)
  #expect(item(resumed, "app_store_connect") == .null)
  let cached = try await scope.call(
    "app_performance", ["app_id": "12", "sync": false, "interaction": "interactive"])
  #expect(cached["onboarding"]["providers"].list.isEmpty)
}

@Test func privateImportReloadsRunningServiceAndContinuesFreshRunAcrossRestart() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let env = [
    "APPSCOPE_DATA_DIR": dir.path,
    "APPSCOPE_CONFIG": dir.appendingPathComponent("custom.json").path,
  ]
  let transport = MockHTTP([
    (searchFixture(), 200),  // original refresh with missing account
    (["access_token": "fixture-private-token", "expires_in": 3600], 200),
    (["result": []], 200),  // scoped verification
    (searchFixture(), 200),  // fresh run, first bounded step
  ])
  let scope = try AppScope(
    config: Configuration.load(environment: env),
    http: HTTP(transport: transport, searchInterval: 0))
  let old = try await scope.call("refresh_app", ["app_id": "12"])
  #expect(old["run"]["status"].text == "completed")
  #expect(old["run"]["steps"].list.filter { $0["status"].text == "skipped" }.count == 2)
  let start = try await scope.call("start_connection", startArgs())
  let creds = try testCredentials(dir)
  let source = URL(fileURLWithPath: creds.values["apple_ads"]["private_key_path"].text)
  try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path)
  var fields = creds.values["apple_ads"].objectValue!
  fields.removeValue(forKey: "private_key_path")
  let helper = try AppScope(config: Configuration.load(environment: env))
  try await helper.savePrivateConnection(
    sessionID: start["session_id"].text, fields: fields,
    keyFile: source, expectedProvider: .null)
  let saved = try Configuration.load(environment: env)
  #expect(saved.credentialStatus("apple_ads") == "configured_unverified")
  #expect(saved.values["apple_ads"]["private_key_path"].text != source.path)
  try Configuration.checkPrivateFile(
    URL(fileURLWithPath: saved.values["apple_ads"]["private_key_path"].text))
  #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path))
  let partial = try await scope.call(
    "connection_status", ["session_id": start["session_id"], "max_steps": 1])
  #expect(partial["state"].text == "refreshing")
  #expect(partial["result"]["run"]["run_id"] != old["run"]["run_id"])
  #expect(partial["result"]["run"]["include_performance"].boolValue == false)
  let transport2 = MockHTTP([
    (["access_token": "fixture-private-token-2", "expires_in": 3600], 200),
    (["result": [["text": "budget", "popularity": 40]]], 200),
  ])
  let restarted = try AppScope(
    config: Configuration.load(environment: env),
    http: HTTP(transport: transport2, searchInterval: 0))
  let done = try await restarted.call("connection_status", ["session_id": start["session_id"]])
  #expect(done["state"].text == "completed")
  #expect(done["result"]["run"]["run_id"] == partial["result"]["run"]["run_id"])
  #expect(done["result"]["run"]["steps"].list.allSatisfy { $0["status"].text == "succeeded" })
  #expect(
    try await restarted.call("connection_status", ["session_id": start["session_id"]]) == done)
  #expect(await transport2.requests.count == 2)
  #expect(
    try await restarted.database.get("popularity", "12|us|budget")?["popularity"].intValue == 40)
  let text = try done.jsonText()
  for forbidden in [
    "fixture-private-token", "BEGIN PRIVATE KEY", "test-client", source.path, "fingerprint",
  ] {
    #expect(!text.contains(forbidden))
  }
}

@Test func accountChecksPreservePartialAccessAndDoNotPromiseReportCoverage() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([
    (["data": ["id": "12"]], 200), (["detail": "secret"], 403),
    (["data": ["id": "12"]], 200), (["data": []], 200),
  ])
  let scope = try AppScope(
    config: testCredentials(dir), http: HTTP(transport: transport, searchInterval: 0))
  let args: [String: JSON] = [
    "provider": "app_store_connect", "app_id": "12", "interaction": "interactive",
  ]
  let partial = try await scope.call("check_connections", args)
  #expect(partial["checks"]["app_store_connect"]["capabilities"]["app_access"].boolValue == true)
  #expect(item(partial, "app_store_connect")["connection_state"].text == "partial_access")
  #expect(item(partial, "app_store_connect")["next_action"]["kind"].text == "review_account_access")
  #expect(!String(decoding: try partial.encoded(), as: UTF8.self).contains("secret"))
  let disabled = try await scope.call("check_connections", args)
  #expect(item(disabled, "app_store_connect")["connection_state"].text == "reports_not_enabled")
  #expect(item(disabled, "app_store_connect")["missing_capabilities"] == ["analytics_reports"])
  #expect(item(disabled, "app_store_connect")["should_invite"].boolValue == false)
  #expect(await transport.requests.allSatisfy { $0.httpMethod == "GET" })
  #expect(try await scope.database.list("analytics").isEmpty)
}

@Test func invalidCredentialsDecorateErrorsAndSuccessfulChecksAreScopedAndExpire() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([
    (["access_token": "hidden", "expires_in": 3600], 200), (["result": []], 200),
  ])
  let scope = try AppScope(
    config: testCredentials(dir), http: HTTP(transport: transport, searchInterval: 0))
  _ = try await scope.call("check_connections", ["provider": "apple_ads", "app_id": "12"])
  #expect(
    item(try await scope.call("setup_status", ["app_id": "12"]), "apple_ads")["connection_state"]
      .text == "verified")
  #expect(
    item(try await scope.call("setup_status", ["app_id": "13"]), "apple_ads")["connection_state"]
      .text == "configured_unverified")
  let evidence = try await scope.database.get("connection_evidence", "apple_ads|12|us")!
  try await scope.database.put(
    "connection_evidence", "apple_ads|12|us",
    evidence.setting([
      "checked_at": .string(timestamp(Date().addingTimeInterval(-90000)))
    ]))
  #expect(
    item(try await scope.call("setup_status", ["app_id": "12"]), "apple_ads")["connection_state"]
      .text == "configured_unverified")
  let missing = try AppScope(config: Configuration(directory: dir))
  do {
    _ = try await missing.call(
      "keyword_suggestions", ["app_id": "12", "interaction": "interactive"])
    Issue.record("Expected missing credentials")
  } catch let error as ScopeError {
    #expect(error.code == "credentials_missing")
    #expect(item(error.json, "apple_ads")["should_invite"].boolValue == true)
    #expect(!error.message.contains("with appscope setup"))
  }
}

@Test func nativeImportRejectsSymlinksBadKeysAndStaleAccountEdits() throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let env = ["APPSCOPE_DATA_DIR": dir.path]
  let config = try testCredentials(dir)
  try PrivateFile.write(
    try config.values.encoded(), to: dir.appendingPathComponent("config.json"), replace: false)
  let source = URL(fileURLWithPath: config.values["app_store_connect"]["private_key_path"].text)
  let link = dir.appendingPathComponent("link.p8")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
  #expect(throws: ScopeError.self) { try CredentialSetup.validateKeyFile(link) }
  var fields = config.values["app_store_connect"].objectValue!
  fields.removeValue(forKey: "private_key_path")
  let before = try Data(contentsOf: dir.appendingPathComponent("config.json"))
  #expect(throws: ScopeError.self) {
    try CredentialSetup.importAndSave(
      provider: "app_store_connect", fields: fields, keyFile: source,
      expectedProvider: .null, environment: env)
  }
  #expect(try Data(contentsOf: dir.appendingPathComponent("config.json")) == before)
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("keys").path)
      .isEmpty)
  try CredentialSetup.importAndSave(
    provider: "app_store_connect", fields: fields, keyFile: source,
    expectedProvider: config.values["app_store_connect"], environment: env)
  #expect(
    try Configuration.load(environment: env).values["apple_ads"] == config.values["apple_ads"])
  let bad = dir.appendingPathComponent("bad.p8")
  try Data("not a key".utf8).write(to: bad)
  #expect(throws: ScopeError.self) { try CredentialSetup.validateKeyFile(bad) }
  #expect(
    CredentialSetup.suggestedKeyID(for: URL(fileURLWithPath: "AuthKey_AB12CD34EF.p8"))
      == "AB12CD34EF")
  #expect(
    CredentialSetup.identifiers(
      from: "Issuer ID: fixture-issuer\nKey ID: AB12CD34EF", provider: "app_store_connect") == [
        "issuer_id": "fixture-issuer", "key_id": "AB12CD34EF",
      ])
  #expect(
    CredentialSetup.identifiers(
      from: "Key ID: secret\n-----BEGIN PRIVATE KEY-----", provider: "app_store_connect"
    ).isEmpty)
}

@Test func cancellationExpiryAndSchemaFailuresNeverImportOrContinue() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([])
  let scope = try AppScope(config: Configuration(directory: dir), http: HTTP(transport: transport))
  let start = try await scope.call("start_connection", startArgs())
  let cancelled = try await scope.call("cancel_connection", ["session_id": start["session_id"]])
  #expect(cancelled["state"].text == "cancelled")
  await #expect(throws: ScopeError.self) {
    try await scope.privateSetupSession(start["session_id"].text)
  }
  let next = try await scope.call("start_connection", startArgs())
  let row = try await scope.database.get("connection_session", next["session_id"].text)!
  try await scope.database.put(
    "connection_session", next["session_id"].text,
    row.setting([
      "expires_at": .string(timestamp(Date().addingTimeInterval(-1)))
    ]))
  #expect(
    try await scope.call("connection_status", ["session_id": next["session_id"]])["state"].text
      == "expired")
  #expect(await transport.requests.isEmpty)
  for extra: [String: JSON] in [
    ["private_key": "do not accept"], ["resume_tool": "enable_reports"],
    [
      "resume_tool": "daily_report",
      "resume_arguments": ["app_id": "12", "private_key_path": "secret"],
    ],
  ] {
    #expect(throws: ScopeError.self) {
      try ToolCatalog.validate("start_connection", startArgs().merging(extra) { _, new in new })
    }
  }
}

@Test func credentialRotationInvalidatesEvidenceAndCachedAdsTokenWithoutRestart() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let config = try testCredentials(dir)
  let env = ["APPSCOPE_DATA_DIR": dir.path]
  try PrivateFile.write(
    try config.values.encoded(), to: dir.appendingPathComponent("config.json"), replace: false)
  let transport = MockHTTP([
    (["access_token": "old-token", "expires_in": 3600], 200), (["result": []], 200),
    (["access_token": "new-token", "expires_in": 3600], 200), (["result": []], 200),
  ])
  let scope = try AppScope(
    config: Configuration.load(environment: env),
    http: HTTP(transport: transport, searchInterval: 0))
  _ = try await scope.call("keyword_suggestions", ["app_id": "12"])
  #expect(
    item(try await scope.call("setup_status", ["app_id": "12"]), "apple_ads")["connection_state"]
      .text == "verified")
  let key = URL(fileURLWithPath: config.values["apple_ads"]["private_key_path"].text)
  try PrivateFile.write(
    Data(P256.Signing.PrivateKey().pemRepresentation.utf8), to: key, replace: true)
  #expect(
    item(try await scope.call("setup_status", ["app_id": "12"]), "apple_ads")["connection_state"]
      .text == "configured_unverified")
  _ = try await scope.call("keyword_suggestions", ["app_id": "12"])
  let requests = await transport.requests
  #expect(requests.count == 4)
  #expect(requests[3].value(forHTTPHeaderField: "Authorization") == "Bearer new-token")
}

@Test func serverWorkerCompletesSavedSetupWithoutAnotherUserMessage() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([
    (["data": []], 200),  // bounded account access check
    (["data": [["id": "12", "attributes": ["name": "Example"]]]], 200),
  ])
  let scope = try AppScope(
    config: testCredentials(dir), http: HTTP(transport: transport, searchInterval: 0))
  let start = try await scope.call(
    "start_connection", ["provider": "app_store_connect", "interaction": "interactive"])
  #expect(start["state"].text == "saved")
  try await scope.advanceReadyConnections()
  let row = try await scope.database.get("connection_session", start["session_id"].text)!
  #expect(row["state"].text == "completed")
  #expect(row["result"]["apps"].list.first?["id"].text == "12")
  #expect(row["verification"]["capabilities"]["owned_apps"].boolValue == true)
  try await scope.advanceReadyConnections()
  #expect(await transport.requests.count == 2)
}

@Test func reportsPendingDoNotTriggerCredentialSetup() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([
    (["data": [["id": "request", "attributes": ["accessType": "ONGOING"]]]], 200),
    (["data": []], 200),
  ])
  let scope = try AppScope(
    config: testCredentials(dir), http: HTTP(transport: transport, searchInterval: 0))
  let result = try await scope.call(
    "app_performance", ["app_id": "12", "interaction": "interactive"])
  #expect(result["sync"]["status"].text == "pending")
  #expect(item(result, "app_store_connect")["connection_state"].text == "reports_pending")
  #expect(item(result, "app_store_connect")["should_invite"].boolValue == false)
  #expect(item(result, "app_store_connect")["next_action"]["kind"].text == "wait_for_apple_reports")
}

private actor PausedSetupHTTP: HTTPTransport {
  var started = false
  var count = 0
  var gate: CheckedContinuation<Void, Never>?
  func release() {
    gate?.resume()
    gate = nil
  }
  func send(_ request: URLRequest) async throws -> (Data, Int, [String: String]) {
    count += 1
    if count == 1 {
      await withCheckedContinuation { continuation in
        gate = continuation
        started = true
      }
      return (try JSON.object(["access_token": "private", "expires_in": 3600]).encoded(), 200, [:])
    }
    return (try JSON.object(["result": []]).encoded(), 200, [:])
  }
}

@Test func concurrentStatusDoesNotDuplicateWorkAndCancellationStopsContinuation() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = PausedSetupHTTP()
  let config = try testCredentials(dir)
  let scope = try AppScope(config: config, http: HTTP(transport: transport, searchInterval: 0))
  let second = try AppScope(config: config, http: HTTP(transport: transport, searchInterval: 0))
  let start = try await scope.call("start_connection", startArgs())
  let task = Task { try await scope.call("connection_status", ["session_id": start["session_id"]]) }
  for _ in 0..<100 {
    if await transport.started { break }
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(await transport.started)
  let busy = try await second.call("connection_status", ["session_id": start["session_id"]])
  #expect(busy["busy"].boolValue == true)
  let cancelled = try await second.call("cancel_connection", ["session_id": start["session_id"]])
  #expect(cancelled["cancellation_requested"].boolValue == true)
  await transport.release()
  #expect(try await task.value["state"].text == "cancelled")
  #expect(await transport.count == 2)
  #expect(try await scope.database.list("refresh_run").isEmpty)
}

@Test func invalidSavedAccountCanBeRepairedAndDeferredChoiceExpires() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let config = try testCredentials(dir)
  let key = URL(fileURLWithPath: config.values["apple_ads"]["private_key_path"].text)
  try Data("broken".utf8).write(to: key)
  let scope = try AppScope(config: config, http: HTTP(transport: MockHTTP([])))
  let start = try await scope.call("start_connection", startArgs())
  let failed = try await scope.call("connection_status", ["session_id": start["session_id"]])
  #expect(failed["state"].text == "needs_attention")
  #expect(failed["next_action"]["kind"].text == "repair_connection")
  let repair = try await scope.call(
    "start_connection", failed["next_action"]["arguments"].objectValue!)
  #expect(repair["session_id"] == start["session_id"])
  #expect(repair["window"].text == "unavailable")
  _ = try await scope.privateSetupSession(start["session_id"].text)
  _ = try await scope.call(
    "connection_decision", ["provider": "apple_ads", "app_id": "12", "decision": "later"])
  let decision = try await scope.database.get("connection_preference", "apple_ads|12")!
  try await scope.database.put(
    "connection_preference", "apple_ads|12", decision.setting(["until": "2000-01-01T00:00:00Z"]))
  let invitation = try await scope.call(
    "daily_report", ["app_id": "12", "interaction": "interactive"])
  #expect(item(invitation, "apple_ads")["should_invite"].boolValue == true)
}
