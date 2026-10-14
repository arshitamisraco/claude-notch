# Claude Notch — Implementation Plan

A native macOS 14+ app that lives in the MacBook notch. It receives Claude Code hook events over localhost HTTP and lets the user **approve/deny permissions** and **answer AskUserQuestion** from the notch. The UI follows `docs/DESIGN.md` exactly; tokens, sizes, motion and copy come from there.

The code is authored on Linux and cannot be compiled there. **CI on a macOS runner and the user's Mac are the compile loop**, so agents must write conservative, explicit Swift.

---

## 0. Build system: Swift Package + bundling script

**Choice:** a `Package.swift` with one executable target and one test target, plus `scripts/build-app.sh`, which wraps the release binary into `Claude Notch.app` (`LSUIElement=true`) and ad-hoc signs it.

**Why not XcodeGen:**
- It needs `brew install xcodegen`, one more tool on the user's Mac.
- A SwiftPM manifest is plain text and builds with `swift build` from Xcode 15.3+ (Swift 5.10, macOS 14 SDK for `@Observable`).
- `swift test` runs the Core and installer tests without a project file.
- We need no xibs or asset catalogs.

**Settings:** `swift-tools-version:5.10` in Swift 5 language mode. Strict Swift 6 concurrency is deliberately avoided. Core state lives on `@MainActor`; network I/O runs on a private `DispatchQueue`.

**Toolchain details:**
- `@main` must **not** live in a file named `main.swift`.
- No third-party dependencies. HTTP uses `NWListener`, the hotkey uses Carbon `RegisterEventHotKey` (needs no Accessibility permission), and launch at login uses `SMAppService.mainApp`.
- Tests use `@testable import ClaudeNotch`.

---

## 1. File tree and ownership

The **contract files** (`Sources/ClaudeNotch/Contract/`) are committed first by the lead and then frozen. Every other file is owned by exactly one workstream (A = Core, B = UI, C = Integration).

