#!/usr/bin/env bash
# SessionStart hook: outputs wiki context to stdout for Claude's system prompt.
# Claude Code captures stdout and injects it as a system-reminder.

set -euo pipefail

CONFIG_FILE="${OBSIDIAN_WIKI_CONFIG:-$HOME/.obsidian-wiki/config}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "# Obsidian Wiki"
  echo ""
  echo "Wiki config not found at $CONFIG_FILE — wiki features disabled."
  exit 0
fi

# Parse config safely (values may contain spaces)
VAULT=$(grep '^OBSIDIAN_VAULT_PATH=' "$CONFIG_FILE" | cut -d= -f2- | sed 's/^["'"'"']//;s/["'"'"']$//')
if [[ -z "$VAULT" || ! -d "$VAULT" ]]; then
  echo "# Obsidian Wiki"
  echo ""
  echo "OBSIDIAN_VAULT_PATH not set or directory missing — wiki features disabled."
  exit 0
fi

# Read index summary (first 80 lines to keep context small)
INDEX_SNIPPET=""
if [[ -f "$VAULT/index.md" ]]; then
  INDEX_SNIPPET=$(head -80 "$VAULT/index.md")
fi

# Count pages
PAGE_COUNT=$(find "$VAULT" -name '*.md' -not -path '*/_raw/*' -not -name '.*' 2>/dev/null | wc -l | tr -d ' ')

cat <<CONTEXT
# Obsidian Wiki Available

You have access to an Obsidian wiki at: $VAULT
Total pages: $PAGE_COUNT

## How to use it

1. **Research topics**: Before answering questions about topics the wiki may cover, use the wiki-query skill (/wiki-query) or search the vault directly with Grep/Glob. The wiki contains pre-synthesized, cross-referenced knowledge that is often more relevant than your training data.

2. **Update the wiki**: When you learn new information during this session — new concepts, decisions, patterns, or insights — consider updating relevant wiki pages or creating new ones using the wiki-ingest workflow. The wiki grows through use.

3. **Cross-reference**: When discussing topics, link to relevant wiki pages using [[wikilinks]] notation so the user can explore further.

## Wiki Structure (from index.md)

$INDEX_SNIPPET

## Conversation History

All conversations are automatically saved to the wiki under \`journals/claude-history/\` when the session ends. This happens automatically — no action needed from you or the user.
CONTEXT
