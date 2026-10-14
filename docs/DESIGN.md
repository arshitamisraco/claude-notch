# Claude Notch — Design System

Minimal, modern, quiet. The notch is hardware; the app should feel like it *is* the hardware coming alive, not a window sitting on top of it.

## Principles

1. **Invisible until needed.** Idle = indistinguishable from the physical notch. No chrome, no borders.
2. **One glance, one action.** Every expanded state answers "what does Claude need?" and offers at most two primary actions.
3. **Urgency is shape + color, not noise.** Approvals persist; completions fade. Sound is opt-in.
4. **Motion is physical.** Everything grows out of the notch with springs; nothing fades in from nowhere.
5. **Keyboard-first.** Every action has a shortcut.

---

## Tokens (`Theme.swift`)

### Color
Pure black surface so the pill merges with the notch. Accent color is used sparingly, mostly as small dots and glows.

| Token | Value | Use |
|---|---|---|
| `surface` | `#000000` | Pill / panel background (must be pure black) |
| `surfaceRaised` | `white @ 6%` | Rows, secondary buttons |
| `surfaceHover` | `white @ 10%` | Hover on rows/buttons |
| `stroke` | `white @ 8%` | Hairline separators (0.5pt) |
| `textPrimary` | `white @ 95%` | Titles |
| `textSecondary` | `white @ 60%` | Body, project names |
| `textTertiary` | `white @ 38%` | Timestamps, hints |
| `accent` (Claude) | `#D97757` | Brand dot, working shimmer |
| `attention` | `#F5B544` | Question / waiting for input |
| `approval` | `#7AA2F7` | Permission request |
| `success` | `#4ADE80` | Done |
| `danger` | `#F87171` | Error, Deny button |

### Typography
SF Pro (system). SF Mono for commands/paths.

| Token | Font | Use |
|---|---|---|
| `title` | 13pt semibold | Event headline |
| `body` | 12pt regular | Message text |
| `caption` | 11pt medium | Project name, session label |
| `micro` | 10pt medium, tracking +0.2 | Timestamps, counts, kbd hints |
| `code` | SF Mono 11pt | Commands, file paths, tool input |

### Spacing (4pt grid)
`xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 24`

### Radius
| Token | Value | Use |
|---|---|---|
| `notchBottom` | 10 (collapsed) → 22 (expanded) | Bottom corners of the pill (top corners are always square/flush with bezel) |
| `row` | 10 | Session rows, code blocks |
| `button` | 8 | Buttons |
| `dot` | full | Status dots |

### Elevation
Only the expanded panel gets a shadow: `black @ 50%, radius 24, y 8`. Nothing else.

### Motion
| Token | Spec | Use |
|---|---|---|
| `springExpand` | `.spring(response: 0.42, dampingFraction: 0.78)` | Collapsed → expanded |
| `springCollapse` | `.spring(response: 0.32, dampingFraction: 0.9)` | Expanded → collapsed |
| `fast` | `.easeOut(0.15)` | Hover, button press |
| `pulse` | 1.6s ease-in-out, repeat | Attention dot breathing |
| `shimmer` | 2.0s linear, repeat | "Working" indicator |

Respect **Reduce Motion**: replace springs with 0.2s crossfade, disable pulse/shimmer.

---

## Layout states

The pill is anchored top-center, top edge flush with the screen top. Width/height are relative to the physical notch (`notchW`, `notchH`, read from `NSScreen.auxiliaryTopLeftArea/RightArea`). On non-notch displays, a 200×32 virtual notch is used.

| State | Size | Content |
|---|---|---|
| **Idle** | `notchW × notchH` | Nothing. Pure black. |
| **Glance** (live activity) | `notchW + 2×36 × notchH` | Left "ear": status dot / Claude glyph. Right "ear": count badge or elapsed time. Notch itself stays empty (camera). |
| **Peek** (new event, 4s) | `~420 × notchH + 64` | One-line headline + project; auto-collapses to Glance unless it's an approval/question. |
| **Expanded** | `~460 × auto (max 420)` | Full card for the active event + session list. |

