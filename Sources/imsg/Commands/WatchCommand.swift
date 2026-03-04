import ArgumentParser
import Foundation
import IMsgCore

struct WatchCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "watch",
    abstract: "Stream incoming messages"
  )

  @OptionGroup
  var global: GlobalOptions

  @Option(name: .long, help: "Limit to chat rowid")
  var chatID: Int64?

  @Option(name: .long, help: "Debounce interval for file events (e.g. 250ms)")
  var debounce = "250ms"

  @Option(name: .customLong("since-rowid"), help: "Start watching after this rowid")
  var sinceRowID: Int64?

  @Option(name: .long, parsing: .upToNextOption, help: "Filter by participant handles")
  var participants: [String] = []

  @Option(name: .long, help: "ISO8601 start date (inclusive)")
  var start: String?

  @Option(name: .long, help: "ISO8601 end date (exclusive)")
  var end: String?

  @Flag(name: .long, help: "Include attachment metadata")
  var attachments = false

  @Flag(name: .long, help: "Include reaction events")
  var reactions = false

  mutating func run() async throws {
    guard let debounceInterval = DurationParser.parse(debounce) else {
      throw ValidationError("Invalid value for '--debounce': \(debounce)")
    }

    let parsedParticipants = ContactsHelpers.parseParticipantValues(participants)
    let filter = try MessageFilter.fromISO(
      participants: parsedParticipants,
      startISO: start,
      endISO: end
    )

    let store = try MessageStore(path: global.db)
    let watcher = MessageWatcher(store: store)
    let config = MessageWatcherConfiguration(
      debounceInterval: debounceInterval,
      batchLimit: 100,
      includeReactions: reactions
    )
    let stream = watcher.stream(chatID: chatID, sinceRowID: sinceRowID, configuration: config)
    let contactsResolver = global.makeContactsResolver()

    for try await message in stream {
      if !filter.allows(message) {
        continue
      }

      let senderName = ContactsHelpers.displayName(for: message.sender, resolver: contactsResolver)

      if global.json {
        let metas = try store.attachments(for: message.rowID)
        let reactionValues = try store.reactions(for: message.rowID)
        let payload = MessagePayload(
          message: message,
          attachments: metas,
          reactions: reactionValues,
          senderName: senderName
        )
        try StdoutWriter.writeJSONLine(payload)
        continue
      }

      let direction = message.isFromMe ? "sent" : "recv"
      let senderLabel = senderName ?? message.sender
      let timestamp = CLIISO8601.format(message.date)

      if message.isReaction, let reactionType = message.reactionType {
        let action = (message.isReactionAdd ?? true) ? "added" : "removed"
        let targetGUID = message.reactedToGUID ?? "unknown"
        StdoutWriter.writeLine(
          "\(timestamp) [\(direction)] \(senderLabel) \(action) \(reactionType.emoji) reaction to \(targetGUID)"
        )
        continue
      }

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
