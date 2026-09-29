import Foundation
import MCP

public typealias JSON = Value
public struct ScopeError: Error, LocalizedError, Sendable {
  public let code: String
  public let message: String
  public let onboarding: JSON?
  public init(_ code: String, _ message: String, onboarding: JSON? = nil) {
    self.code = code
    self.message = message
    self.onboarding = onboarding
  }
  public var errorDescription: String? { message }
  public var json: JSON {
    var fields: [String: JSON] = [
      "status": "error", "code": .string(code), "message": .string(message),
    ]
    if let onboarding { fields["onboarding"] = onboarding }
    return .object(fields)
  }
}

extension Value {
  public subscript(_ key: String) -> Value { objectValue?[key] ?? .null }
  public var text: String { stringValue ?? "" }
  public var list: [Value] { arrayValue ?? [] }
  public var number: Double? { doubleValue ?? intValue.map(Double.init) }
  public static func decode(_ data: Data) throws -> Value {
    try JSONDecoder().decode(Value.self, from: data)
  }
  public func encoded(pretty: Bool = false) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting =
      pretty
      ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      : [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }
  public func jsonText(pretty: Bool = false) throws -> String {
    String(decoding: try encoded(pretty: pretty), as: UTF8.self)
  }
  public static func strings(_ values: [String]) -> Value { .array(values.map(Value.string)) }
  public func setting(_ fields: [String: Value]) -> Value {
    .object((objectValue ?? [:]).merging(fields) { _, new in new })
  }
}

public enum Validate {
  public static func identifier(_ value: String) throws -> String {
    guard let id = UUID(uuidString: value) else {
      throw ScopeError("invalid_identifier", "Use the UUID returned by AppScope.")
    }
    return id.uuidString.lowercased()
  }
  public static func appID(_ value: String) throws -> String {
    guard value.range(of: "^[0-9]{1,20}$", options: .regularExpression) != nil else {
      throw ScopeError("invalid_app_id", "Use the numeric App Store app ID.")
    }
    return value
  }
  public static func country(_ value: String) throws -> String {
    let code = value.lowercased()
    guard code.range(of: "^[a-z]{2}$", options: .regularExpression) != nil,
      Locale.Region.isoRegions.contains(where: { $0.identifier.lowercased() == code })
    else {
      throw ScopeError("invalid_country", "Use a two-letter ISO country code, such as us or gb.")
    }
    return code
  }
  public static func keyword(_ value: String) throws -> String {
    let text = value.precomposedStringWithCompatibilityMapping.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).lowercased()
    guard !text.isEmpty, text.count <= 100, text.rangeOfCharacter(from: .controlCharacters) == nil
    else {
      throw ScopeError(
        "invalid_keyword", "A keyword must contain 1–100 characters without control characters.")
    }
    return text
  }
  public static func date(_ value: String) throws -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
      throw ScopeError("invalid_date", "Use a valid YYYY-MM-DD date.")
    }
    return value
  }
}
public func timestamp(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }
public func day(_ date: Date = Date()) -> String { String(timestamp(date).prefix(10)) }
public func dateOffset(_ value: String, days: Int) -> String {
  let date = ISO8601DateFormatter().date(from: value + "T00:00:00Z")!
  return day(date.addingTimeInterval(Double(days) * 86400))
}
