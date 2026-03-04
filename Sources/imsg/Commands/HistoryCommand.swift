import ArgumentParser
import Foundation
import IMsgCore

struct HistoryCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "history",
    abstract: "Show recent messages for a chat"
  )

  @OptionGroup
  var global: GlobalOptions

  @Option(name: .long, help: "Chat rowid from 'imsg chats'")
  var chatID: Int64

  @Option(name: .long, help: "Number of messages to show")
  var limit = 50

  @Option(name: .long, parsing: .upToNextOption, help: "Filter by participant handles")
  var participants: [String] = []

  @Option(name: .long, help: "ISO8601 start date (inclusive)")
  var start: String?

  @Option(name: .long, help: "ISO8601 end date (exclusive)")
  var end: String?

  @Flag(name: .long, help: "Include attachment metadata")
  var attachments = false

  mutating func run() async throws {
    let parsedParticipants = ContactsHelpers.parseParticipantValues(participants)
    let filter = try MessageFilter.fromISO(
      participants: parsedParticipants,
      startISO: start,
      endISO: end
    )

    let store = try MessageStore(path: global.db)
    let messages = try store.messages(chatID: chatID, limit: limit, filter: filter)
    let contactsResolver = global.makeContactsResolver()

    if global.json {
      for message in messages {
        let metas = try store.attachments(for: message.rowID)
        let reactions = try store.reactions(for: message.rowID)
        let senderName = ContactsHelpers.displayName(for: message.sender, resolver: contactsResolver)
        let payload = MessagePayload(
          message: message,
          attachments: metas,
          reactions: reactions,
          senderName: senderName
        )
        try StdoutWriter.writeJSONLine(payload)
      }
      return
    }

    for message in messages {
      let direction = message.isFromMe ? "sent" : "recv"
      let senderName = ContactsHelpers.displayName(for: message.sender, resolver: contactsResolver)
      let senderLabel = senderName ?? message.sender
      let timestamp = CLIISO8601.format(message.date)
      StdoutWriter.writeLine("\(timestamp) [\(direction)] \(senderLabel): \(message.text)")

      if message.attachmentsCount > 0 {
        if attachments {
          let metas = try store.attachments(for: message.rowID)
          for meta in metas {
            let name = displayName(for: meta)
            StdoutWriter.writeLine(
              "  attachment: name=\(name) mime=\(meta.mimeType) missing=\(meta.missing) path=\(meta.originalPath)"
            )
          }
        } else {
          StdoutWriter.writeLine(
            "  (\(message.attachmentsCount) attachment\(pluralSuffix(for: message.attachmentsCount)))"
          )
        }
      }
    }
  }
}
