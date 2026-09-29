import CryptoKit
import Darwin
import Foundation
import MCP

enum PrivateFile {
  static func readKey(_ url: URL) throws -> Data {
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    guard descriptor >= 0 else {
      throw ScopeError("invalid_private_key", "Choose a readable P-256 private-key file.")
    }
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
      info.st_uid == getuid(), info.st_size > 0, info.st_size <= 32_768
    else {
      throw ScopeError(
        "invalid_private_key", "Choose a regular private-key file owned by you, smaller than 32 KB."
      )
    }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count < 0 && errno == EINTR { continue }
      guard count >= 0, data.count + max(0, count) <= 32_768 else {
        throw ScopeError("invalid_private_key", "Cannot read the selected private-key file.")
      }
      if count == 0 { break }
      data.append(contentsOf: buffer.prefix(count))
    }
    return data
  }
  static func write(_ data: Data, to url: URL, replace: Bool) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      guard replace else {
        throw ScopeError("file_exists", "A key file already exists. It will not be replaced.")
      }
      try Configuration.checkPrivateFile(url)
    }
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".appscope-\(UUID().uuidString).tmp")
    let descriptor = open(
      temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw ScopeError("setup_error", "Cannot create a private temporary configuration file.")
    }
    defer {
      close(descriptor)
      try? FileManager.default.removeItem(at: temporary)
    }
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else {
          throw ScopeError("setup_error", "Cannot write private configuration.")
        }
        offset += count
      }
    }
    guard fsync(descriptor) == 0 else {
      throw ScopeError("setup_error", "Cannot persist private configuration.")
    }
    if replace {
      guard rename(temporary.path, url.path) == 0 else {
        throw ScopeError("setup_error", "Cannot replace local configuration.")
      }
    } else {
      // link is atomic and fails if another creator won the destination name.
      guard link(temporary.path, url.path) == 0 else {
        throw ScopeError("file_exists", "A key file already exists or cannot be created.")
      }
    }
  }
}

