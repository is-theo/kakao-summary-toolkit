#!/bin/zsh
# ============================================================================
# send-to-webhook.sh v1.2 — 어제 자연일 카톡 메시지를 n8n webhook으로 POST
# ============================================================================
# 시간 정책: KST 단일 진실 + 어제 자연일 윈도우
# - window: 어제 00:00 ~ 오늘 00:00 KST (자연일 24시간)
# - kakaocli는 48h 가져온 후 Python에서 윈도우로 필터
# - messages[].timestamp: KST (+09:00 명시)
#
# Usage:
#   send-to-webhook.sh <chat_id>                  # 어제 자연일 (default)
#   send-to-webhook.sh <chat_id> 7d               # 최근 7일 (필터 없이 그대로)
#   send-to-webhook.sh <chat_id> 24h /tmp/x.json  # 어제 자연일 + 파일 저장
#
# Required environment variables (in ~/.kakaocli-config):
#   KAKAOCLI_BIN, KAKAOCLI_DB, KAKAOCLI_KEY, KAKAOCLI_WEBHOOK_URL
# ============================================================================

set -euo pipefail

# Load config
if [[ -f "$HOME/.kakaocli-config" ]]; then
  source "$HOME/.kakaocli-config"
else
  echo "✗ ~/.kakaocli-config not found. Run install.sh first." >&2
  exit 1
fi

# Validate required env
: "${KAKAOCLI_BIN:?KAKAOCLI_BIN not set}"
: "${KAKAOCLI_DB:?KAKAOCLI_DB not set}"
: "${KAKAOCLI_KEY:?KAKAOCLI_KEY not set}"
: "${KAKAOCLI_WEBHOOK_URL:?KAKAOCLI_WEBHOOK_URL not set — add to ~/.kakaocli-config: export KAKAOCLI_WEBHOOK_URL=\"https://...\"}"

# Args
CHAT_ID="${1:?Usage: send-to-webhook.sh <chat_id> [since=24h] [save_to_file]}"
SINCE="${2:-24h}"
SAVE_TO="${3:-}"

# Decide kakaocli fetch window:
#   24h (default) → fetch 48h, filter to yesterday natural day
#   others (7d etc) → fetch as-is, no filter
KCLI_SINCE="$SINCE"
NATURAL_DAY=false
if [[ "$SINCE" == "24h" ]]; then
  KCLI_SINCE="48h"
  NATURAL_DAY=true
fi

# ============================================================================
# Step 1: Get chat metadata (name, members, type)
# ============================================================================