```
claude-notch/
├─ Package.swift                                   C (lead commits initial)
├─ README.md                                       C  build/install/uninstall/troubleshoot
├─ Support/Info.plist                              C  LSUIElement, bundle id dev.claudenotch.ClaudeNotch, LSMinimumSystemVersion 14.0
├─ scripts/
│  ├─ build-app.sh                                 C  swift build -c release [--universal]; assemble .app; codesign -s -; [--install → /Applications]
│  ├─ run-dev.sh                                   C  build-app.sh && open the .app (kills old instance)
│  └─ send-test-event.sh                           C  curl fixtures (permission/question/stop/notify) with token
├─ .github/workflows/ci.yml                        C  macos-14: swift build, swift test, build-app.sh
├─ docs/DESIGN.md, docs/PLAN.md
├─ Sources/ClaudeNotch/
│  ├─ Contract/                                    frozen (lead)
│  │  ├─ Models.swift
│  │  ├─ JSONValue.swift
│  │  └─ Interfaces.swift
│  ├─ Core/                                        ── A
│  │  ├─ Server/HTTPServer.swift                   NWListener on 127.0.0.1:port, per-connection read loop, disconnect callback, Connection: close
│  │  ├─ Server/HTTPRequestParser.swift            incremental HTTP/1.1 parse: request line, headers, Content-Length + chunked, 8 MB cap
│  │  ├─ Server/RequestAuthenticator.swift         token (constant-time), Host, Origin, Content-Type, method/path checks
│  │  ├─ Hooks/HookPayload.swift                   Decodable superset of hook input fields
│  │  ├─ Hooks/HookResponse.swift                  builders for output JSON
│  │  ├─ Hooks/ToolSummarizer.swift                tool_input → (displayToolName, headline, summary, detail), activity text, fingerprint
│  │  ├─ Routing/HookRouter.swift                  dispatch; observe vs hold; dedupe; HookDecision → response
│  │  ├─ State/SessionReducer.swift                pure: (SessionInfo?, HookPayload, now) → SessionInfo; release rules
│  │  ├─ State/DecisionBroker.swift                CheckedContinuation per held item, timeout, single-resume guarantee
│  │  ├─ State/NotchStore.swift                    @Observable store (API §2.3)
│  │  └─ CoreRuntime.swift                         server+router+broker+store; start/restart/shutdown
│  ├─ UI/                                          ── B
│  │  ├─ Theme/Theme.swift
│  │  ├─ Panel/NotchPanel.swift
│  │  ├─ Panel/NotchGeometry.swift
│  │  ├─ Panel/NotchPanelController.swift
│  │  ├─ Panel/FullscreenDetector.swift
│  │  ├─ Panel/GlobalHotKey.swift
│  │  ├─ NotchViewModel.swift
│  │  ├─ Views/NotchRootView.swift
│  │  ├─ Views/NotchShape.swift
│  │  ├─ Views/GlanceEarsView.swift
│  │  ├─ Views/PeekView.swift
│  │  ├─ Views/ExpandedView.swift
│  │  ├─ Views/Cards/EventCard.swift
│  │  ├─ Views/Cards/ApprovalCardBody.swift
│  │  ├─ Views/Cards/QuestionCardBody.swift
│  │  ├─ Views/Cards/StatusCardBody.swift
│  │  ├─ Components/StatusDot.swift, CodeBlock.swift, NotchButton.swift, Badge.swift, KeyHint.swift, SessionRow.swift
│  │  ├─ Accessibility/Announcer.swift
│  │  └─ Preview/PreviewFixtures.swift
│  ├─ App/                                         ── C
│  │  ├─ ClaudeNotchApp.swift                      @main App: MenuBarExtra + Settings scene; NSApplicationDelegateAdaptor
│  │  ├─ AppDelegate.swift                         bootstrap; terminate → shutdown()
│  │  └─ MenuBarContent.swift
│  ├─ Settings/
│  │  ├─ AppSettings.swift                         @Observable UserDefaults-backed; CoreSettings & UISettings; token generation
│  │  └─ SettingsView.swift
│  └─ Integration/
│     ├─ HooksConfig.swift
│     ├─ HooksInstaller.swift
│     ├─ TerminalFocuser.swift
│     ├─ SoundPlayer.swift
│     └─ LaunchAtLogin.swift
└─ Tests/ClaudeNotchTests/
   ├─ HookPayloadDecodingTests.swift               A
   ├─ HTTPRequestParserTests.swift                 A
   ├─ SessionReducerTests.swift                    A
   ├─ DecisionBrokerTests.swift                    A
   ├─ HookResponseTests.swift                      A
   └─ HooksInstallerTests.swift                    C
```

---

## 2. Shared interface contract

§2.1 and §2.2 are in `Sources/ClaudeNotch/Contract/` (frozen). §2.3 and §2.4 are APIs that the named workstream must implement **exactly** as written.

### 2.3 Store API (A implements in `Core/State/NotchStore.swift`; B and C consume it)

