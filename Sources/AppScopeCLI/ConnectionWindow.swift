import AppKit
import AppScopeCore
import CoreGraphics
import CryptoKit
import Foundation
import MCP
import SwiftUI

enum ConnectionWindowLauncher {
  /// A small local app wrapper gives the one shipped executable a normal macOS window identity.
  /// Its immutable cache is keyed by executable bytes, so upgrades never reuse an old helper.
  static func helperExecutable(_ executable: URL, directory: URL) throws -> URL {
    if Bundle.main.bundleIdentifier == "com.lunarmothstudios.AppScope.Connection" {
      return executable
    }
    let bytes = try Data(contentsOf: executable, options: .mappedIfSafe)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let cache = directory.appendingPathComponent("connection-ui/\(digest)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: cache, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let bundle = cache.appendingPathComponent("AppScope Connection.app", isDirectory: true)
    let binary = bundle.appendingPathComponent("Contents/MacOS/appscope")
    if FileManager.default.fileExists(atPath: binary.path) {
      guard try Data(contentsOf: binary, options: .mappedIfSafe) == bytes else {
        throw ScopeError(
          "setup_window_unavailable",
          "The local setup helper changed. Reinstall AppScope before opening setup.")
      }
      return binary
    }
    let temporary = cache.appendingPathComponent(UUID().uuidString + ".app", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(
      at: temporary.appendingPathComponent("Contents/MacOS"),
      withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.copyItem(
      at: executable, to: temporary.appendingPathComponent("Contents/MacOS/appscope"))
    let info: [String: Any] = [
      "CFBundleIdentifier": "com.lunarmothstudios.AppScope.Connection",
      "CFBundleName": "AppScope Connection",
      "CFBundleDisplayName": "AppScope Connection", "CFBundleExecutable": "appscope",
      "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
      "CFBundleShortVersionString": String(appScopeVersion.split(separator: "-")[0]),
      "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": true,
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: temporary.appendingPathComponent("Contents/Info.plist"), options: .atomic)
    do { try FileManager.default.moveItem(at: temporary, to: bundle) } catch {
      guard (try? Data(contentsOf: binary, options: .mappedIfSafe)) == bytes else { throw error }
    }
    return binary
  }
  static func launch(_ session: String, _ configuration: Configuration) throws {
    guard ProcessInfo.processInfo.environment["APPSCOPE_DISABLE_SETUP_UI"] != "1",
      CGSessionCopyCurrentDictionary() != nil,
      let executable = Bundle.main.executableURL
    else { throw ScopeError("setup_window_unavailable", "Open setup on the Mac running AppScope.") }
    let process = Process()
    process.executableURL = try helperExecutable(
      executable.resolvingSymlinksInPath(), directory: configuration.directory)
    process.arguments = ["connection-window", session]
    process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) {
      _, new in new
    }
    // The helper has no access to the MCP stream and never writes credentials to logs.
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
  }
}

@MainActor @Observable final class ConnectionWindowModel {
  let scope: AppScope
  let config: Configuration
  let sessionID: String
  var session: JSON = [:]
  var fields: [String: String] = [:]
  var keyFile: URL?
  var publicKey = ""
  var error = ""
  var busy = true
  var loaded = false
  var saved = false
  var expectedProvider: JSON = .null
  var provider: String { session["provider"].text }
  var isAds: Bool { provider == "apple_ads" }
  var labels: [(String, String)] {
    isAds
      ? [
        ("client_id", "Client ID"), ("team_id", "Team ID"), ("key_id", "Key ID"),
        ("ad_account_id", "Ad account ID"),
      ]
      : [("issuer_id", "Issuer ID"), ("key_id", "Key ID")]
  }
  var canSave: Bool {
    loaded && !busy && keyFile != nil
      && labels.allSatisfy {
        !(fields[$0.0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }

  init(config: Configuration, sessionID: String) throws {
    self.config = config
    self.sessionID = sessionID
    scope = try AppScope(config: config)
  }
  func load() async {
    do {
      session = try await scope.privateSetupSession(sessionID)
      expectedProvider = config.values[provider]
      for (name, _) in labels { fields[name] = config.values[provider][name].text }
      let existing = config.values[provider]["private_key_path"].text
      if !existing.isEmpty {
        let candidate = URL(fileURLWithPath: existing)
        if (try? CredentialSetup.validateKeyFile(candidate)) != nil { keyFile = candidate }
      }
      if isAds && keyFile == nil { try prepareAdsKey() }
      loaded = true
    } catch { show(error) }
    busy = false
  }
  func show(_ failure: Error) {
    error =
      (failure as? ScopeError)?.message
      ?? "Setup could not finish. Check access to the selected file and try again."
  }
  func openAccount() {
    NSWorkspace.shared.open(Onboarding.accountURL(provider))
  }
  func chooseKey() {
    let panel = NSOpenPanel()
    panel.title = "Choose your Apple private key"
    panel.message =
      "AppScope keeps a private copy on this Mac. The key stays out of your conversation."
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    // Apple .p8 files may have an unregistered/dynamic UTI. Validate the selected
    // file's bytes instead of letting Launch Services incorrectly disable it.
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.selectKey(url)
    }
  }
  func selectKey(_ url: URL) {
    do {
      try CredentialSetup.validateKeyFile(url)
      keyFile = url
      publicKey = ""
      if let id = CredentialSetup.suggestedKeyID(for: url) { fields["key_id"] = id }
      error = ""
    } catch { show(error) }
  }
  func prepareAdsKey() throws {
    let value = try CredentialSetup.prepareAdsKey(
      sessionID: sessionID, environment: config.environment)
    keyFile = URL(fileURLWithPath: value["private_key_path"].text)
    publicKey = value["public_key"].text
  }
  func copyPublicKey() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(publicKey, forType: .string)
  }
  func pasteDetails() {
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    let parsed = CredentialSetup.identifiers(from: text, provider: provider)
    for (field, value) in parsed { fields[field] = value }
    error =
      parsed.isEmpty
      ? "No labeled IDs were found. Copy the API details from Apple, or enter the IDs below." : ""
  }
  func save() async {
    guard canSave, let keyFile else { return }
    busy = true
    error = ""
    do {
      let values = Dictionary(
        uniqueKeysWithValues: labels.map {
          ($0.0, JSON.string((fields[$0.0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)))
        })
      try await scope.savePrivateConnection(
        sessionID: sessionID, fields: values, keyFile: keyFile,
        expectedProvider: expectedProvider)
      saved = true
      NSApplication.shared.terminate(nil)
    } catch { show(error) }
    busy = false
  }
  func cancel() async {
    if !saved { _ = try? await scope.call("cancel_connection", ["session_id": .string(sessionID)]) }
    NSApplication.shared.terminate(nil)
  }
}

@MainActor struct ConnectionSetupView: View {
  @Bindable var model: ConnectionWindowModel
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "lock.shield").font(.system(size: 30)).foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 5) {
          Text(
            model.loaded
              ? "Connect \(Onboarding.title(model.provider))" : "Connect your Apple account"
          )
          .font(.title2.bold())
          Text(
            model.isAds
              ? "Add official keyword popularity to your report."
              : "Add downloads and performance from your own app."
          )
          .foregroundStyle(.secondary)
        }
      }
      if model.loaded {
        Text(
          model.session["app_id"].text == "*"
            ? "For your account"
            : "For app \(model.session["app_id"].text) · \(model.session["country"].text.uppercased())"
        )
        .font(.caption).foregroundStyle(.secondary)
        GroupBox {
          VStack(alignment: .leading, spacing: 12) {
            Text(
              model.isAds
                ? "1. Open Apple Ads → Account settings → API"
                : "1. Open App Store Connect → Team Keys"
            )
            .font(.headline)
            Text(
              model.isAds
                ? "Use an API account with read-only access. If you need a new API client, register the public key AppScope prepared."
                : "Use an existing team API key with access to this app, or have an Admin create one. Download the private key when Apple offers it."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
              Button("Open Apple account", systemImage: "arrow.up.right") { model.openAccount() }
              Link("Setup help", destination: Onboarding.helpURL(model.provider))
              if !model.publicKey.isEmpty {
                Spacer()
                Button("Copy public key") { model.copyPublicKey() }
              }
            }
          }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        GroupBox {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("2. Add the key and Apple IDs").font(.headline)
              Spacer()
              Button("Paste API details") { model.pasteDetails() }
            }
            HStack {
              Image(systemName: model.keyFile == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                .foregroundStyle(model.keyFile == nil ? Color.secondary : Color.green)
              Text(
                model.keyFile == nil
                  ? "Choose or drop your downloaded .p8 file" : "Private key selected"
              )
              .font(.callout)
              Spacer()
              Button(model.keyFile == nil ? "Choose key…" : "Change key…") { model.chooseKey() }
            }
            .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .dropDestination(for: URL.self) { urls, _ in
              guard urls.count == 1, let url = urls.first, url.isFileURL else { return false }
              model.selectKey(url)
              return true
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
              ForEach(model.labels, id: \.0) { name, label in
                GridRow {
                  Text(label).foregroundStyle(.secondary)
                  TextField(
                    label,
                    text: Binding(
                      get: { model.fields[name] ?? "" },
                      set: { model.fields[name] = String($0.prefix(256)) })
                  )
                  .textFieldStyle(.roundedBorder).accessibilityLabel(label)
                }
              }
            }
          }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        Text(
          "Your key stays in private files on this Mac. Your agent verifies access and continues the report after you connect."
        )
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      } else if model.busy {
        ProgressView("Preparing private setup…").frame(maxWidth: .infinity)
      }
      if !model.error.isEmpty {
        Text(model.error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
          .accessibilityIdentifier("setup-error")
      }
      HStack {
        Button("Cancel") { Task { await model.cancel() } }.keyboardShortcut(.cancelAction)
        Spacer()
        if model.busy && model.loaded { ProgressView().controlSize(.small) }
        Button("Connect and continue") { Task { await model.save() } }
          .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!model.canSave)
      }
    }
    .padding(24).frame(width: 620).fixedSize(horizontal: true, vertical: true)
    .task { await model.load() }
  }
}

