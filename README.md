# imsg


macOS CLI for Messages.app. Read chats/history/watch from `chat.db`, send messages from terminal, and resolve phone/email handles to Contacts names.

This fork removes JSON-RPC mode and focuses on direct terminal usage.

## Installation

```bash
brew install aayush9029/tap/imsg
```

Tap-first alternative:

```bash
brew tap aayush9029/tap
brew install imsg
```

Build locally:

```bash
swift build -c release
./.build/release/imsg --help
```

## Usage

```bash
# list recent chats (with contact names when available)
imsg chats --limit 10

# message history for one chat
imsg history --chat-id 1 --limit 25 --attachments

# live stream updates
imsg watch --chat-id 1 --reactions --debounce 250ms

# send by phone/email or contact name
imsg send --to "Ayush" --text "test"

# react to latest message in chat
imsg react --chat-id 1 --reaction like

# shell completions
imsg --generate-completion-script zsh
```

## Commands

### Global options

- `--db <path>`: custom Messages SQLite database path (default: `~/Library/Messages/chat.db`)
- `--json`: JSON Lines output
- `--verbose`: verbose output
- `--no-contacts`: disable Contacts name resolution

### `imsg chats`

- `--limit <n>`: number of chats to list (default: `20`)

### `imsg history`

- `--chat-id <id>`: chat rowid (required)
- `--limit <n>`: number of messages (default: `50`)
- `--participants <handles...>`: filter by handle(s), supports comma-separated values
- `--start <ISO8601>`: inclusive start
- `--end <ISO8601>`: exclusive end
- `--attachments`: include attachment metadata

### `imsg watch`

- `--chat-id <id>`: optional chat scope
- `--debounce <duration>`: fs debounce, e.g. `250ms`, `1s` (default: `250ms`)
- `--since-rowid <id>`: start after rowid
- `--participants <handles...>`: filter by handle(s)
- `--start <ISO8601>` / `--end <ISO8601>`: date filter
- `--attachments`: include attachment metadata
- `--reactions`: include reaction events

### `imsg send`

- `--to <phone|email|contact name>`: recipient (required for direct sends)
- `--text <message>`: message body
- `--file <path>`: attachment path
- `--service <auto|imessage|sms>`: send service (default: `auto`)
- `--region <ISO country>`: phone normalization region (default: `US`)
- Advanced chat targets: `--chat-id`, `--chat-identifier`, `--chat-guid`

### `imsg react`

- `--chat-id <id>`: chat rowid (required)
- `-r, --reaction <value>`: `love`, `like`, `dislike`, `laugh`, `emphasis`, `question`, or single emoji

## Contacts behavior

- `imsg` uses `Contacts.framework` to map handles to display names.
- Nickname is preferred over full name.
- If Contacts permission is denied, commands continue with raw handles (no crash).
- `send --to "Name"` resolves the contact name to a phone/email handle.

## JSON output

`--json` emits one JSON object per line.

- `chats` includes: `id`, `name`, `identifier`, `contact_name`, `service`, `last_message_at`
- `history`/`watch` includes message fields plus `sender_name`, `attachments`, and `reactions`

## Permissions

`imsg` requires macOS permissions:

1. Full Disk Access for your terminal app (to read `chat.db`)
2. Automation access to Messages (for `send`/`react`)
3. Contacts access (optional, for name resolution)

System Settings path: `Privacy & Security`.

## Requirements

- macOS 14+
- Messages.app signed in
- SMS relay configured on iPhone for SMS sends

## Development

```bash
swift build
swift test
```

## License

MIT
