#!/usr/bin/env bash
# Rebuild and relaunch Claude Notch for development.
set -euo pipefail

cd "$(dirname "$0")/.."

pkill -x ClaudeNotch 2>/dev/null || true
sleep 0.3

./scripts/build-app.sh
open "build/Claude Notch.app"