```swift
import Observation

@MainActor @Observable
final class NotchStore {
    // read (UI)
    private(set) var sessions: [SessionInfo]       // sorted: status desc, then lastEventAt desc
    private(set) var visibleItems: [NotchItem]     // pending + lingering resolved + done/error/attention < 6s;
                                                   // sorted: pending first, priority desc, createdAt asc
    private(set) var history: [NotchItem]          // last 50 finished items, newest first
    private(set) var latestArrival: NotchItem.ID?  // changes on every newly created item (Peek trigger)
    private(set) var serverState: ServerState

    var pendingItems: [NotchItem] { get }          // visibleItems.filter { $0.isBlocking && $0.isPending }
    var aggregateStatus: SessionStatus { get }     // max(sessions.status ∪ visibleItems.priority) or .idle
    var hasActivity: Bool { get }                  // !visibleItems.isEmpty || any session != .idle
    func session(_ id: SessionID) -> SessionInfo?

    // actions (UI → Core). Idempotent; no-op if item not pending.
    func allow(_ id: NotchItem.ID)
    func allowAlways(_ id: NotchItem.ID)                      // falls back to allow if !canAlwaysAllow
    func deny(_ id: NotchItem.ID, message: String? = nil)    // default "Denied from Claude Notch"
    func answer(_ id: NotchItem.ID, answers: QuestionAnswers)
    func handOffToTerminal(_ id: NotchItem.ID)               // releases with {} then jump(to:)
    func dismiss(_ id: NotchItem.ID)                         // non-blocking items only
    func jump(to sessionID: SessionID)                       // calls terminalFocuser

    // integration (C sets at bootstrap)
    var terminalFocuser: (@MainActor (SessionInfo) -> Void)?
    func addArrivalObserver(_ observer: @escaping @MainActor (NotchItem) -> Void)   // sounds, a11y

    // previews/tests
    static func preview(sessions: [SessionInfo], items: [NotchItem]) -> NotchStore
}
```

### 2.4 Runtime and UI entry points

```swift
// A: Core/CoreRuntime.swift
@MainActor final class CoreRuntime {
    let store: NotchStore
    init(settings: CoreSettings)
    func start()        // bind listener; sets store.serverState
    func restart()      // after port/token change; releases held requests with {}
    func shutdown()     // releaseAll({}), stop listener
}

// B: UI/Panel/NotchPanelController.swift
@MainActor final class NotchPanelController {
    init(store: NotchStore, settings: UISettings)
    func show()
    func hide()
    func toggleExpanded()          // also bound to ⌃⌥C internally
    func settingsDidChange()       // re-pick screen, re-register hotkey
}
```

Core-internal API (A only):

```swift
enum HookDecision: Sendable { case release, approval(ApprovalDecision), answers(QuestionAnswers) }

@MainActor final class DecisionBroker {
    func hold(_ id: UUID, timeout: TimeInterval) async -> HookDecision   // .release on timeout/cancel
    @discardableResult func resolve(_ id: UUID, _ d: HookDecision) -> Bool
    func releaseAll()
    var onTimeout: ((UUID) -> Void)?
}
```

**Bootstrap** (C, `AppDelegate.applicationDidFinishLaunching`):
1. `settings = AppSettings()`
2. `core = CoreRuntime(settings:)`
3. `core.store.terminalFocuser = TerminalFocuser().focus`
4. `core.store.addArrivalObserver(SoundPlayer(settings).play)`
5. `core.start()`
6. `panel = NotchPanelController(store: core.store, settings: settings)`
7. `panel.show()`
8. If hooks are not installed, open Settings → Hooks once.

---

## 3. Hooks written by the installer

There are two endpoints under the marker prefix `/claude-notch/v1/`:
- `/claude-notch/v1/hook` may **hold** a request. It is used for PermissionRequest and for PreToolUse `AskUserQuestion`.
- `/claude-notch/v1/event` is **observe-only** and always returns `200 {}` immediately.

The default port is 41817.