CHAT_META_JSON=$("$KAKAOCLI_BIN" query \
  "SELECT cr.chatId,
          COALESCE(NULLIF(cr.chatName, ''), NULLIF(ol.linkName, ''), '(이름 없음)') AS name,
          cr.activeMembersCount,
          cr.type,
          cr.linkId
   FROM NTChatRoom cr
   LEFT JOIN NTOpenLink ol ON cr.linkId = ol.linkId
   WHERE cr.chatId = $CHAT_ID
   LIMIT 1" \
  --db "$KAKAOCLI_DB" --key "$KAKAOCLI_KEY")

CHAT_META=$(echo "$CHAT_META_JSON" | python3 -c "
import json, sys
rows = json.load(sys.stdin, strict=False)
if not rows:
    print('NOT_FOUND', file=sys.stderr)
    sys.exit(1)
row = rows[0]
chat_id, name, members, type_, link_id = row
chat_type = 'openchat' if link_id and link_id != 0 else 'group'
print(json.dumps({
    'id': chat_id,
    'name': name,
    'member_count': members,
    'type': chat_type
}, ensure_ascii=False))
")

if [[ -z "$CHAT_META" ]]; then
  echo "✗ Chat ID $CHAT_ID not found" >&2
  exit 1
fi

CHAT_NAME=$(echo "$CHAT_META" | python3 -c "import json,sys; print(json.load(sys.stdin, strict=False)['name'])")
echo "▶ Chat: $CHAT_NAME (ID: $CHAT_ID)"

# ============================================================================
# Step 2: Extract messages (kakaocli 넉넉하게)
# ============================================================================

if $NATURAL_DAY; then
  echo "▶ Extracting messages (mode: 어제 자연일, kakaocli fetch: $KCLI_SINCE)..."
else
  echo "▶ Extracting messages (since: $KCLI_SINCE)..."
fi

MESSAGES_JSON=$("$KAKAOCLI_BIN" messages \
  --chat-id "$CHAT_ID" \
  --since "$KCLI_SINCE" \
  --limit 5000 \
  --json \
  --db "$KAKAOCLI_DB" \
  --key "$KAKAOCLI_KEY")

RAW_COUNT=$(echo "$MESSAGES_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin, strict=False)))")
echo "  → $RAW_COUNT raw messages fetched"

# ============================================================================
# Step 3: Build payload (KST + natural day window filter)
# ============================================================================

NOW_KST=$(date '+%Y-%m-%dT%H:%M:%S+09:00')

if $NATURAL_DAY; then
  # 어제 자연일: 어제 00:00 ~ 오늘 00:00 KST
  WINDOW_START=$(date -v-1d '+%Y-%m-%dT00:00:00+09:00')
  WINDOW_END=$(date '+%Y-%m-%dT00:00:00+09:00')
else
  # 7d 등: 지금 - SINCE 만큼
  # (간단히 지금 시각 기준으로 끝점 표시, 시작점은 24h라면 위, 다른 거면 -SINCE)
  WINDOW_START=$(date -v-${SINCE} '+%Y-%m-%dT%H:%M:%S+09:00' 2>/dev/null || date -v-7d '+%Y-%m-%dT%H:%M:%S+09:00')
  WINDOW_END="$NOW_KST"
fi

export PY_CHAT_META="$CHAT_META"
export PY_MESSAGES="$MESSAGES_JSON"
export PY_NOW_KST="$NOW_KST"
export PY_WINDOW_START="$WINDOW_START"
export PY_WINDOW_END="$WINDOW_END"
export PY_SINCE_LABEL="$SINCE"
export PY_NATURAL_DAY=$($NATURAL_DAY && echo "1" || echo "0")

PAYLOAD_FILE=$(mktemp -t kakao-payload.XXXXXX.json)
trap 'rm -f "$PAYLOAD_FILE"' EXIT

python3 <<'PYEOF' > "$PAYLOAD_FILE"
import json
import os
import sys
from datetime import datetime, timezone, timedelta

KST = timezone(timedelta(hours=9))

def to_kst(ts_str):
    """원본 timestamp → KST ISO8601 (+09:00)"""
    if not ts_str:
        return ts_str
    s = ts_str.replace('Z', '+00:00')
    try:
        dt = datetime.fromisoformat(s)
    except (ValueError, TypeError):
        return ts_str
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(KST).strftime('%Y-%m-%dT%H:%M:%S+09:00')

def parse_iso(s):
    return datetime.fromisoformat(s.replace('Z', '+00:00'))

chat_meta = json.loads(os.environ['PY_CHAT_META'], strict=False)
messages = json.loads(os.environ['PY_MESSAGES'], strict=False)
natural_day = os.environ['PY_NATURAL_DAY'] == "1"

# 1) 모든 메시지 timestamp → KST 변환
for m in messages:
    if 'timestamp' in m:
        m['timestamp'] = to_kst(m['timestamp'])

# 2) 자연일 모드면 윈도우로 필터링
if natural_day:
    win_start = parse_iso(os.environ['PY_WINDOW_START'])
    win_end = parse_iso(os.environ['PY_WINDOW_END'])
    
    filtered = []
    for m in messages:
        ts = m.get('timestamp', '')
        if not ts:
            continue
        try:
            dt = parse_iso(ts)
        except (ValueError, TypeError):
            continue
        if win_start <= dt < win_end:
            filtered.append(m)
    
    print(f"  → filtered to {len(filtered)} messages in window {win_start.date()} ~ {win_end.date()}", file=sys.stderr)
    messages = filtered

# 3) 빈 결과 처리
if not messages:
    print("⚠ No messages in this window after filtering.", file=sys.stderr)
    # 빈 페이로드라도 보내야 (n8n 워크플로우가 동작 자체는 시도)
    pass

# 4) Active speaker count
speakers = set()
for m in messages:
    if not m.get('is_from_me'):
        speakers.add(m.get('sender_id'))
    else:
        speakers.add('me')

payload = {
    "meta": {
        "version": "1.2",
        "sent_at": os.environ['PY_NOW_KST'],
        "source": "mac-kakaocli",
        "timezone": "Asia/Seoul",
        "window_mode": "natural_day" if natural_day else "rolling",
        "_note": "All timestamps are KST (+09:00). No UTC fields.",
    },
    "chat": chat_meta,
    "window": {
        "since_label": os.environ['PY_SINCE_LABEL'],
        "since": os.environ['PY_WINDOW_START'],
        "until": os.environ['PY_WINDOW_END'],
    },
    "stats": {
        "message_count": len(messages),
        "active_speakers": len(speakers),
    },
    "messages": messages,
}
print(json.dumps(payload, ensure_ascii=False))
PYEOF

# Show stats
FINAL_COUNT=$(python3 -c "import json; print(json.load(open('$PAYLOAD_FILE'))['stats']['message_count'])")
echo "  → $FINAL_COUNT messages in final payload"

if [[ "$FINAL_COUNT" -eq 0 ]]; then
  echo "⚠ No messages after filtering. Aborting."
  exit 0
fi

if [[ -n "$SAVE_TO" ]]; then
  cp "$PAYLOAD_FILE" "$SAVE_TO"
  echo "  → Saved payload to $SAVE_TO ($(wc -c < "$SAVE_TO") bytes)"
fi

# ============================================================================
# Step 4: POST to webhook
# ============================================================================

echo "▶ Sending to webhook..."
echo "  → URL: $KAKAOCLI_WEBHOOK_URL"

HTTP_CODE=$(curl \
  -X POST \
  -H "Content-Type: application/json" \
  -H "User-Agent: kakao-summary-toolkit/1.2" \
  --data-binary "@$PAYLOAD_FILE" \
  --silent \
  --output /tmp/kakao-webhook-response.txt \
  --write-out "%{http_code}" \
  "$KAKAOCLI_WEBHOOK_URL" || echo "000")

if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "201" ]] || [[ "$HTTP_CODE" == "204" ]]; then
  echo "✓ Sent successfully (HTTP $HTTP_CODE)"
  if [[ -s /tmp/kakao-webhook-response.txt ]]; then
    echo "  Response:"
    head -c 500 /tmp/kakao-webhook-response.txt | sed 's/^/    /'
    echo ""
  fi
else
  echo "✗ Send failed (HTTP $HTTP_CODE)" >&2
  if [[ -s /tmp/kakao-webhook-response.txt ]]; then
    echo "  Response:"
    head -c 500 /tmp/kakao-webhook-response.txt | sed 's/^/    /' >&2
    echo "" >&2
  fi
  exit 1
fi
