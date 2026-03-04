import ArgumentParser
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

      let last = CLIISO8601.format(chat.lastMessageAt)
      StdoutWriter.writeLine("[\(chat.id)] \(displayName) (\(chat.identifier)) last=\(last)")
    }
  }
}
