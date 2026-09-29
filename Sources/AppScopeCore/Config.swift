import CryptoKit
import Foundation
import MCP

public struct Configuration: Sendable {
  public let directory: URL
  public let values: JSON
  public let sourceURL: URL?
  private let fingerprints: [String: String]
  public init(directory: URL, values: JSON = .object([:]), sourceURL: URL? = nil) {
    self.directory = directory
    self.values = values
    self.sourceURL = sourceURL
    fingerprints = Dictionary(
      uniqueKeysWithValues: ["apple_ads", "app_store_connect"].map { provider in
        (provider, Self.fingerprint(values: values, provider: provider))
      })
  }
  public static func load(environment: [String: String] = ProcessInfo.processInfo.environment)
    throws -> Configuration
  {
    let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/AppScope")
    let directory =
      environment["APPSCOPE_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? defaultDirectory
    let path =
      environment["APPSCOPE_CONFIG"].map { URL(fileURLWithPath: $0) }
      ?? directory.appendingPathComponent("config.json")
    guard FileManager.default.fileExists(atPath: path.path) else {
      return Configuration(directory: directory, sourceURL: path)
    }
    try checkPrivateFile(path)
    do {
      let values = try JSON.decode(Data(contentsOf: path))
      guard values.objectValue != nil else {
        throw ScopeError("invalid_config", "Configuration must be a JSON object.")
      }
      return Configuration(directory: directory, values: values, sourceURL: path)
    } catch {
      throw ScopeError(
        "invalid_config", "AppScope configuration must be valid JSON. Run appscope setup.")
    }
  }
  public func credentialStatus(_ name: String) -> String {
    let required =
      name == "apple_ads"
      ? ["client_id", "team_id", "key_id", "private_key_path", "ad_account_id"]
      : ["issuer_id", "key_id", "private_key_path"]
    return required.allSatisfy { !values[name][$0].text.isEmpty }
      ? "configured_unverified" : "not_configured"
  }
  public func credentials(_ name: String) throws -> JSON {
    guard credentialStatus(name) == "configured_unverified" else {
      throw ScopeError(
        "credentials_missing",
        "Connect \(name) with start_connection, or run appscope configure \(name.replacingOccurrences(of: "_", with: "-")). Public searches still work."
      )
    }
    return values[name]
  }
  public var environment: [String: String] {
    [
      "APPSCOPE_DATA_DIR": directory.path,
      "APPSCOPE_CONFIG": (sourceURL ?? directory.appendingPathComponent("config.json")).path,
    ]
  }

  /// Kept only in local evidence records; never returned to the agent.
  func credentialFingerprint(_ provider: String) -> String {
    fingerprints[provider] ?? ""
  }
  private static func fingerprint(values: JSON, provider: String) -> String {
    var bytes = (try? values[provider].encoded()) ?? Data()
    let path = URL(fileURLWithPath: values[provider]["private_key_path"].text)
    if (try? Self.checkPrivateFile(path)) != nil,
      let key = try? PrivateFile.readKey(path)
    {
      bytes.append(key)
    }
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
  public static func checkPrivateFile(_ url: URL) throws {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
      throw ScopeError(
        "unsafe_permissions",
        "Credential files must be readable only by their owner. Use chmod 600 on the configuration and private key files."
      )
    }
    guard attrs[.type] as? FileAttributeType == .typeRegular else {
      throw ScopeError("unsafe_file", "Credentials must be regular files.")
    }
  }
  public func signJWT(_ provider: String, now: Date = Date()) throws -> String {
    let settings = try credentials(provider)
    let keyURL = URL(
      fileURLWithPath: (settings["private_key_path"].text as NSString).expandingTildeInPath)
    do {
      try Self.checkPrivateFile(keyURL)
      let key = try P256.Signing.PrivateKey(
        pemRepresentation: String(decoding: PrivateFile.readKey(keyURL), as: UTF8.self))
      let seconds = Int(now.timeIntervalSince1970)
      let header: JSON = ["alg": "ES256", "kid": settings["key_id"], "typ": "JWT"]
      let claims: JSON =
        provider == "apple_ads"
        ? [
          "iss": settings["team_id"], "sub": settings["client_id"],
          "aud": "https://appleid.apple.com", "iat": .int(seconds), "exp": .int(seconds + 3600),
        ]
        : [
          "iss": settings["issuer_id"], "aud": "appstoreconnect-v1", "iat": .int(seconds),
          "exp": .int(seconds + 900),
        ]
      let signingInput = try header.encoded().base64URL + "." + claims.encoded().base64URL
      let signature = try key.signature(for: Data(signingInput.utf8))
      return signingInput + "." + signature.rawRepresentation.base64URL
    } catch let error as ScopeError { throw error } catch {
      throw ScopeError(
        "invalid_private_key",
        "Unable to read or sign with the configured P-256 private key. Check its path, format, and permissions."
      )
    }
  }
}
extension Data {
  var base64URL: String {
    base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
      of: "/", with: "_"
    ).replacingOccurrences(of: "=", with: "")
  }
}
