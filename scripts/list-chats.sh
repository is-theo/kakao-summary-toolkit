#!/bin/zsh
# ============================================================================
# list-chats.sh — 채팅방 목록을 진짜 이름과 함께 표시
# ============================================================================
# kakaocli chats 명령은 group chat 이름을 (unknown)으로 표시함.
# 이 스크립트는 NTChatRoom + NTOpenLink JOIN으로 진짜 이름을 가져옴.
# ============================================================================

set -euo pipefail

if [[ -f "$HOME/.kakaocli-config" ]]; then
  source "$HOME/.kakaocli-config"
else
  echo "✗ ~/.kakaocli-config not found. Run install.sh first." >&2
  exit 1
fi

LIMIT="${1:-20}"

"$KAKAOCLI_BIN" query \
  "SELECT cr.chatId,
          COALESCE(NULLIF(cr.chatName, ''), NULLIF(ol.linkName, ''), '(이름 없음)') AS displayName,
          cr.activeMembersCount,
          cr.countOfNewMessage,
          cr.lastUpdatedAt
   FROM NTChatRoom cr
   LEFT JOIN NTOpenLink ol ON cr.linkId = ol.linkId
   ORDER BY cr.lastUpdatedAt DESC
   LIMIT $LIMIT" \
  --db "$KAKAOCLI_DB" \
  --key "$KAKAOCLI_KEY" | python3 -c "
import json
import sys
from datetime import datetime, timezone, timedelta

KST = timezone(timedelta(hours=9))
rows = json.load(sys.stdin)
print(f'{\"ID\":<22} {\"이름\":<40} {\"멤버\":>6} {\"안읽음\":>7}  최근(KST)')
print('-' * 100)
for row in rows:
    chat_id, name, members, unread, last_at = row
    name = (name or '(이름 없음)')[:38]
    if last_at:
        try:
            dt = datetime.fromtimestamp(last_at, tz=KST).strftime('%m-%d %H:%M')
        except (OSError, ValueError, OverflowError):
            dt = str(last_at)[:10]
    else:
        dt = '?'
    print(f'{chat_id:<22} {name:<40} {members:>6,} {unread:>7,}  {dt}')
"
