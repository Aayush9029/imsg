import ArgumentParser
import Foundation
import IMsgCore

enum ContactsHelpers {
  static func displayName(for handle: String, resolver: ContactsResolver?) -> String? {
    guard let resolver else { return nil }
    let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let name = resolver.displayName(for: trimmed) else { return nil }
    if name.caseInsensitiveCompare(trimmed) == .orderedSame {
      return nil
    }
    return name
  }

  static func resolveRecipient(_ recipient: String, resolver: ContactsResolver?) throws -> String {
    let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }
    if isLikelyHandle(trimmed) {
      return trimmed
    }

    guard let resolver, let handle = resolver.firstHandle(matching: trimmed) else {
      throw ValidationError(
        "Unable to resolve contact '\(trimmed)'. Use a phone/email or allow Contacts access."
      )
    }
    return handle
  }

  static func parseParticipantValues(_ values: [String]) -> [String] {
    values
      .flatMap { $0.split(separator: ",").map(String.init) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func isLikelyHandle(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    let lower = trimmed.lowercased()
    if lower.hasPrefix("imessage:") || lower.hasPrefix("sms:") || lower.hasPrefix("auto:") {
      return true
    }
    if trimmed.contains("@") {
      return true
    }

    let allowed = CharacterSet(charactersIn: "+0123456789 ()-")
    if trimmed.rangeOfCharacter(from: allowed.inverted) == nil {
      return true
    }

    return false
  }
}
