import Foundation
import MCP

public enum Onboarding {
  public static let providers = ["apple_ads", "app_store_connect"]
  public static let continuationTools = [
    "daily_report", "aso_strategy", "refresh_app", "app_performance", "keyword_suggestions",
    "search_term_popularity", "owned_apps",
  ]
  static let relevantTools = Set(continuationTools + ["setup_status", "check_connections"])
  static func provider(for tool: String) -> String? {
    switch tool {
    case "keyword_suggestions", "search_term_popularity": return "apple_ads"
    case "app_performance", "owned_apps": return "app_store_connect"
    default: return nil
    }
  }
  public static func title(_ provider: String) -> String {
    provider == "apple_ads" ? "Apple Ads" : "App Store Connect"
  }
  public static func accountURL(_ provider: String) -> URL {
    URL(
      string: provider == "apple_ads"
        ? "https://ads.apple.com/" : "https://appstoreconnect.apple.com/access/integrations/api")!
  }
  public static func helpURL(_ provider: String) -> URL {
    URL(
      string: provider == "apple_ads"
        ? "https://ads.apple.com/app-store/help/campaigns/0022-use-the-apple-ads-platform-api"
        : "https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api")!
  }
  static func state(for error: ScopeError, appAccess: Bool = false) -> String {
    switch error.code {
    case "credentials_missing": return "not_configured"
    case "provider_http_401", "invalid_private_key", "unsafe_permissions", "unsafe_file":
      return "invalid_credentials"
    case "provider_http_403": return appAccess ? "partial_access" : "access_denied"
    case "reports_not_enabled": return "reports_not_enabled"
    default: return "verification_failed"
    }
  }
}

