import Foundation
import MCP
import Testing

@testable import AppScopeCore

private func providerItem(_ result: JSON, _ provider: String) -> JSON {
  result["onboarding"]["providers"].list.first { $0["provider"].text == provider } ?? .null
}

@Test func backgroundSetupGuidanceNeverInvitesOrStartsWork() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([])
  let scope = try AppScope(
    config: Configuration(directory: dir), http: HTTP(transport: transport),
    connectionLauncher: { _, _ in Issue.record("Background work must not launch setup") })
  for mode in [nil, "background"] as [String?] {
    var args: [String: JSON] = ["app_id": "12"]
    if let mode { args["interaction"] = .string(mode) }
    let result = try await scope.call("daily_report", args)
    #expect(result["health"] != .null)
    for provider in ["apple_ads", "app_store_connect"] {
      let item = providerItem(result, provider)
      #expect(item["should_invite"].boolValue == false)
      #expect(item["prompt_suppression"].text == "background")
      #expect(item["next_action"]["kind"].text == "setup_needed")
      #expect(item["next_action"]["requires_user_consent"].boolValue == true)
      #expect(item["next_action"]["requires_interactive_context"].boolValue == true)
      #expect(item["next_action"]["tool"] == .null)
    }
  }
  #expect(await transport.requests.isEmpty)
  #expect(try await scope.database.list("connection_session").isEmpty)
}

@Test func cancellingSetupPersistsASnoozeUntilExpiryOrExplicitRetry() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([])
  let config = Configuration(directory: dir)
  let scope = try AppScope(config: config, http: HTTP(transport: transport))
  let args: [String: JSON] = [
    "provider": "apple_ads", "app_id": "12", "interaction": "interactive",
  ]
  let start = try await scope.call("start_connection", args)
  #expect(
    try await scope.call("cancel_connection", ["session_id": start["session_id"]])["state"].text
      == "cancelled")
  let restarted = try AppScope(config: config, http: HTTP(transport: transport))
  let report = try await restarted.call(
    "daily_report", ["app_id": "12", "country": "gb", "interaction": "interactive"])
  #expect(providerItem(report, "apple_ads")["should_invite"].boolValue == false)
  #expect(providerItem(report, "apple_ads")["prompt_suppression"].text == "cancelled")
  #expect(providerItem(report, "app_store_connect")["should_invite"].boolValue == true)
  #expect(try await restarted.call("start_connection", args)["state"].text == "deferred")
  let decision = try #require(await restarted.database.get("connection_preference", "apple_ads|12"))
  let until = try #require(ISO8601DateFormatter().date(from: decision["until"].text))
  #expect(abs(until.timeIntervalSinceNow - 7 * 86400) < 60)
  let retry = try await restarted.call(
    "start_connection", args.merging(["retry": true]) { _, new in new })
  #expect(retry["state"].text == "awaiting_user")
  #expect(retry["session_id"] != start["session_id"])
  _ = try await restarted.call("cancel_connection", ["session_id": retry["session_id"]])
  try await restarted.database.put(
    "connection_preference", "apple_ads|12", decision.setting(["until": "2000-01-01T00:00:00Z"]))
  #expect(
    providerItem(
      try await restarted.call("daily_report", ["app_id": "12", "interaction": "interactive"]),
      "apple_ads")["should_invite"].boolValue == true)
  #expect(await transport.requests.isEmpty)
  #expect(config.values == [:])
}

@Test func expiredAppSnoozeFallsBackToAccountDeclineAndCancellationPreservesChoices() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(config: Configuration(directory: dir))
  _ = try await scope.call("connection_decision", ["provider": "apple_ads", "decision": "decline"])
  try await scope.database.put(
    "connection_preference", "apple_ads|12", ["decision": "later", "until": "2000-01-01T00:00:00Z"])
  let report = try await scope.call("daily_report", ["app_id": "12", "interaction": "interactive"])
  #expect(providerItem(report, "apple_ads")["prompt_suppression"].text == "declined")
  let start = try await scope.call(
    "start_connection",
    ["provider": "apple_ads", "app_id": "12", "interaction": "interactive", "retry": true])
  #expect(start["state"].text == "awaiting_user")
  let until = timestamp(Date().addingTimeInterval(86400))
  try await scope.database.put(
    "connection_preference", "apple_ads|12", ["decision": "later", "until": .string(until)])
  _ = try await scope.call("cancel_connection", ["session_id": start["session_id"]])
  #expect(
    try await scope.database.get("connection_preference", "apple_ads|12")?["until"].text == until)
  #expect(
    try await scope.database.get("connection_preference", "apple_ads|*")?["decision"].text
      == "decline")
}

