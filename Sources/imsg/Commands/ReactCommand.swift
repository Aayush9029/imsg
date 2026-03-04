import ArgumentParser
import Foundation
import IMsgCore

struct ReactCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "react",
    abstract: "Send a tapback reaction to the most recent message"
  )

  @OptionGroup
  var global: GlobalOptions

  @Option(name: .long, help: "Chat rowid to react in")
  var chatID: Int64

  @Option(name: [.short, .long], help: "Reaction: love, like, dislike, laugh, emphasis, question, or emoji")
  var reaction: String

  mutating func run() async throws {
    guard let reactionType = ReactionType.parse(reaction) else {
      throw ValidationError("Invalid reaction '\(reaction)'.")
    }

    if case .custom(let emoji) = reactionType, !isSingleEmoji(emoji) {
      throw ValidationError("Invalid custom emoji reaction '\(reaction)'.")
    }

    let store = try MessageStore(path: global.db)
    guard let chatInfo = try store.chatInfo(chatID: chatID) else {
      throw IMsgError.chatNotFound(chatID: chatID)
    }

    let chatLookup = preferredChatLookup(chatInfo: chatInfo)
    try sendReaction(reactionType: reactionType, chatGUID: chatInfo.guid, chatLookup: chatLookup)

    if global.json {
      let result = ReactResult(
        success: true,
        chatID: chatID,
        reactionType: reactionType.name,
        reactionEmoji: reactionType.emoji
      )
      try JSONLines.print(result)
      return
    }

    StdoutWriter.writeLine("Sent \(reactionType.emoji) reaction to chat \(chatID)")
  }

  private func sendReaction(reactionType: ReactionType, chatGUID: String, chatLookup: String) throws {
    let keyNumber: Int
    switch reactionType {
    case .love: keyNumber = 1
    case .like: keyNumber = 2
    case .dislike: keyNumber = 3
    case .laugh: keyNumber = 4
    case .emphasis: keyNumber = 5
    case .question: keyNumber = 6
    case .custom:
      let script = """
        on run argv
          set chatGUID to item 1 of argv
          set chatLookup to item 2 of argv
          set customEmoji to item 3 of argv

          tell application "Messages"
            activate
            set targetChat to chat id chatGUID
          end tell

          delay 0.3

          tell application "System Events"
            tell process "Messages"
              keystroke "f" using command down
              delay 0.15
              keystroke "a" using command down
              keystroke chatLookup
              delay 0.25
              key code 36
              delay 0.35
              keystroke "t" using command down
              delay 0.2
              keystroke customEmoji
              delay 0.1
              key code 36
            end tell
          end tell
        end run
        """
      try runAppleScript(script, arguments: [chatGUID, chatLookup, reactionType.emoji])
      return
    }

    let script = """
      on run argv
        set chatGUID to item 1 of argv
        set chatLookup to item 2 of argv
        set reactionKey to item 3 of argv

        tell application "Messages"
          activate
          set targetChat to chat id chatGUID
        end tell

        delay 0.3

        tell application "System Events"
          tell process "Messages"
            keystroke "f" using command down
            delay 0.15
            keystroke "a" using command down
            keystroke chatLookup
            delay 0.25
            key code 36
            delay 0.35
            keystroke "t" using command down
            delay 0.2
            keystroke reactionKey
          end tell
        end tell
      end run
      """
    try runAppleScript(script, arguments: [chatGUID, chatLookup, "\(keyNumber)"])
  }

  private func preferredChatLookup(chatInfo: ChatInfo) -> String {
    let preferred = chatInfo.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !preferred.isEmpty {
      return preferred
    }
    let identifier = chatInfo.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    if !identifier.isEmpty {
      return identifier
    }
    return chatInfo.guid
  }

  private func isSingleEmoji(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == 1 else { return false }
    guard let scalar = trimmed.unicodeScalars.first else { return false }
    return scalar.properties.isEmoji || scalar.properties.isEmojiPresentation
  }

  private func runAppleScript(_ source: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "AppleScript", "-"] + arguments

    let stdinPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardError = stderrPipe

    try process.run()
    if let data = source.data(using: .utf8) {
      stdinPipe.fileHandleForWriting.write(data)
    }
    stdinPipe.fileHandleForWriting.closeFile()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8) ?? "Unknown AppleScript error"
      throw IMsgError.appleScriptFailure(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }
}

struct ReactResult: Codable {
  let success: Bool
  let chatID: Int64
  let reactionType: String
  let reactionEmoji: String

  enum CodingKeys: String, CodingKey {
    case success
    case chatID = "chat_id"
    case reactionType = "reaction_type"
    case reactionEmoji = "reaction_emoji"
  }
}