@MainActor final class ConnectionWindowDelegate: NSObject, NSWindowDelegate, NSApplicationDelegate {
  let model: ConnectionWindowModel
  weak var window: NSWindow?
  init(model: ConnectionWindowModel) { self.model = model }
  func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
    window?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    Task { await model.cancel() }
    return false
  }
  @objc func quit(_ sender: Any?) { Task { await model.cancel() } }
}

@MainActor enum ConnectionWindow {
  static func run(sessionID: String) throws {
    let id = try Validate.identifier(sessionID)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let model = try ConnectionWindowModel(config: Configuration.load(), sessionID: id)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 668, height: 600),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    let delegate = ConnectionWindowDelegate(model: model)
    delegate.window = window
    app.delegate = delegate
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    appItem.submenu = NSMenu(title: "AppScope Connection")
    let quit = NSMenuItem(
      title: "Quit AppScope Connection", action: #selector(ConnectionWindowDelegate.quit(_:)),
      keyEquivalent: "q")
    quit.target = delegate
    appItem.submenu?.addItem(quit)
    let editItem = NSMenuItem()
    menu.addItem(editItem)
    editItem.submenu = NSMenu(title: "Edit")
    for (title, action, key) in [
      ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
      ("Paste", #selector(NSText.paste(_:)), "v"),
      ("Select All", #selector(NSText.selectAll(_:)), "a"),
    ] { editItem.submenu?.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key)) }
    app.mainMenu = menu
    window.delegate = delegate
    window.title = "AppScope · Private connection"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: ConnectionSetupView(model: model))
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    withExtendedLifetime(delegate) { app.run() }
  }
}
