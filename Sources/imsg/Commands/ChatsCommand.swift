import ArgumentParser
import Darwin
import Foundation
import IMsgCore

struct ChatsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "chats",
    abstract: "List recent conversations"
  )

  @OptionGroup
  var global: GlobalOptions

  @Option(name: .long, help: "Number of chats to list")
  var limit = 20

  @Flag(name: .long, inversion: .prefixedNo, help: "Show last-message preview in chat list")
  var preview = true

  @Option(name: .long, help: "Maximum characters for preview text")
  var previewChars = 64

  @Flag(name: .long, inversion: .prefixedNo, help: "Colorize interactive output")
  var color = true

  mutating func run() async throws {
    let store = try MessageStore(path: global.db)
    let chats = try store.listChats(limit: limit)
    let contactsResolver = global.makeContactsResolver()

    if global.json {
      for chat in chats {
        let contactName = ContactsHelpers.displayName(for: chat.identifier, resolver: contactsResolver)
        try StdoutWriter.writeJSONLine(ChatPayload(chat: chat, contactName: contactName))
      }
      return
    }

    let colorEnabled = shouldUseColor()
    var rows: [ChatRow] = []

    for chat in chats {
      let contactName = ContactsHelpers.displayName(for: chat.identifier, resolver: contactsResolver)
      let displayName: String
      if let contactName {
        if chat.name.isEmpty || chat.name == chat.identifier {
          displayName = contactName
        } else if chat.name.caseInsensitiveCompare(contactName) == .orderedSame {
          displayName = chat.name
        } else {
          displayName = "\(chat.name) [\(contactName)]"
        }
      } else {
        displayName = chat.name
      }

      let previewText: String
      if preview {
        previewText = try latestMessagePreview(chatID: chat.id, store: store)
      } else {
        previewText = ""
      }
      rows.append(
        ChatRow(
          id: String(chat.id),
          name: displayName,
          handle: chat.identifier,
          service: chat.service,
          lastMessageAt: CLIISO8601.format(chat.lastMessageAt),
          preview: previewText
        )
      )
    }

    let table = ChatsTable(rows: rows, colorEnabled: colorEnabled, previewChars: max(previewChars, 0))
    for line in table.render() {
      StdoutWriter.writeLine(line)
    }

    if let first = rows.first {
      let hint = "Tip: imsg history --chat-id \(first.id) --limit 30"
      StdoutWriter.writeLine(colorEnabled ? ANSI.dim(hint) : hint)
    }
  }

  private func shouldUseColor() -> Bool {
    if !color { return false }
    if global.json { return false }
    if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
    return isatty(fileno(stdout)) != 0
  }

  private func latestMessagePreview(chatID: Int64, store: MessageStore) throws -> String {
    guard let message = try store.messages(chatID: chatID, limit: 1).first else {
      return ""
    }
    if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return message.text
    }
    if message.attachmentsCount > 0 {
      return "(\(message.attachmentsCount) attachment\(pluralSuffix(for: message.attachmentsCount)))"
    }
    return "(no text)"
  }
}

private struct ChatRow {
  let id: String
  let name: String
  let handle: String
  let service: String
  let lastMessageAt: String
  let preview: String
}

private struct ChatsTable {
  let rows: [ChatRow]
  let colorEnabled: Bool
  let previewChars: Int

  func render() -> [String] {
    let idWidth = width(for: \.id, header: "CHAT_ID", max: 12)
    let nameWidth = width(for: \.name, header: "NAME", max: 28)
    let handleWidth = width(for: \.handle, header: "HANDLE", max: 28)
    let serviceWidth = width(for: \.service, header: "SERVICE", max: 10)
    let lastWidth = max(24, "LAST_MESSAGE_AT".count)

    var lines: [String] = []
    lines.append(
      ANSI.bold(
        [
          fit("CHAT_ID", width: idWidth),
          fit("NAME", width: nameWidth),
          fit("HANDLE", width: handleWidth),
          fit("SERVICE", width: serviceWidth),
          fit("LAST_MESSAGE_AT", width: lastWidth),
          "PREVIEW",
        ].joined(separator: "  "),
        enabled: colorEnabled
      )
    )

    for row in rows {
      let previewText = compactWhitespace(row.preview)
      let clippedPreview = clip(previewText, limit: previewChars)
      lines.append(
        [
          ANSI.cyan(fit(row.id, width: idWidth), enabled: colorEnabled),
          fit(row.name, width: nameWidth),
          ANSI.yellow(fit(row.handle, width: handleWidth), enabled: colorEnabled),
          ANSI.green(fit(row.service, width: serviceWidth), enabled: colorEnabled),
          ANSI.dim(fit(row.lastMessageAt, width: lastWidth), enabled: colorEnabled),
          ANSI.dim(clippedPreview, enabled: colorEnabled),
        ].joined(separator: "  ")
      )
    }

    return lines
  }

  private func width(
    for keyPath: KeyPath<ChatRow, String>,
    header: String,
    max: Int
  ) -> Int {
    let rowMax = rows.map { $0[keyPath: keyPath].count }.max() ?? 0
    return min(max, Swift.max(header.count, rowMax))
  }

  private func fit(_ value: String, width: Int) -> String {
    guard width > 0 else { return "" }
    if value.count == width { return value }
    if value.count < width {
      return value + String(repeating: " ", count: width - value.count)
    }
    if width <= 3 { return String(value.prefix(width)) }
    return String(value.prefix(width - 3)) + "..."
  }

  private func clip(_ value: String, limit: Int) -> String {
    guard limit > 0, value.count > limit else { return value }
    if limit <= 3 { return String(value.prefix(limit)) }
    return String(value.prefix(limit - 3)) + "..."
  }

  private func compactWhitespace(_ value: String) -> String {
    value
      .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
      .map(String.init)
      .joined(separator: " ")
  }
}

private enum ANSI {
  private static let reset = "\u{001B}[0m"
  private static let boldCode = "\u{001B}[1m"
  private static let dimCode = "\u{001B}[2m"
  private static let cyanCode = "\u{001B}[36m"
  private static let yellowCode = "\u{001B}[33m"
  private static let greenCode = "\u{001B}[32m"

  static func bold(_ value: String, enabled: Bool) -> String {
    colorize(value, code: boldCode, enabled: enabled)
  }

  static func dim(_ value: String, enabled: Bool = true) -> String {
    colorize(value, code: dimCode, enabled: enabled)
  }

  static func cyan(_ value: String, enabled: Bool) -> String {
    colorize(value, code: cyanCode, enabled: enabled)
  }

  static func yellow(_ value: String, enabled: Bool) -> String {
    colorize(value, code: yellowCode, enabled: enabled)
  }

  static func green(_ value: String, enabled: Bool) -> String {
    colorize(value, code: greenCode, enabled: enabled)
  }

  private static func colorize(_ value: String, code: String, enabled: Bool) -> String {
    guard enabled else { return value }
    return code + value + reset
  }
}
