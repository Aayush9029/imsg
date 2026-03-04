import ArgumentParser

@main
struct IMsgCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "imsg",
    abstract: "Send and read iMessage / SMS from the terminal",
    version: IMsgVersion.current,
    subcommands: [
      ChatsCommand.self,
      HistoryCommand.self,
      WatchCommand.self,
      SendCommand.self,
      ReactCommand.self,
    ]
  )
}
