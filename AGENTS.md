# imsg

A Swift CLI for Messages.app: it reads chats, history, and live updates from `chat.db`, sends messages and reactions, and shows Contacts names. This repository is a fork of `steipete/imsg` (remote `upstream`) without the JSON-RPC mode. It ships through `aayush9029/tap`. Status: shipped.

## Commands

| Task | Command |
|------|---------|
| Rebuild and run the debug CLI | `make imsg ARGS="chats --limit 5"` |
| Test (syncs the version and patches dependencies first) | `make test` |
| Lint (`swift format` and `swiftlint`) | `make lint` |
| Format | `make format` |
| Universal release build into `bin/` | `make build` |

## Architecture

- `Sources/imsg` holds the argument-parser commands (`chats`, `history`, `watch`, `send`, `react`) and the output.
- `Sources/IMsgCore` holds the read-only SQLite access, the file watcher, the AppleScript sender, the Contacts lookup, and the attributed-body parser.

## Rules

- `version.env` holds the version. `scripts/generate-version.sh` writes `Sources/imsg/Version.swift` and `Sources/imsg/Resources/Info.plist`. Do not edit those two files by hand.
- `scripts/patch-deps.sh` patches the SQLite.swift and PhoneNumberKit checkouts after `swift package resolve`. Use the `make` targets; a plain `swift build` after a fresh resolve can fail.
- The tap formula builds from the source tag and installs `PhoneNumberKit_PhoneNumberKit.bundle` next to the binary. Keep that bundle in the build output.
- Open `chat.db` read-only. Tests use fixtures, not the live Messages database.
- Reads need Full Disk Access for the terminal. Sends need Automation access to Messages.app.
- `docs/RELEASING.md` and `scripts/sign-and-notarize.sh` come from upstream and default to the upstream signing identity. Set `CODESIGN_IDENTITY` to your own `Developer ID Application` identity.
- Use long kebab-case flags (`--chat-id`). Use commit prefixes `feat:`, `fix:`, `chore:`, and `ci:`.
- When you merge from `upstream`, keep the fork changes: no JSON-RPC mode and the Contacts-aware command set.
