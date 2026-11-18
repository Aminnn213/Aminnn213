#!/usr/bin/env bash
# Install Earshot on macOS and register it as a user-scoped MCP server in Claude Code.
set -euo pipefail

# 1. Prerequisites: uv, ffmpeg, ffprobe
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install it from https://brew.sh and re-run." >&2
  exit 1
fi
command -v uv >/dev/null 2>&1 || brew install uv
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  brew install ffmpeg   # provides both ffmpeg and ffprobe
fi
uv tool update-shell >/dev/null 2>&1 || true
export PATH="$HOME/.local/bin:$PATH"

# 2. Install Earshot
uv tool install --force "earshot[mcp] @ git+https://github.com/Leonxlnx/earshot"

# 3. Download models and check the install
earshot doctor --fetch

# 4. Register with Claude Code (available in all projects)
claude mcp remove earshot --scope user >/dev/null 2>&1 || true
claude mcp add earshot --scope user -e EARSHOT_THREADS=3 -- earshot mcp

# 5. Verify
claude mcp list
say -o /tmp/earshot-test.aiff "Hello, this is an Earshot test." 2>/dev/null \
  && ffmpeg -y -loglevel error -i /tmp/earshot-test.aiff /tmp/earshot-test.wav \
  && echo "Test audio: /tmp/earshot-test.wav (run: earshot --help to see how to transcribe it)"
echo "Done."
