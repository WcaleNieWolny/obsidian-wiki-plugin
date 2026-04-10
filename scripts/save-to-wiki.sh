#!/usr/bin/env bash
# Stop hook: saves the conversation transcript to the Obsidian wiki.
# Receives JSON on stdin with session_id, transcript_path, etc.

set -euo pipefail

CONFIG_FILE="${OBSIDIAN_WIKI_CONFIG:-$HOME/.obsidian-wiki/config}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi

# Parse config safely (values may contain spaces)
VAULT=$(grep '^OBSIDIAN_VAULT_PATH=' "$CONFIG_FILE" | cut -d= -f2- | sed 's/^["'"'"']//;s/["'"'"']$//')
if [[ -z "$VAULT" || ! -d "$VAULT" ]]; then
  exit 0
fi

# Read hook input from stdin
HOOK_INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null || true)
SESSION_ID=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)

if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# Create output directory
HISTORY_DIR="$VAULT/journals/claude-history"
mkdir -p "$HISTORY_DIR"

DATE=$(date '+%Y-%m-%d')
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')

# Generate the markdown file from the transcript JSONL
OUTPUT_FILE="$HISTORY_DIR/${DATE}-${SESSION_ID:0:12}.md"

python3 - "$TRANSCRIPT_PATH" "$OUTPUT_FILE" "$DATE" "$TIMESTAMP" "$SESSION_ID" << 'PYEOF'
import sys
import json
from pathlib import Path

transcript_path = sys.argv[1]
output_path = sys.argv[2]
date = sys.argv[3]
timestamp = sys.argv[4]
session_id = sys.argv[5]

messages = []
with open(transcript_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
            messages.append(msg)
        except json.JSONDecodeError:
            continue

if not messages:
    sys.exit(0)

# Extract a title from the first user message
title = date
for msg in messages:
    if msg.get('type') == 'user':
        content = msg.get('content', '')
        if isinstance(content, list):
            # content can be a list of content blocks
            for block in content:
                if isinstance(block, dict) and block.get('type') == 'text':
                    content = block.get('text', '')
                    break
                elif isinstance(block, str):
                    content = block
                    break
            else:
                content = ''
        if isinstance(content, str) and content.strip():
            # Take first line, truncate to 80 chars
            first_line = content.strip().split('\n')[0][:80]
            # Strip markdown/special chars
            first_line = first_line.lstrip('#- ').strip()
            if first_line:
                title = first_line
        break

# Build markdown
lines = []
lines.append('---')
lines.append(f'title: "{title}"')
lines.append(f'date: {date}')
lines.append(f'session_id: {session_id}')
lines.append(f'created: {timestamp}')
lines.append('category: claude-history')
lines.append('tags: [claude, conversation, history]')
lines.append('---')
lines.append('')
lines.append(f'# {title}')
lines.append('')

for msg in messages:
    msg_type = msg.get('type', 'unknown')
    ts = msg.get('timestamp', '')

    content = msg.get('content', '')
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict):
                if block.get('type') == 'text':
                    parts.append(block.get('text', ''))
                elif block.get('type') == 'tool_use':
                    tool = block.get('name', 'unknown')
                    parts.append(f'*[Tool: {tool}]*')
                elif block.get('type') == 'tool_result':
                    parts.append('*[Tool result]*')
            elif isinstance(block, str):
                parts.append(block)
        content = '\n'.join(parts)

    if not isinstance(content, str):
        content = str(content) if content else ''

    if not content.strip():
        continue

    if msg_type == 'user':
        lines.append(f'## User ({ts})')
        lines.append('')
        lines.append(content.strip())
        lines.append('')
    elif msg_type == 'assistant':
        lines.append(f'## Assistant ({ts})')
        lines.append('')
        lines.append(content.strip())
        lines.append('')

Path(output_path).write_text('\n'.join(lines), encoding='utf-8')
PYEOF
