import ArgumentParser
import Foundation
import IMsgCore

struct SendCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "send",
    abstract: "Send a message (text and/or attachment)"
  )

  @OptionGroup
  var global: GlobalOptions

  @Option(name: .long, help: "Phone, email, or contact name")
  var to = ""

  @Option(name: .long, help: "Chat rowid")
  var chatID: Int64?

  @Option(name: .long, help: "Chat identifier")
  var chatIdentifier = ""

  @Option(name: .long, help: "Chat guid")
  var chatGUID = ""

  @Option(name: .long, help: "Message body text")
  var text = ""

  @Option(name: .long, help: "Path to attachment file")
  var file = ""

  @Option(name: .long, help: "Service to use: imessage, sms, auto")
  var service = "auto"

  @Option(name: .long, help: "Default region for phone normalization")
  var region = "US"

  mutating func run() async throws {
    let input = ChatTargetInput(
      recipient: to,
      chatID: chatID,
      chatIdentifier: chatIdentifier,
      chatGUID: chatGUID
    )

    try ChatTargetResolver.validateRecipientRequirements(
      input: input,
      mixedTargetError: ValidationError("Use either '--to' or chat target options, not both."),
      missingRecipientError: ValidationError("Missing expected argument '--to'.")
    )

    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      throw ValidationError("Specify at least one of '--text' or '--file'.")
    }

    guard let messageService = MessageService(rawValue: service) else {
      throw ValidationError("Invalid '--service' value '\(service)'. Use: auto, imessage, sms.")
    }

    let contactsResolver = global.makeContactsResolver()
    var resolvedInput = input
    if !resolvedInput.recipient.isEmpty {
      resolvedInput = ChatTargetInput(
        recipient: try ContactsHelpers.resolveRecipient(resolvedInput.recipient, resolver: contactsResolver),
        chatID: resolvedInput.chatID,
        chatIdentifier: resolvedInput.chatIdentifier,
        chatGUID: resolvedInput.chatGUID
      )
    }

    let resolvedTarget = try await ChatTargetResolver.resolveChatTarget(
      input: resolvedInput,
      lookupChat: { chatID in
        let store = try MessageStore(path: global.db)
        return try store.chatInfo(chatID: chatID)
      },
      unknownChatError: { chatID in
        ValidationError("Unknown chat id \(chatID)")
      }
    )

    if resolvedInput.hasChatTarget && resolvedTarget.preferredIdentifier == nil {
      throw ValidationError("Missing chat identifier or guid for selected chat target.")
    }

    try MessageSender().send(
      MessageSendOptions(
        recipient: resolvedInput.recipient,
        text: text,
        attachmentPath: file,
        service: messageService,
        region: region,
        chatIdentifier: resolvedTarget.chatIdentifier,
        chatGUID: resolvedTarget.chatGUID
      )
    )

    if global.json {
      try StdoutWriter.writeJSONLine([
        "status": "sent",
        "recipient": resolvedInput.recipient,
      ])
      return
    }

    if global.verbose, !to.isEmpty, to != resolvedInput.recipient {
      StdoutWriter.writeLine("resolved '\(to)' -> '\(resolvedInput.recipient)'")
    }
    StdoutWriter.writeLine("sent")
  }
}
