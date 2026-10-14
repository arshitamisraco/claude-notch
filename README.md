# Claude Notch

A tiny macOS menu-bar app that lives in your MacBook's notch and surfaces [Claude Code](https://docs.claude.com/en/docs/claude-code) hook events. Approve or deny permission requests, answer Claude's questions, and see when a session finishes, all without leaving what you're doing.

Idle, it looks like the physical notch. When Claude needs you, the notch grows.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15.3+ or the matching Command Line Tools (Swift 5.10)
- Claude Code with HTTP hooks support

## Build and run

```sh
scripts/run-dev.sh              # build, assemble, relaunch the app
scripts/build-app.sh            # build/Claude Notch.app (ad-hoc signed)
scripts/build-app.sh --universal --install   # arm64+x86_64, copy to /Applications
swift test                      # unit tests
```

The app is ad-hoc signed, not notarized. If macOS blocks the first launch, right-click the app and choose Open.

## Install the hooks

1. Launch Claude Notch. On first run it opens **Settings > Hooks**.
2. Click **Install Hooks**. Or use **Install Hooks** in the menu-bar menu.

This merges entries into `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`). Existing settings and hooks are preserved, a timestamped backup is made first (last 5 kept), and the write is atomic. If the file can't be parsed, nothing is written. Changing the port or regenerating the token rewrites the hooks automatically.

Apps launched from Finder don't see your shell's `CLAUDE_CONFIG_DIR`. If you use it, set the path under **Settings > Hooks > settings.json location**.

## How it works

```
Claude Code ──hook event──▶ POST http://127.0.0.1:41817/claude-notch/v1/{hook|event}
                                      │  (token header, loopback only)
                                      ▼
                              Claude Notch (menu-bar app)
                                      │
   /event  observe only ─────────────▶ updates the notch ─▶ responds {} immediately
   /hook   PermissionRequest,
           PreToolUse AskUserQuestion ─▶ shows a card ─▶ holds the request
                                      │
                    you click Allow / Deny / answer ─▶ decision JSON back to Claude
```

## Approvals safety model

Claude Notch only returns an allow or deny decision after an explicit click. In every other case it returns `{}`, and Claude shows its normal terminal prompt:

- the app isn't running (connection refused) or crashes
- you click "Answer in terminal"
- you answer in the terminal first (the card is released)
- the hold times out (default 110s, configurable 10-115s, below the 120s hook timeout)
- the app quits
- the token is wrong (HTTP 401)

The worst case is a delay of up to the hold timeout.

## Works with

- Claude Code CLI in any terminal
- Claude Code IDE extensions (VS Code, Cursor, Zed...)
- Claude desktop app local sessions (same `settings.json`)

Cloud sessions are planned for v2.

Clicking a session focuses its terminal or editor (via the terminal headers the hooks send). Turn headers off in Settings to authenticate through a `?token=` query parameter instead; focus then falls back to the Claude app.

## Try it without Claude

```sh
scripts/send-test-event.sh permission   # also: question | stop | notify | idle [port]
```

## Uninstall

1. **Settings > Hooks > Uninstall** removes only the Claude Notch entries. Other hooks are left alone.
2. Quit the app and delete it from `/Applications`.
3. Optional: `defaults delete dev.claudenotch.ClaudeNotch`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Nothing appears | Check the menu: server must say "Listening". Check Settings > Hooks status. Start a new Claude Code session after installing. |
| "Port 41817 is in use" | Change the port in Settings > Hooks and click Apply. Hooks are rewritten. |
| Status "Update available" | Port, token or options changed. Click Update Hooks. |
| "Hooks disabled in settings" | `disableAllHooks` is true in your settings.json. |
| "settings.json unreadable" | The file isn't valid JSON. Fix it; Claude Notch never overwrites a file it can't parse. |
| Click doesn't focus the terminal | Terminal headers must be on. Header interpolation depends on your Claude Code version. |
| Wrong settings file | Set the path override in Settings > Hooks. |

## Security notes

- The server binds to loopback only and accepts `POST` on two paths.
- Every request needs a random 32-byte token (stored in the app's preferences and written into your hooks). It is compared in constant time.
- Requests with a browser `Origin`, a wrong `Host` or a non-JSON content type are rejected.
- Decisions come only from the local UI. There is no remote approval path.
- Your token is stored in plain text in `settings.json` (as with any hook header). Keep that file private; the installer preserves its permissions.
- No network calls leave your Mac.
