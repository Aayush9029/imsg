import ArgumentParser
import IMsgCore

struct GlobalOptions: ParsableArguments {
  @Option(name: .long, help: "Path to chat.db")
  var db: String = MessageStore.defaultPath

  @Flag(name: .long, help: "Emit JSON Lines output")
  var json = false

  @Flag(name: .long, help: "Enable verbose logs")
  var verbose = false

  @Flag(name: .long, help: "Disable Contacts name resolution")
  var noContacts = false

  func makeContactsResolver() -> ContactsResolver? {
    noContacts ? nil : ContactsResolver()
  }
}