extension AppScope {
  func evidenceKey(_ provider: String, _ app: String, _ country: String) -> String {
    "\(provider)|\(app)|\(country)"
  }
  func saveConnectionEvidence(
    provider: String, app: String, country: String, state: String,
    capabilities: JSON = [:], error: ScopeError? = nil, configuration: Configuration
  ) async throws {
    let record: JSON = [
      "provider": .string(provider), "app_id": .string(app), "country": .string(country),
      "connection_state": .string(state), "capabilities": capabilities,
      "checked_at": .string(timestamp()), "error": error?.json ?? .null,
      "fingerprint": .string(configuration.credentialFingerprint(provider)),
    ]
    try await database.put("connection_evidence", evidenceKey(provider, app, country), record)
  }
  func saveConnectionEvidence(
    provider: String, app: String, country: String, error: ScopeError,
    configuration: Configuration
  ) async throws {
    try await saveConnectionEvidence(
      provider: provider, app: app, country: country,
      state: Onboarding.state(for: error), error: error, configuration: configuration)
  }
  func observeConnectionResult(
    name: String, args: [String: JSON], result: JSON, configuration: Configuration
  ) async throws {
    guard let provider = Onboarding.provider(for: name) else { return }
    let app = args["app_id"]?.text ?? "*"
    let country = args["country"]?.text.lowercased() ?? "us"
    if name == "app_performance" {
      let sync = result["sync"]
      if sync["status"].text == "not_requested" { return }
      if sync["status"].text == "error" {
        try await saveConnectionEvidence(
          provider: provider, app: app, country: country,
          error: ScopeError(sync["code"].text, sync["message"].text), configuration: configuration)
        return
      }
      try await saveConnectionEvidence(
        provider: provider, app: app, country: country,
        state: sync["status"].text == "pending" ? "reports_pending" : "verified",
        capabilities: [
          "app_access": true, "analytics_reports": .bool(sync["status"].text == "synced"),
        ],
        configuration: configuration)
    } else {
      try await saveConnectionEvidence(
        provider: provider, app: app, country: country,
        state: "verified",
        capabilities: [provider == "apple_ads" ? "keyword_popularity" : "owned_apps": true],
        configuration: configuration)
    }
  }
  func connectionEvidence(provider: String, app: String, country: String) async throws -> JSON? {
    guard
      let saved = try await database.get(
        "connection_evidence", evidenceKey(provider, app, country)),
      saved["fingerprint"].text == config.credentialFingerprint(provider),
      let date = ISO8601DateFormatter().date(from: saved["checked_at"].text),
      Date().timeIntervalSince(date) < 86400
    else { return nil }
    return saved
  }
  func connectionPreference(provider: String, app: String) async throws -> JSON? {
    if let scoped = try await database.get("connection_preference", "\(provider)|\(app)") {
      return scoped
    }
    return try await database.get("connection_preference", "\(provider)|*")
  }
  func onboarding(name: String, args: [String: JSON]) async throws -> JSON {
    let app = args["app_id"]?.text ?? "*"
    let country = args["country"]?.text.lowercased() ?? "us"
    let interactive = args["interaction"]?.text == "interactive"
    var providers = Onboarding.provider(for: name).map { [$0] } ?? Onboarding.providers
    if name == "check_connections", let provider = args["provider"]?.text { providers = [provider] }
    if name == "app_performance", args["sync"]?.boolValue == false { providers = [] }
    if name == "refresh_app" {
      if args["include_popularity"]?.boolValue == false {
        providers.removeAll { $0 == "apple_ads" }
      }
      if args["include_performance"]?.boolValue == false {
        providers.removeAll { $0 == "app_store_connect" }
      }
    }
    var items: [JSON] = []
    for provider in providers {
      let evidence = try await connectionEvidence(provider: provider, app: app, country: country)
      let state =
        config.credentialStatus(provider) == "not_configured"
        ? "not_configured" : evidence?["connection_state"].text ?? "configured_unverified"
      let decision = try await connectionPreference(provider: provider, app: app)
      let declined = decision?["decision"].text == "decline"
      let deferred =
        decision?["decision"].text == "later"
        && (decision?["until"].text ?? "") > timestamp()
      let needsSetup = ["not_configured", "invalid_credentials"].contains(state)
      let capability =
        provider == "apple_ads"
        ? "keyword_popularity" : name == "owned_apps" ? "owned_apps" : "analytics_reports"
      let missing = evidence?["capabilities"][capability].boolValue == true ? [] : [capability]
      let canScope = app != "*" || ["owned_apps", "search_term_popularity"].contains(name)
      let canInvite = needsSetup && interactive && !declined && !deferred && canScope
      var action: JSON = ["kind": "none"]
      if canInvite {
        var original = args
        original.removeValue(forKey: "interaction")
        let resumeTool = Onboarding.continuationTools.contains(name) ? name : "daily_report"
        if resumeTool != name { original = ["app_id": .string(app), "country": .string(country)] }
        var arguments: [String: JSON] = [
          "provider": .string(provider), "country": .string(country),
          "interaction": "interactive", "resume_tool": .string(resumeTool),
          "resume_arguments": .object(original),
        ]
        if app != "*" { arguments["app_id"] = .string(app) }
        action = [
          "kind": "offer_connection", "tool": "start_connection", "arguments": .object(arguments),
        ]
      } else if state == "configured_unverified", app != "*" {
        action = [
          "kind": "verify_connection", "tool": "check_connections",
          "arguments": [
            "app_id": .string(app), "country": .string(country), "provider": .string(provider),
          ],
        ]
      } else if state == "reports_not_enabled" {
        action = [
          "kind": "enable_reports_with_explicit_approval",
          "command": .string("appscope enable-reports \(app) --confirm"),
          "message":
            "An Admin must approve one-time report enablement. Keep the current report partial until then.",
        ]
      } else if state == "reports_pending" {
        action = [
          "kind": "wait_for_apple_reports",
          "message":
            "Connection works. Apple reports are not ready yet; retain the partial report and retry collection later.",
        ]
      } else if ["partial_access", "access_denied"].contains(state) {
        action = [
          "kind": "review_account_access",
          "url": .string(Onboarding.helpURL(provider).absoluteString),
          "message":
            "Ask the account administrator to review access to this app and API. Existing access may still work.",
        ]
      } else if state == "verification_failed", app != "*" {
        action = [
          "kind": "retry_verification", "tool": "check_connections",
          "arguments": [
            "provider": .string(provider), "app_id": .string(app), "country": .string(country),
          ],
        ]
      }
      items.append([
        "provider": .string(provider), "connection_state": .string(state),
        "missing_capabilities": .strings(missing), "capabilities": evidence?["capabilities"] ?? [:],
        "checked_at": evidence?["checked_at"] ?? .null,
        "verification_scope": [
          "app_id": app == "*" ? .null : .string(app), "country": .string(country),
        ],
        "should_invite": .bool(canInvite),
        "prompt_suppression": .string(
          !interactive
            ? "background"
            : declined
              ? "declined" : deferred ? "deferred" : !canScope ? "select_app_first" : "none"),
        "benefit": .string(
          provider == "apple_ads"
            ? "Add official keyword popularity to your research."
            : "Add downloads and performance from your own app."),
        "next_action": action,
      ])
    }
    return [
      "version": 1, "providers": .array(items),
      "host_instructions":
        "Present one short invitation only when should_invite is true, and record the user's later/decline choice with connection_decision. With consent, call start_connection, then connection_status with wait_seconds 20 while the user uses the private window; retrieve the result when completed. AppScope's running server automatically verifies and continues after saving. Stop on needs_attention, cancelled or expired. If the window is unavailable, explain the local fallback. Never request keys, tokens, passwords, or Apple sign-in codes in chat. Background jobs continue with partial data without opening setup. Do not infer that an invitation was displayed from this JSON.",
    ]
  }
}