```json
{
  "hooks": {
    "PermissionRequest": [
      { "matcher": "*", "hooks": [ { "type": "http", "url": "http://127.0.0.1:41817/claude-notch/v1/hook", "timeout": 120, "headers": { "X-Claude-Notch-Token": "TOKEN", "X-Claude-Notch-Term": "$TERM_PROGRAM", "X-Claude-Notch-Bundle": "$__CFBundleIdentifier" }, "allowedEnvVars": ["TERM_PROGRAM", "__CFBundleIdentifier"] } ] }
    ],
    "PreToolUse": [
      { "matcher": "AskUserQuestion", "hooks": [ { "type": "http", "url": ".../claude-notch/v1/hook",  "timeout": 120, "headers": {…}, "allowedEnvVars": […] } ] },
      { "matcher": "*",               "hooks": [ { "type": "http", "url": ".../claude-notch/v1/event", "timeout": 5,   "headers": {…}, "allowedEnvVars": […] } ] }
    ],
    "PostToolUse":        [ { "matcher": "*", "hooks": [ { …/event, "timeout": 5 } ] } ],
    "PostToolUseFailure": [ { "matcher": "*", "hooks": [ { …/event, "timeout": 5 } ] } ],
    "Notification":       [ { "hooks": [ { …/event, "timeout": 5 } ] } ],
    "UserPromptSubmit":   [ { "hooks": [ { …/event, "timeout": 5 } ] } ],
    "Stop":               [ { "hooks": [ { …/event, "timeout": 5 } ] } ],
    "SubagentStop":       [ { "hooks": [ { …/event, "timeout": 5 } ] } ],
    "SessionStart":       [ { "hooks": [ { …/event, "timeout": 5 } ] } ],
    "SessionEnd":         [ { "hooks": [ { …/event, "timeout": 5 } ] } ]
  }
}
```

**Verify on a Mac:** the hook `headers` field and `$VAR` interpolation through `allowedEnvVars`. The installer has an `includeTerminalHeaders` flag (on by default), and the server also accepts the token as a `?token=` query parameter. A header value that still starts with `$` was not interpolated and is treated as absent.

**Why PermissionRequest `"*"` is safe:** the app returns allow or deny **only after an explicit user click**. In every other case it returns `{}`, and Claude shows its normal prompt:
- The app is not running: the connection is refused (non-blocking).
- The app crashes: the connection is reset.
- The hold times out: the app answers at 110s, below the 120s hook timeout.
- The user clicks "Answer in terminal".
- The app quits: `releaseAll`.
- Authentication fails: 401, which is non-blocking.

The worst case is a delay of up to the hold timeout, which the user can set from 10 to 115s.

**Dedupe rules:**
- `Notification permission_prompt`: dropped if the session has a pending approval, or one resolved or released in the last 5s. Otherwise it creates an `attention` item: "Waiting for you · Approve in terminal".
- `elicitation_dialog`: same rule, checked against pending questions.
- `idle_prompt`: sets the session status to `.attention` with "Waiting for you". It shows a Peek only, not a persistent card.
- `auth_success`, `agent_completed` and unknown types: activity only.
- `Stop`: one `done` item per turn. Ignored if `stop_hook_active == true`.
- `SubagentStop`: activity only.
- `PostToolUseFailure`: activity "Bash failed". It creates an `error` item only if `showToolFailures` is on.

**Release rules ("Answered in terminal"):** a pending item for the same `session_id` is released on these events. Released means the app responds `{}` if the request is still open, then marks the item `.answeredInTerminal`.

| Pending | Released by |
|---|---|
| approval | PostToolUse/PostToolUseFailure with matching `tool_name`+fingerprint(`tool_input`), UserPromptSubmit, Stop, SessionEnd, HTTP client disconnect, hold timeout |
| question | PostToolUse/PostToolUseFailure with `tool_name == "AskUserQuestion"`, UserPromptSubmit, Stop, SessionEnd, client disconnect, hold timeout |

Do **not** release on an unrelated PreToolUse, because tool calls can run in parallel. If `tool_use_id` is present on both sides, match on it. The fingerprint is `tool_name + "|" + tool_input.compactString()`.

**Response bodies:**
- Allow: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
- Always allow: the allow body plus `"updatedPermissions": <permission_suggestions>`. This is hidden if there are no suggestions.
- Deny: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Claude Notch","interrupt":false}}}`
- Answer: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":<ORIGINAL tool_input with "answers": {...} added>}}`
- Release or observe: `{}` with 200, `Content-Type: application/json` and `Connection: close`.

---

## 4. Security

