import AppScopeCore
import CryptoKit
import Darwin
import Foundation
import MCP

@main struct AppScopeCLI {
  @MainActor static func main() async {
    do {
      if CommandLine.arguments.dropFirst().first == "connection-window" {
        guard CommandLine.arguments.count == 3 else { throw ScopeError("usage", "Use appscope connection-window SESSION_ID") }
        try ConnectionWindow.run(sessionID: CommandLine.arguments[2])
      } else { try await run() }
    } catch let error as ScopeError {
      fputs("AppScope [\(error.code)]: \(error.message)\n", stderr)
      exit(1)
    } catch {
      fputs(
        "AppScope: operation failed. Check configuration, filesystem access, and network connectivity.\n",
        stderr)
      exit(1)
    }
  }
  static func run() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty || args[0] == "--help" || args[0] == "help" {
      print(
        """
        AppScope \(appScopeVersion) — app intelligence for MCP agents

        appscope serve                       Start the MCP server over stdio
        appscope setup                       Create private configuration, print MCP connection
        appscope doctor                      Check local setup (no network)
        appscope doctor --live APP_ID         Check configured providers (read-only network)
        appscope configure PROVIDER          Guided local setup: apple-ads or app-store-connect
        appscope connection-window SESSION_ID  Open a private setup session created by your agent
        appscope keygen apple-ads             Create a private P-256 key and print its public key
        appscope call TOOL '{"arg":"value"}'  Call a tool directly and print JSON
        appscope enable-reports APP_ID --confirm  One-time Apple report enablement (Admin)
        appscope --version                   Print version

        Data: ~/Library/Application Support/AppScope (override APPSCOPE_DATA_DIR)
        Config: DATA_DIR/config.json (override APPSCOPE_CONFIG)
        Credentials stay in local files. No dashboard, scheduler, or LLM key required.
        """)
      return
    }
    if args[0] == "--version" {
      print(appScopeVersion)
      return
    }
    if args[0] == "setup" {
      try setup()
      return
    }
    if args[0] == "configure" {
      guard args.count == 2 else {
        throw ScopeError("usage", "Use: appscope configure apple-ads|app-store-connect")
      }
      try configure(args[1])
      return
    }
    if args[0] == "keygen" {
      guard args == ["keygen", "apple-ads"] else {
        throw ScopeError("usage", "Use: appscope keygen apple-ads")
      }
      print(try CredentialSetup.generateAdsKey().jsonText(pretty: true))
      return
    }
    let configuration = try Configuration.load()
    let scope = try AppScope(config: configuration, connectionLauncher: ConnectionWindowLauncher.launch)
    switch args[0] {
    case "doctor":
      if args.count == 1 {
        print(try await scope.status().jsonText(pretty: true))
      } else if args.count == 3 && args[1] == "--live" {
        print(
          try await scope.call("check_connections", ["app_id": .string(args[2])]).jsonText(
            pretty: true))
      } else {
        throw ScopeError("usage", "Use: appscope doctor [--live APP_ID]")
      }
    case "call":
      guard args.count == 3, let object = try JSON.decode(Data(args[2].utf8)).objectValue else {
        throw ScopeError("usage", "Use: appscope call TOOL '{\"argument\":\"value\"}'")
      }
      print(try await scope.call(args[1], object).jsonText(pretty: true))
    case "enable-reports":
      guard args.count == 3, args[2] == "--confirm" else {
        throw ScopeError(
          "usage",
          "Use: appscope enable-reports APP_ID --confirm. This creates an ongoing analytics report request using an Admin key."
        )
      }
      print(try await scope.enableReports(app: args[1]).jsonText(pretty: true))
    case "serve":
      let server = Server(
        name: "AppScope", version: appScopeVersion,
        capabilities: .init(tools: .init(listChanged: false)))
      await server.withMethodHandler(ListTools.self) { _ in .init(tools: ToolCatalog.all) }
      await server.withMethodHandler(CallTool.self) { params in
        do {
          let progress: RefreshProgress?
          if let token = params._meta?.progressToken {
            progress = { completed, total, message in
              try? await server.notify(
                ProgressNotification.message(
                  .init(
                    progressToken: token, progress: Double(completed), total: Double(total),
                    message: message)))
            }
          } else {
            progress = nil
          }
          let result = try await scope.call(
            params.name, params.arguments ?? [:], progress: progress)
          return try .init(
            content: [.text(text: try result.jsonText(), annotations: nil, _meta: nil)],
            structuredContent: result, isError: false)
        } catch let error as ScopeError {
          return try .init(
            content: [.text(text: try error.json.jsonText(), annotations: nil, _meta: nil)],
            structuredContent: error.json, isError: true)
        } catch is CancellationError {
          return .init(
            content: [.text(text: "Request cancelled.", annotations: nil, _meta: nil)],
            isError: true)
        } catch {
          return .init(
            content: [
              .text(
                text:
                  "AppScope could not complete the operation. Run appscope doctor; no private error details are returned.",
                annotations: nil, _meta: nil)
            ], isError: true)
        }
      }
      try await server.start(transport: StdioTransport())
      await server.waitUntilCompleted()
    default: throw ScopeError("usage", "Unknown command. Run appscope --help.")
    }
  }
  static func configure(_ name: String) throws {
    guard isatty(STDIN_FILENO) != 0 else {
      throw ScopeError(
        "terminal_required",
        "Run guided configuration in Terminal. Never pass credentials through MCP or piped prompts."
      )
    }
    let provider = name.replacingOccurrences(of: "-", with: "_")
    let fields = try CredentialSetup.fields(for: provider)
    let config = try Configuration.load()
    print(
      "Configure \(name) locally. Enter identifiers and a private-key FILE PATH, never private-key contents."
    )
    print("Press Return to keep an existing value. Press Ctrl-D to cancel without saving.")
    var values: [String: JSON] = [:]
    for field in fields {
      let existing = config.values[provider][field].text
      print("\(field)\(existing.isEmpty ? "" : " [keep existing]"): ", terminator: "")
      fflush(stdout)
      guard let line = readLine() else {
        throw ScopeError(
          "setup_cancelled", "Configuration cancelled; existing settings are unchanged.")
      }
      let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
      values[field] = .string(value.isEmpty ? existing : value)
    }
    try CredentialSetup.save(provider: provider, fields: values)
    print(
      "Saved private local configuration. Key format and permissions checked; Apple access is still unverified."
    )
    print("AppScope reloads credentials on the next tool call. To test access: appscope doctor --live YOUR_NUMERIC_APP_ID")
  }
  static func setup() throws {
    let environment = ProcessInfo.processInfo.environment
    let directory =
      environment["APPSCOPE_DATA_DIR"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/AppScope")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let path =
      environment["APPSCOPE_CONFIG"].map { URL(fileURLWithPath: $0) }
      ?? directory.appendingPathComponent("config.json")
    if !FileManager.default.fileExists(atPath: path.path) {
      let value: JSON = [
        "apple_ads": [
          "client_id": "", "team_id": "", "key_id": "", "ad_account_id": "", "private_key_path": "",
        ], "app_store_connect": ["issuer_id": "", "key_id": "", "private_key_path": ""],
      ]
      guard
        FileManager.default.createFile(
          atPath: path.path, contents: try value.encoded(pretty: true),
          attributes: [.posixPermissions: 0o600])
      else { throw ScopeError("setup_error", "Could not create the private configuration file.") }
    }
    try Configuration.checkPrivateFile(path)
    let binary = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath().path
    print(
      "Configuration: \(path.path)\nPublic app searches work immediately. Fill in Apple credentials locally to enable account data. Keep private key files outside this repository and chmod 600 them.\n"
    )
    var connection: [String: JSON] = ["command": .string(binary), "args": ["serve"]]
    if environment["APPSCOPE_DATA_DIR"] != nil || environment["APPSCOPE_CONFIG"] != nil {
      connection["env"] = .object([
        "APPSCOPE_DATA_DIR": .string(directory.path), "APPSCOPE_CONFIG": .string(path.path),
      ])
    }
    let json: JSON = ["mcpServers": ["appscope": .object(connection)]]
    print(try json.jsonText(pretty: true))
  }
}
