import Foundation
import MCP
import Testing

@testable import AppScopeCore

actor ProgressRecorder {
  var values: [Double] = []
  var tokens: [ProgressToken] = []
  func record(_ params: ProgressNotification.Parameters) {
    values.append(params.progress)
    tokens.append(params.progressToken)
  }
}

@Test func realMCPProcessListsCallsAndRejectsInvalidTools() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let binary =
    ProcessInfo.processInfo.environment["APPSCOPE_TEST_BINARY"].map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
      ".build/debug/appscope")
  let input = Pipe()
  let output = Pipe()
  let error = Pipe()
  let process = Process()
  process.executableURL = binary
  process.arguments = ["serve"]
  process.environment = [
    "PATH": "/usr/bin:/bin", "APPSCOPE_DATA_DIR": dir.path, "APPSCOPE_DISABLE_SETUP_UI": "1",
  ]
  process.standardInput = input
  process.standardOutput = output
  process.standardError = error
  try process.run()
  defer {
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
  }
  let client = Client(name: "AppScopeIntegrationTest", version: "1.0")
  let transport = StdioTransport(
    input: .init(rawValue: output.fileHandleForReading.fileDescriptor),
    output: .init(rawValue: input.fileHandleForWriting.fileDescriptor))
  _ = try await client.connect(transport: transport)
  let (tools, _) = try await client.listTools()
  #expect(tools.count == ToolCatalog.all.count)
  #expect(!tools.contains { $0.name == "enable_reports" })
  let (content, failed) = try await client.callTool(name: "setup_status", arguments: [:])
  #expect(failed != true)
  if case .text(let text, _, _) = content[0] {
    let result = try JSON.decode(Data(text.utf8))
    #expect(result["apple_ads"].text == "not_configured")
  } else {
    Issue.record("Expected JSON text")
  }
  let (_, invalid) = try await client.callTool(
    name: "track_keywords", arguments: ["app_id": "12", "keywords": ["budget"]])
  #expect(invalid != true)
  let (_, rejected) = try await client.callTool(
    name: "analyze_keyword", arguments: ["app_id": "12", "keyword": "budget", "limit": -1])
  #expect(rejected == true)
  // Resume a saved run through the real stdio boundary without live provider traffic.
  let database = try Database(directory: dir)
  let runID = UUID().uuidString.lowercased()
  try await database.saveSnapshot([
    "app_id": "12", "country": "us", "keyword": "budget", "rank": 2,
    "status": "found", "observed_at": .string(timestamp()), "source": "itunes_search",
    "requested_limit": 200, "competitors": [],
  ])
  try await database.put(
    "refresh_run", runID,
    [
      "run_id": .string(runID), "app_id": "12", "country": "us",
      "day": .string(day()), "status": "paused", "include_popularity": true,
      "include_performance": true,
      "keywords": ["budget"],
      "steps": [
        ["kind": "profile", "status": "succeeded"],
        ["kind": "popularity", "status": "pending", "seeds": ["budget"]],
        ["kind": "ranking", "keyword": "budget", "status": "pending"],
        ["kind": "performance", "status": "pending"],
      ],
    ])
  try await database.put("refresh_latest", "12|us", ["run_id": .string(runID)])
  let recorder = ProgressRecorder()
  await client.onNotification(ProgressNotification.self) { message in
    await recorder.record(message.params)
  }
  let (_, refreshFailed) = try await client.callTool(
    name: "refresh_app", arguments: ["app_id": "12", "run_id": .string(runID)],
    meta: Metadata(progressToken: .string("refresh-test")))
  #expect(refreshFailed != true)
  for _ in 0..<30 {
    if await recorder.values.count == 3 { break }
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(await recorder.values == [2, 3, 4])
  #expect(await recorder.tokens.allSatisfy { $0 == .string("refresh-test") })
  // Exercise the new contract over the actual MCP transport, with UI explicitly disabled.
  let (invitation, invitationFailed) = try await client.callTool(
    name: "daily_report",
    arguments: ["app_id": "12", "interaction": "interactive"])
  #expect(invitationFailed != true)
  if case .text(let text, _, _) = invitation[0] {
    let result = try JSON.decode(Data(text.utf8))
    #expect(
      result["onboarding"]["providers"].list.allSatisfy { $0["should_invite"].boolValue == true })
  }
  let (started, startFailed) = try await client.callTool(
    name: "start_connection",
    arguments: ["provider": "apple_ads", "app_id": "12", "interaction": "interactive"])
  #expect(startFailed != true)
  if case .text(let text, _, _) = started[0] {
    let result = try JSON.decode(Data(text.utf8))
    #expect(result["window"].text == "unavailable")
    let (_, cancelFailed) = try await client.callTool(
      name: "cancel_connection", arguments: ["session_id": result["session_id"]])
    #expect(cancelFailed != true)
  }
  let (_, rejectedCredentials) = try await client.callTool(
    name: "start_connection",
    arguments: [
      "provider": "apple_ads", "app_id": "12", "interaction": "interactive",
      "private_key_path": "forbidden",
    ])
  #expect(rejectedCredentials == true)
  let credentials = try testCredentials(dir)
  try PrivateFile.write(
    try credentials.values.encoded(), to: dir.appendingPathComponent("config.json"), replace: false)
  let (reloaded, reloadFailed) = try await client.callTool(name: "setup_status", arguments: [:])
  #expect(reloadFailed != true)
  if case .text(let text, _, _) = reloaded[0] {
    let result = try JSON.decode(Data(text.utf8))
    #expect(result["apple_ads"].text == "configured_unverified")
    #expect(!text.contains("test-client"))
    #expect(!text.contains("private_key_path"))
  }
  await client.disconnect()
}
