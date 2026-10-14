#!/usr/bin/env bash
# Send a realistic hook event to a running Claude Notch.
# Usage: scripts/send-test-event.sh permission|question|stop|notify|idle [port]
set -euo pipefail

KIND="${1:-}"
PORT="${2:-41817}"

if [[ -z "$KIND" ]]; then
  echo "Usage: $0 permission|question|stop|notify|idle [port]" >&2
  exit 2
fi

TOKEN="$(defaults read dev.claudenotch.ClaudeNotch authToken 2>/dev/null || true)"
if [[ -z "$TOKEN" ]]; then
  echo "error: no auth token found. Launch Claude Notch once first." >&2
  exit 1
fi

SESSION_ID="test-$(date +%s | tail -c 7)abcdef"
CWD="$HOME/projects/demo-app"
TRANSCRIPT="$HOME/.claude/projects/demo/$SESSION_ID.jsonl"
ENDPOINT="event"
BODY=""

case "$KIND" in
  permission)
    ENDPOINT="hook"
    BODY=$(cat <<JSON
{
  "session_id": "$SESSION_ID",
  "transcript_path": "$TRANSCRIPT",
  "cwd": "$CWD",
  "permission_mode": "default",
  "hook_event_name": "PermissionRequest",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test -- --coverage",
    "description": "Run the test suite with coverage"
  },
  "permission_suggestions": [
    {
      "type": "addRules",
      "rules": [ { "toolName": "Bash", "ruleContent": "npm test:*" } ],
      "behavior": "allow",
      "destination": "localSettings"
    }
  ]
}
JSON
)
    ;;
  question)
    ENDPOINT="hook"
    BODY=$(cat <<JSON
{
  "session_id": "$SESSION_ID",
  "transcript_path": "$TRANSCRIPT",
  "cwd": "$CWD",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "AskUserQuestion",
  "tool_use_id": "toolu_test_$SESSION_ID",
  "tool_input": {
    "questions": [
      {
        "question": "Which test framework should I use?",
        "header": "Framework",
        "multiSelect": false,
        "options": [
          { "label": "Vitest", "description": "Fast, Vite-native runner" },
          { "label": "Jest", "description": "Widely used, larger ecosystem" }
        ]
      }
    ]
  }
}
JSON
)
    ;;
  stop)
    BODY=$(cat <<JSON
{
  "session_id": "$SESSION_ID",
  "transcript_path": "$TRANSCRIPT",
  "cwd": "$CWD",
  "permission_mode": "default",
  "hook_event_name": "Stop",
  "stop_hook_active": false,
  "last_assistant_message": "All 42 tests pass. I also fixed the flaky timeout in the auth suite."
}
JSON
)
    ;;
  notify)
    BODY=$(cat <<JSON
{
  "session_id": "$SESSION_ID",
  "transcript_path": "$TRANSCRIPT",
  "cwd": "$CWD",
  "hook_event_name": "Notification",
  "notification_type": "permission_prompt",
  "message": "Claude needs your permission to use Bash"
}
JSON
)
    ;;
  idle)
    BODY=$(cat <<JSON
{
  "session_id": "$SESSION_ID",
  "transcript_path": "$TRANSCRIPT",
  "cwd": "$CWD",
  "hook_event_name": "Notification",
  "notification_type": "idle_prompt",
  "message": "Claude is waiting for your input"
}
JSON
)
    ;;
  *)
    echo "Unknown kind: $KIND (use permission|question|stop|notify|idle)" >&2
    exit 2 ;;
esac

URL="http://127.0.0.1:$PORT/claude-notch/v1/$ENDPOINT"
echo "POST $URL ($KIND, session $SESSION_ID)"
if [[ "$ENDPOINT" == "hook" ]]; then
  echo "Held until you act in the notch (or the hold timeout expires)..."
fi

RESPONSE=$(curl -sS -m 130 -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Claude-Notch-Token: $TOKEN" \
  -H "X-Claude-Notch-Term: Apple_Terminal" \
  -H "X-Claude-Notch-Bundle: com.apple.Terminal" \
  --data "$BODY")
echo "Response: $RESPONSE"