### Ears (Glance)
- Left ear: 8pt status dot (color = highest-priority state across sessions). `working` shows the accent dot with shimmer.
- Right ear: `micro` text: pending count (`2`) or elapsed (`3m`), or ✓ for 2s after a completion.

---

## Components

### `NotchShape`
A custom `Shape`: flat top, vertical sides that curve outward at the top (the "inverse fillet" that makes it look like it melts into the bezel), and rounded bottom corners (`notchBottom`). The radius is animatable.

### `StatusDot`
| Variant | Color | Motion |
|---|---|---|
| working | accent | shimmer |
| question | attention | pulse |
| approval | approval | pulse |
| done | success | none |
| error | danger | none |
| idle | textTertiary | none |

### `EventCard`
Header: `StatusDot` · `title` · spacer · `micro` timestamp.
Sub-header: `caption` project name (last path component of `cwd`) · session short id.
Body: `body` message, max 3 lines; optional `CodeBlock`.
Footer: actions.

Variants:
- **Approval**: shows tool name ("Bash", "Edit") as title, `CodeBlock` with the command or file path, plus actions **Deny** (`⌘⌫`, ghost/danger), **Allow** (`⌘↩`, primary), and an overflow "Always allow" (`⌥⌘↩`).
- **Question**: shows the question, and options as stacked `OptionRow`s (1–4, number-key shortcuts). Free text falls back to "Open terminal".
- **Done**: success dot, "Finished" + last assistant summary line, and a **Jump to** action. Auto-dismisses after 6s.
- **Error**: danger dot, message, **Jump to**.

### `CodeBlock`
`surfaceRaised` background, `row` radius, `code` font, 2 lines collapsed with "Show more", horizontal scroll, and selectable text.

### `Button`
| Variant | Style |
|---|---|
| primary | white bg, black text, `button` radius, 28pt height |
| secondary | `surfaceRaised` bg, `textPrimary` |
| danger-ghost | transparent, `danger` text; on hover `danger @ 12%` bg |

States: hover (`fast` brighten), pressed (scale 0.97), disabled (40% opacity), and loading (inline spinner replaces label). Each button shows its keyboard hint in a `micro` `textTertiary` chip.

### `SessionRow`
`StatusDot` · project name (`caption`, `textPrimary`) · current activity (`micro`, `textSecondary`, e.g. "Running Bash · 2m") · trailing badge. Hover → `surfaceHover`. Click → focus that session's terminal.

### `Badge`
Capsule, `micro`, `surfaceRaised` bg; tinted (`approval @ 20%` bg + `approval` text) when an approval is pending.

---

## Behavior

- **Priority:** approval > question > error > done > working. The expanded card shows the highest-priority pending item, and the others queue (`1 of 3` pager, `←/→`).
- **Persistence:** approvals and questions stay until resolved (or until the hook times out, which shows "Answered in terminal" and fades). Done and error items fade after 6s and remain in history.
- **Hover** over the pill → Expanded. Mouse exit + 600ms grace → collapse (unless something is pending).
- **Click-through:** when Idle, the panel ignores mouse events outside the notch rect, so it never blocks the menu bar.
- **Fullscreen apps:** when the notch is hidden, show Peek as a floating pill instead.
- **Global shortcut** `⌃⌥C` toggles Expanded; while Expanded, `Esc` collapses.

## Copy tone
Short, verb-first, no exclamation marks. "Claude wants to run", "Waiting for you", "Finished", "Allowed", "Denied", "Answered in terminal".

## Accessibility
- Every control has an `accessibilityLabel` (e.g. "Allow Bash command in claude-notch").
- New approvals post an `NSAccessibility` announcement.
- Status color is never the only signal; titles always state the state.
- Contrast: all text ≥ 4.5:1 on black (the tokens above satisfy this).