1. **Loopback only.** `requiredLocalEndpoint = 127.0.0.1:port`, and non-loopback remotes are rejected. Only `POST` is accepted, and only on the two paths.
2. **Shared secret.** A 32-byte `SecRandomCopyBytes` token, base64url, stored in UserDefaults and written into the hook headers. It is compared in constant time; a mismatch gets 401. "Regenerate token" rewrites the hooks.
3. **Browser/CSRF defenses.** A custom-header token, no CORS (`OPTIONS` gets 405), rejection of any request with an `Origin` or `Sec-Fetch-Site` header, a required `Content-Type: application/json`, and a required `Host` of `127.0.0.1:<port>` or `localhost:<port>` (this defeats DNS rebinding).
4. **Decisions come only from local UI.** There is no remote approval path in v1.
5. **Limits.** 8 MB body, a 10s header-read timeout, at most 64 connections, and at most 32 held requests (beyond that, respond `{}`).
6. **Logging.** `os.Logger` with subsystem `dev.claudenotch`. Tool input is logged `.private`, and the token is never logged.

---

## 5. Workstream details

### A — Core
- **HTTPServer:**
  1. `NWListener` on a dedicated queue.
  2. For each connection: accumulate data, parse, authenticate, `await MainActor` router, write the response, `cancel()`.
  3. On `.failed` or `.cancelled` before the response is written: `router.clientDisconnected(requestID)`, which gives `.release` and `.answeredInTerminal`.
  4. `EADDRINUSE` maps to `ServerState.failed("Port N is in use")`.
- **HookPayload:** every field is optional except `session_id` and `hook_event_name`. `tool_input`, `tool_response` and `permission_suggestions` are `JSONValue`. An unknown event gets 200 `{}`.
- **Router (held request):**
  1. Reduce the session.
  2. Build the item.
  3. `store.append`.
  4. `await broker.hold(...)`.
  5. Build the response.
  6. Update the item state.

  If AskUserQuestion has malformed or empty questions, return `{}` immediately and show nothing.
- **Store:**
  - Lifetimes use `Task.sleep`. Resolved items linger 1.5s and then move to history. Done, error and attention items expire after 6s.
  - Sessions are reaped 10s after SessionEnd, or after 30 min with no events while idle or done.
  - Sessions are created lazily from any event.

### B — UI (DESIGN.md exactly)
- **NotchPanel:**
  - `[.borderless, .nonactivatingPanel]`, `level = .statusBar + 1`
  - `collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`
  - Clear background, no shadow
  - Fixed frame of 560×520, top edge at `screen.frame.maxY`, centered on the notch midX
- **NotchGeometry:**
  - `notchH = safeAreaInsets.top`
  - `notchW = frame.width - auxLeft.width - auxRight.width`
  - midX is taken from `auxiliaryTopLeftArea.maxX`
  - With no notch, use a virtual 200×32 notch (the height is the menu bar height when it is > 0)
  - Recompute on screen-parameter and space changes
- **Click-through:**
  - `ignoresMouseEvents = true` by default.
  - Global and local `.mouseMoved` monitors test the cursor against `interactiveRect`, which comes from a PreferenceKey (plus 4pt of slop).
  - Inside the rect: accept mouse events and hover-expand.
  - Outside: collapse after 600ms, unless items are pending (then collapse to Glance).
  - When idle, the rect is the physical notch only.
- **Keyboard:**
  - `canBecomeKey` only while Expanded.
  - A nonactivating panel can take key status without activating the app.
  - Shortcuts: ⌘↩, ⌘⌫, ⌥⌘↩, 1–4, ←/→, Esc.
  - Never call `NSApp.activate`.
- **Layout states:** idle, glance, peek (4s; approvals and questions remain), expanded. The bottom radius animates 10 → 22. Reduce Motion gives a crossfade.
- **Fullscreen:** best effort. If the menu bar window is absent (`CGWindowListCopyWindowInfo`), show a floating pill.
- **Accessibility:** labels on every control, plus `Announcer` for new approvals and questions.