public enum CredentialSetup {
  public static func configURL(environment: [String: String] = ProcessInfo.processInfo.environment)
    -> URL
  {
    if let path = environment["APPSCOPE_CONFIG"] { return URL(fileURLWithPath: path) }
    let directory =
      environment["APPSCOPE_DATA_DIR"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/AppScope")
    return directory.appendingPathComponent("config.json")
  }
  public static func fields(for provider: String) throws -> [String] {
    switch provider {
    case "apple_ads":
      return ["client_id", "team_id", "key_id", "ad_account_id", "private_key_path"]
    case "app_store_connect": return ["issuer_id", "key_id", "private_key_path"]
    default: throw ScopeError("invalid_provider", "Choose apple-ads or app-store-connect.")
    }
  }
  public static func save(
    provider: String, fields: [String: JSON],
    expectedProvider: JSON? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    let required = try Self.fields(for: provider)
    guard Set(fields.keys) == Set(required),
      required.allSatisfy({
        guard let text = fields[$0]?.stringValue else { return false }
        return !text.isEmpty && text.count <= 4096
          && text.rangeOfCharacter(from: .controlCharacters) == nil
          && !text.contains("PRIVATE KEY")
      })
    else {
      throw ScopeError(
        "invalid_credentials",
        "Every required identifier and a local private-key path must be supplied.")
    }
    let path = configURL(environment: environment)
    try FileManager.default.createDirectory(
      at: path.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let lock: RefreshLock
    do {
      lock = try RefreshLock(
        directory: path.deletingLastPathComponent(), app: "configuration", country: "local")
    } catch {
      throw ScopeError(
        "configuration_busy",
        "Cannot lock configuration. Finish any other setup process and check directory access.")
    }
    defer { lock.release() }
    let old = try Configuration.load(environment: environment)
    if let expectedProvider, old.values[provider] != expectedProvider {
      throw ScopeError(
        "configuration_changed",
        "This account changed in another setup window. Reopen setup to use the latest values.")
    }
    var values = old.values.objectValue ?? [:]
    var normalized = fields
    let keyPath = (fields["private_key_path"]!.text as NSString).expandingTildeInPath
    normalized["private_key_path"] = .string(URL(fileURLWithPath: keyPath).standardizedFileURL.path)
    values[provider] = .object(normalized)
    let candidate = Configuration(directory: old.directory, values: .object(values))
    if provider == "apple_ads" { _ = try Validate.appID(fields["ad_account_id"]!.text) }
    // Offline key-format/permission check; the JWT is never returned or logged.
    _ = try candidate.signJWT(provider)
    try PrivateFile.write(try candidate.values.encoded(pretty: true), to: path, replace: true)
  }

  public static func suggestedKeyID(for file: URL) -> String? {
    let stem = file.deletingPathExtension().lastPathComponent
    let candidate = stem.hasPrefix("AuthKey_") ? String(stem.dropFirst(8)) : ""
    return candidate.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
      ? candidate : nil
  }
  public static func identifiers(from text: String, provider: String) -> [String: String] {
    guard text.utf8.count <= 16_384, !text.contains("PRIVATE KEY") else { return [:] }
    let labels =
      provider == "apple_ads"
      ? [
        "client_id": "client", "team_id": "team", "key_id": "key",
        "ad_account_id": "ad\\s*account",
      ]
      : ["issuer_id": "issuer", "key_id": "key"]
    var result: [String: String] = [:]
    for (field, label) in labels {
      let pattern = "(?im)^\\s*" + label + "[ _]*id\\s*[:=]?\\s*([A-Za-z0-9.-]{1,256})\\s*$"
      guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let range = Range(match.range(at: 1), in: text)
      else { continue }
      result[field] = String(text[range])
    }
    return result
  }
  public static func validateKeyFile(_ file: URL) throws {
    do {
      _ = try P256.Signing.PrivateKey(
        pemRepresentation: String(decoding: PrivateFile.readKey(file), as: UTF8.self))
    } catch {
      throw ScopeError(
        "invalid_private_key",
        "Choose a valid P-256 private key (.p8 or .pem). Its contents stay on this Mac.")
    }
  }
  public static func importAndSave(
    provider: String, fields: [String: JSON], keyFile: URL, expectedProvider: JSON,
    environment: [String: String]
  ) throws {
    let config = try Configuration.load(environment: environment)
    let key: P256.Signing.PrivateKey
    do {
      key = try P256.Signing.PrivateKey(
        pemRepresentation: String(decoding: PrivateFile.readKey(keyFile), as: UTF8.self))
    } catch {
      throw ScopeError(
        "invalid_private_key", "The selected file is not a readable P-256 private key.")
    }
    let folder = config.directory.appendingPathComponent("keys", isDirectory: true)
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let destination = folder.appendingPathComponent(
      "\(provider)-\(UUID().uuidString.lowercased()).p8")
    try PrivateFile.write(Data(key.pemRepresentation.utf8), to: destination, replace: false)
    do {
      var values = fields
      values["private_key_path"] = .string(destination.path)
      try save(
        provider: provider, fields: values, expectedProvider: expectedProvider,
        environment: environment)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }

  /// Idempotent within one private window; never exposed through MCP.
  public static func prepareAdsKey(sessionID: String, environment: [String: String]) throws -> JSON
  {
    let id = try Validate.identifier(sessionID)
    let config = try Configuration.load(environment: environment)
    let folder = config.directory.appendingPathComponent("keys", isDirectory: true)
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let file = folder.appendingPathComponent("ads-setup-\(id).p8")
    let key: P256.Signing.PrivateKey
    if FileManager.default.fileExists(atPath: file.path) {
      try Configuration.checkPrivateFile(file)
      key = try P256.Signing.PrivateKey(
        pemRepresentation: String(decoding: PrivateFile.readKey(file), as: UTF8.self))
    } else {
      key = P256.Signing.PrivateKey()
      try PrivateFile.write(Data(key.pemRepresentation.utf8), to: file, replace: false)
    }
    return [
      "private_key_path": .string(file.path),
      "public_key": .string(key.publicKey.pemRepresentation),
    ]
  }
  public static func generateAdsKey(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> JSON {
    let config = try Configuration.load(environment: environment)
    try FileManager.default.createDirectory(
      at: config.directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let keyPath = config.directory.appendingPathComponent("apple-ads-private.p8")
    let publicPath = config.directory.appendingPathComponent("apple-ads-public.pem")
    guard !FileManager.default.fileExists(atPath: keyPath.path),
      !FileManager.default.fileExists(atPath: publicPath.path)
    else {
      throw ScopeError(
        "file_exists",
        "Apple Ads key files already exist in the data directory. Existing keys are preserved.")
    }
    let key = P256.Signing.PrivateKey()
    try PrivateFile.write(Data(key.pemRepresentation.utf8), to: keyPath, replace: false)
    // If public-key creation fails, retain the generated private key so it is not lost.
    try PrivateFile.write(
      Data(key.publicKey.pemRepresentation.utf8), to: publicPath, replace: false)
    return [
      "private_key_path": .string(keyPath.path), "public_key_path": .string(publicPath.path),
      "public_key": .string(key.publicKey.pemRepresentation),
      "next_step":
        "Give Apple only this public key when creating an Ads API client. Then run appscope configure apple-ads. Private key bytes are never printed.",
    ]
  }
}

extension AppScope {
  func checkConnections(app: String, country: String, provider: String? = nil) async throws -> JSON
  {
    var checks: [String: JSON] = [:]
    for name in provider.map({ [$0] }) ?? ["public_search", "apple_ads", "app_store_connect"] {
      if name == "public_search" {
        do {
          _ = try await storefront.lookup(app, country: country)
          checks[name] = ["status": "ok", "checked_at": .string(timestamp())]
        } catch is CancellationError { throw CancellationError() } catch {
          checks[name] =
            (error as? ScopeError)?.json ?? ScopeError("check_failed", "Public lookup failed.").json
        }
      } else {
        checks[name] = try await verifyConnection(provider: name, app: app, country: country)
      }
    }
    return [
      "app_id": .string(app), "country": .string(country), "checks": .object(checks),
      "status": .string(
        checks.values.contains { $0["status"].text == "error" } ? "partial" : "checked"),
      "scope":
        "Read-only scoped provider checks. Only sanitized capability results are saved. No reports are enabled or downloaded; report coverage and device ranks remain unverified.",
    ]
  }

  func verifyConnection(provider: String, app: String, country: String) async throws -> JSON {
    try Task.checkCancellation()
    let snapshot = config
    let adsClient = ads
    let connectClient = connect
    if snapshot.credentialStatus(provider) == "not_configured" {
      return ["status": "not_configured", "connection_state": "not_configured"]
    }
    var capabilities: JSON = [:]
    var details: JSON = [:]
    do {
      var state = "verified"
      if provider == "apple_ads" {
        let result = try await adsClient.suggestions(
          app: app, country: country, seeds: [], offset: 0)
        capabilities = ["keyword_popularity": true]
        details = ["suggestions_returned": .int(result["suggestions"].list.count)]
      } else if app == "*" {
        _ = try await connectClient.get(
          endpoint("https://api.appstoreconnect.apple.com/v1/apps", query: ["limit": "1"]))
        capabilities = ["owned_apps": true]
      } else {
        let result = try await connectClient.get(
          endpoint("https://api.appstoreconnect.apple.com/v1/apps/\(app)"))
        guard result["data"]["id"].text == app else {
          throw ScopeError("app_access_unverified", "Apple did not confirm access to this app.")
        }
        capabilities = ["app_access": true]
        // One bounded page is enough to establish API access. Pagination is unknown, never disabled.
        let requests = try await connectClient.get(
          endpoint(
            "https://api.appstoreconnect.apple.com/v1/apps/\(app)/analyticsReportRequests",
            query: ["limit": "200"]))
        let ongoing = requests["data"].list.contains {
          $0["attributes"]["accessType"].text == "ONGOING"
            && $0["attributes"]["stoppedDueToInactivity"].boolValue != true
        }
        let more = !requests["links"]["next"].text.isEmpty
        capabilities = capabilities.setting([
          "analytics_report_requests": true, "analytics_reports": false,
        ])
        state = ongoing || more ? "verified" : "reports_not_enabled"
        details = [
          "ongoing_reports_enabled": ongoing ? true : more ? .null : false,
          "next_step": .string(
            ongoing || more
              ? "Run app_performance to validate report downloads and coverage."
              : "An Admin must approve one-time report enablement with the CLI."),
        ]
      }
      try await saveConnectionEvidence(
        provider: provider, app: app, country: country,
        state: state, capabilities: capabilities, configuration: snapshot)
      return details.setting([
        "status": "ok", "connection_state": .string(state),
        "capabilities": capabilities, "checked_at": .string(timestamp()),
      ])
    } catch is CancellationError { throw CancellationError() } catch {
      let safe =
        (error as? ScopeError)
        ?? ScopeError("check_failed", "The connection check could not finish. Check local setup.")
      let state = Onboarding.state(
        for: safe, appAccess: capabilities["app_access"].boolValue == true)
      try await saveConnectionEvidence(
        provider: provider, app: app, country: country,
        state: state, capabilities: capabilities, error: safe, configuration: snapshot)
      return safe.json.setting([
        "connection_state": .string(state), "capabilities": capabilities,
        "checked_at": .string(timestamp()),
      ])
    }
  }
}