@Test func savedRefreshExclusionsAndKeywordsSurviveConnectionAndRestart() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let complete = try testCredentials(dir)
  let environment = ["APPSCOPE_DATA_DIR": dir.path]
  let file = dir.appendingPathComponent("config.json")
  try PrivateFile.write(
    try complete.values.setting(["apple_ads": [:]]).encoded(), to: file, replace: false)
  let transport = ReportConnectionHTTP()
  let scope = try AppScope(
    config: Configuration.load(environment: environment),
    http: HTTP(transport: transport, searchInterval: 0))
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["budget"]])
  let old = try await scope.call(
    "refresh_app", ["app_id": "12", "include_performance": false, "interaction": "interactive"])
  let start = try await scope.call(
    "start_connection", providerItem(old, "apple_ads")["next_action"]["arguments"].objectValue!)
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["saving"]])
  try PrivateFile.write(try complete.values.encoded(), to: file, replace: true)
  let restarted = try AppScope(
    config: Configuration.load(environment: environment),
    http: HTTP(transport: transport, searchInterval: 0))
  _ = try await restarted.call(
    "connection_status", ["session_id": start["session_id"], "max_steps": 1])
  try await restarted.advanceReadyConnections()
  let done = try await restarted.call("connection_status", ["session_id": start["session_id"]])
  #expect(done["state"].text == "completed")
  #expect(done["result"]["run"]["run_id"] != old["run"]["run_id"])
  #expect(done["result"]["run"]["keywords"] == ["budget"])
  #expect(done["result"]["run"]["include_performance"].boolValue == false)
  #expect(done["result"]["run"]["include_popularity"].boolValue == true)
  #expect(providerItem(done["result"], "app_store_connect") == .null)
  #expect(await transport.requests.allSatisfy { $0.url!.host != "api.appstoreconnect.apple.com" })
}

@Test func recordingDeclineWhileCancellingDoesNotDowngradeTheChoice() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let config = Configuration(directory: dir)
  let scope = try AppScope(config: config)
  let start = try await scope.call(
    "start_connection", ["provider": "apple_ads", "app_id": "12", "interaction": "interactive"])
  _ = try await scope.call("connection_decision", ["provider": "apple_ads", "decision": "decline"])
  #expect(
    try await scope.call("connection_status", ["session_id": start["session_id"]])["state"].text
      == "cancelled")
  let restarted = try AppScope(config: config)
  let report = try await restarted.call(
    "daily_report", ["app_id": "12", "interaction": "interactive"])
  #expect(providerItem(report, "apple_ads")["prompt_suppression"].text == "declined")
  #expect(
    try await restarted.database.get("connection_preference", "apple_ads|*")?["until"] == .null)
  #expect(try await restarted.database.get("connection_preference", "apple_ads|12") == nil)
}

private actor ReportConnectionHTTP: HTTPTransport {
  var requests: [URLRequest] = []
  func send(_ request: URLRequest) async throws -> (Data, Int, [String: String]) {
    requests.append(request)
    let path = request.url!.path
    let value: JSON
    if path.contains("oauth") {
      value = ["access_token": "synthetic-token", "expires_in": 3600]
    } else if path.hasSuffix("suggestions/keywords/query") {
      value = ["result": [["text": "budget", "popularity": 40]]]
    } else if path.hasSuffix("analyticsReportRequests") {
      value = ["data": [["id": "request", "attributes": ["accessType": "ONGOING"]]]]
    } else if path.hasSuffix("/reports") {
      value = ["data": []]
    } else if path == "/v1/apps/12" {
      value = ["data": ["id": "12"]]
    } else if request.url!.host == "itunes.apple.com" {
      value = searchFixture()
    } else {
      throw ScopeError("unexpected_request", "No matching synthetic provider response")
    }
    return (try value.encoded(), 200, [:])
  }
}

