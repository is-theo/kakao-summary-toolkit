#!/bin/zsh
# ============================================================================
# list-chats.sh — 채팅방 목록 보기 (chat_id 찾을 때)
# ============================================================================

set -euo pipefail

if [[ -f "$HOME/.kakaocli-config" ]]; then
  source "$HOME/.kakaocli-config"
else
  echo "✗ ~/.kakaocli-config not found. Run install.sh first." >&2
  exit 1
fi

LIMIT="${1:-20}"

"$KAKAOCLI_BIN" chats \
  --db "$KAKAOCLI_DB" \
  --key "$KAKAOCLI_KEY" \
  --limit "$LIMIT" \
  --json | python3 -c "
import json, sys
chats = json.load(sys.stdin)
print(f'{\"ID\":<22} {\"Name\":<35} {\"Members\":>8} {\"Unread\":>8} Last')
print('-' * 100)
for c in chats:
    name = c.get('display_name', '(unknown)')[:34]
    members = c.get('member_count', 0)
    unread = c.get('unread_count', 0)
    last = c.get('last_message_at', '')[:10]
    print(f'{c[\"id\"]:<22} {name:<35} {members:>8,} {unread:>8,} {last}')
"
