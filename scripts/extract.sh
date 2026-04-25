#!/bin/zsh
# ============================================================================
# extract.sh — 특정 채팅방의 메시지를 JSON으로 추출
# ============================================================================
# Usage:
#   ./extract.sh <chat_id>                  # 어제 24시간치, 기본 5000개
#   ./extract.sh <chat_id> 7d               # 최근 7일
#   ./extract.sh <chat_id> 24h /tmp/out.json # 출력 파일 지정
# ============================================================================

set -euo pipefail

# Load config
if [[ -f "$HOME/.kakaocli-config" ]]; then
  source "$HOME/.kakaocli-config"
else
  echo "✗ ~/.kakaocli-config not found. Run install.sh first." >&2
  exit 1
fi

# Validate env
: "${KAKAOCLI_BIN:?KAKAOCLI_BIN not set}"
: "${KAKAOCLI_DB:?KAKAOCLI_DB not set}"
: "${KAKAOCLI_KEY:?KAKAOCLI_KEY not set}"

# Args
CHAT_ID="${1:?Usage: extract.sh <chat_id> [since=24h] [output_file]}"
SINCE="${2:-24h}"
OUTPUT="${3:-/tmp/kakao-${CHAT_ID}-$(date +%Y-%m-%d).json}"

# Run
"$KAKAOCLI_BIN" messages \
  --chat-id "$CHAT_ID" \
  --since "$SINCE" \
  --limit 5000 \
  --json \
  --db "$KAKAOCLI_DB" \
  --key "$KAKAOCLI_KEY" \
  > "$OUTPUT"

# Report
COUNT=$(python3 -c "import json; print(len(json.load(open('$OUTPUT'))))")
echo "✓ Extracted $COUNT messages → $OUTPUT"