@Test(arguments: ["apple_ads", "app_store_connect"], ["daily_report", "aso_strategy"])
func reportContinuationPreservesTheAlreadyConnectedProvider(provider: String, tool: String)
  async throws
{
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let complete = try testCredentials(dir)
  let environment = ["APPSCOPE_DATA_DIR": dir.path]
  let file = dir.appendingPathComponent("config.json")
  try PrivateFile.write(
    try complete.values.setting([provider: [:]]).encoded(), to: file, replace: false)
  let initial = try Configuration.load(environment: environment)
  let transport = ReportConnectionHTTP()
  let scope = try AppScope(config: initial, http: HTTP(transport: transport, searchInterval: 0))
  let other = provider == "apple_ads" ? "app_store_connect" : "apple_ads"
  try await scope.saveConnectionEvidence(
    provider: other, app: "12", country: "us", state: "verified",
    capabilities: [other == "apple_ads" ? "keyword_popularity" : "analytics_reports": true],
    configuration: initial)
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["budget"]])
  let report = try await scope.call(tool, ["app_id": "12", "interaction": "interactive"])
  #expect(providerItem(report, provider)["should_invite"].boolValue == true)
  #expect(providerItem(report, other)["should_invite"].boolValue == false)
  let start = try await scope.call(
    "start_connection", providerItem(report, provider)["next_action"]["arguments"].objectValue!)
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["saving"]])
  // A synthetic external save models the private helper; no live provider is contacted.
  try PrivateFile.write(try complete.values.encoded(), to: file, replace: true)
  _ = try await scope.call(
    "connection_status", ["session_id": start["session_id"], "max_steps": 1])
  let restarted = try AppScope(
    config: Configuration.load(environment: environment),
    http: HTTP(transport: transport, searchInterval: 0))
  try await restarted.advanceReadyConnections()
  let done = try await restarted.call("connection_status", ["session_id": start["session_id"]])
  #expect(done["state"].text == "completed")
  #expect(done["result"]["run"]["include_popularity"].boolValue == true)
  #expect(done["result"]["run"]["include_performance"].boolValue == true)
  #expect(done["result"]["run"]["keywords"] == ["budget"])
  #expect(
    done["result"]["run"]["steps"].list.contains {
      $0["kind"].text == "popularity" && $0["status"].text == "succeeded"
    })
  #expect(
    done["result"]["run"]["steps"].list.contains {
      $0["kind"].text == "performance" && $0["status"].text == "succeeded"
    })
  #expect(done["result"]["report"]["health"] != .null)
  #expect(
    providerItem(done["result"], "app_store_connect")["connection_state"].text == "reports_pending")
  #expect(providerItem(done["result"], other)["should_invite"].boolValue == false)
  #expect(!String(data: try done.encoded(), encoding: .utf8)!.contains("synthetic-token"))
}

@Test(arguments: [401, 403, 500])
func failedProviderVerificationDoesNotStartSavedReport(status: Int) async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP(
    Array(repeating: (["detail": "private-provider-body"], status), count: status == 500 ? 3 : 1))
  let scope = try AppScope(config: testCredentials(dir), http: HTTP(transport: transport))
  let start = try await scope.call(
    "start_connection",
    ["provider": "app_store_connect", "app_id": "12", "interaction": "interactive"])
  let failed = try await scope.call("connection_status", ["session_id": start["session_id"]])
  #expect(failed["state"].text == "needs_attention")
  #expect(failed["verification"]["code"].text == "provider_http_\(status)")
  #expect(
    failed["verification"]["connection_state"].text
      == (status == 401
        ? "invalid_credentials" : status == 403 ? "access_denied" : "verification_failed"))
  #expect(try await scope.database.list("refresh_run").isEmpty)
  #expect(!String(data: try failed.encoded(), encoding: .utf8)!.contains("private-provider-body"))
  let count = await transport.requests.count
  try await scope.advanceReadyConnections()
  #expect(await transport.requests.count == count)
}