### C — Integration
- **HooksInstaller:** works on `~/.claude/settings.json`, or `$CLAUDE_CONFIG_DIR/settings.json`.
  - **Read:** if the file is missing, start from `{}`. If parsing fails, report `settingsUnreadable` and **never write**.
  - **Merge:** use `JSONSerialization` `[String: Any]`.
    1. Remove every handler whose `url` contains `/claude-notch/v1/` (this is the marker).
    2. Drop groups and event keys only if *we* emptied them.
    3. Append ours.
    - Merging is idempotent.
  - **Backup:** `settings.json.claude-notch.bak-YYYYMMDD-HHMMSS`, keeping the last 5.
  - **Write:** atomic, pretty-printed, sorted keys, keeping the original permissions. Symlinks are resolved first.
  - **Status:** `notInstalled`, `installed`, `outdated`, `settingsUnreadable` or `hooksDisabled`.
  - A port or token change reinstalls the hooks automatically.
- **TerminalFocuser:** tries these in order:
  1. The bundle ID header.
  2. A `TERM_PROGRAM` map (Apple_Terminal, iTerm.app, vscode, ghostty, WezTerm, WarpTerminal, kitty, alacritty, zed).
  3. For editors, opening the cwd with that app.
  4. The Claude desktop app (`com.anthropic.claudefordesktop`).
  5. The last-known terminal.
- **SoundPlayer:** off by default. Approval plays "Funk", question "Tink", done "Glass".
- **LaunchAtLogin:** `SMAppService.mainApp`, with a hint when approval is required.
- **build-app.sh:**
  1. `swift build -c release` (`--universal` builds both architectures).
  2. Assemble `build/Claude Notch.app`.
  3. `codesign --force --sign -`.
  4. `--install` copies the app to /Applications.
- **send-test-event.sh** usage is `permission|question|stop|notify [port]`. The token comes from `defaults read dev.claudenotch.ClaudeNotch authToken`.

---

## 6. Edge cases

- **App not running or crashed:** Claude behaves normally. Quitting sends `{}` to every held request.
- **Terminal prompt held back:** the terminal prompt does not appear while a request is held. Mitigations are the hold timeout, an "Answer in terminal" button on every blocking card, and the release rules.
- **Concurrent sessions:** cards queue by priority with a pager, and the Glance badge shows the pending count.
- **Multi-question AskUserQuestion:** a stepper collects the answers. multiSelect uses toggles plus Submit. "Other" or free text means "Answer in terminal".
- **Huge `tool_input`:** the display is truncated at 20k characters, and the original is echoed back unchanged.
- **Duplicate PermissionRequest with the same fingerprint while one is pending:** it gets `{}` immediately.
- **Missing `cwd`:** the project name is "Claude".
- **settings.json problems:** malformed, missing, symlinked or `disableAllHooks` are all handled. An old port or token shows as `outdated`.
- **Port in use:** shown in the menu, with a "Change port…" action.
- **Display changes:** lid closed or external display only, screens added or removed, Stage Manager, fullscreen and an auto-hidden menu bar are all handled.
- **Desktop app local sessions:** these use the same `settings.json`. `TERM_PROGRAM` is absent there, so focus goes to the Claude app.

## 7. v2 ideas

- **Cloud sessions:** `.claude/settings.json` hooks in the repo POST to an E2E-encrypted relay, which forwards to the Mac (or to an iPhone or Watch).
- **Packaging:** ship as a Claude Code plugin with `hooks.json`.
- **iOS Live Activity:** a Dynamic Island mirror.
- **Tab-level terminal focus:** a `command` hook that captures the TTY or PID, plus AppleScript.
- **Live activity:** a transcript tail (what Claude is doing) and a token or cost meter.
- **Previews and rules:** inline diff previews for Edit approvals, and per-project "always allow" rules.
- **System integration:** App Intents and Shortcuts, Focus filters, and voice answers.
- **Distribution:** Sparkle, notarized builds and a Homebrew cask.
