#!/bin/zsh
# ============================================================================
# send-to-webhook.sh — 어제 24시간치 카톡 메시지를 n8n webhook으로 POST
# ============================================================================
# Usage:
#   send-to-webhook.sh <chat_id>                  # 어제 24시간 (default)
#   send-to-webhook.sh <chat_id> 7d               # 최근 7일
#   send-to-webhook.sh <chat_id> 24h /tmp/x.json  # JSON 파일도 함께 저장
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
SAVE_TO="${3:-}"  # Optional — also save payload to this path

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

# Extract fields with python (jq might not be installed)
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

CHAT_NAME=$(echo "$CHAT_META" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
echo "▶ Chat: $CHAT_NAME (ID: $CHAT_ID)"

# ============================================================================
# Step 2: Extract messages
# ============================================================================

echo "▶ Extracting messages (since: $SINCE)..."
MESSAGES_JSON=$("$KAKAOCLI_BIN" messages \
  --chat-id "$CHAT_ID" \
  --since "$SINCE" \
  --limit 5000 \
  --json \
  --db "$KAKAOCLI_DB" \
  --key "$KAKAOCLI_KEY")

MESSAGE_COUNT=$(echo "$MESSAGES_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin, strict=False)))")
echo "  → $MESSAGE_COUNT messages"

if [[ "$MESSAGE_COUNT" -eq 0 ]]; then
  echo "⚠ No messages in this window. Aborting."
  exit 0
fi

# ============================================================================
# Step 3: Build payload (combine metadata + messages)
# ============================================================================

# Compute window timestamps (KST, macOS date syntax)
NOW_KST=$(date '+%Y-%m-%dT%H:%M:%S+09:00')
WINDOW_END=$(date -v-1d '+%Y-%m-%dT23:59:59+09:00')
WINDOW_START=$(date -v-1d '+%Y-%m-%dT00:00:00+09:00')

# Pass everything to Python via env vars (avoids JSON parsing issues with shell)
export PY_CHAT_META="$CHAT_META"
export PY_MESSAGES="$MESSAGES_JSON"
export PY_NOW_KST="$NOW_KST"
export PY_WINDOW_START="$WINDOW_START"
export PY_WINDOW_END="$WINDOW_END"
export PY_SINCE_LABEL="$SINCE"

# Write payload directly to temp file from Python (avoids shell variable corruption)
PAYLOAD_FILE=$(mktemp -t kakao-payload.XXXXXX.json)
trap 'rm -f "$PAYLOAD_FILE"' EXIT

python3 <<PYEOF > "$PAYLOAD_FILE"
import json
import os

chat_meta = json.loads(os.environ['PY_CHAT_META'], strict=False)
messages = json.loads(os.environ['PY_MESSAGES'], strict=False)

# Compute active speaker count
speakers = set()
for m in messages:
    if not m.get('is_from_me'):
        speakers.add(m.get('sender_id'))
    else:
        speakers.add('me')

payload = {
    "meta": {
        "version": "1.0",
        "sent_at": os.environ['PY_NOW_KST'],
        "source": "mac-kakaocli",
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

# Optionally save a copy of payload (for debugging)
if [[ -n "$SAVE_TO" ]]; then
  cp "$PAYLOAD_FILE" "$SAVE_TO"
  echo "  → Saved payload to $SAVE_TO ($(wc -c < "$SAVE_TO") bytes)"
fi

# ============================================================================
# Step 4: POST to webhook
# ============================================================================

echo "▶ Sending to webhook..."
echo "  → URL: $KAKAOCLI_WEBHOOK_URL"

# Send file directly (bypasses any shell variable corruption)
HTTP_CODE=$(curl \
  -X POST \
  -H "Content-Type: application/json" \
  -H "User-Agent: kakao-summary-toolkit/1.0" \
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
