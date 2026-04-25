#!/bin/bash
# ============================================================================
# Kakao Summary Toolkit — One-Stop Installer
# ============================================================================
# Usage: curl -fsSL https://raw.githubusercontent.com/is-theo/kakao-summary-toolkit/main/install.sh | bash
#
# What this does:
# 1. Downloads patched kakaocli binary to ~/Applications/kakaocli/
# 2. Guides you through Full Disk Access permission
# 3. Auto-discovers your KakaoTalk User ID
# 4. Saves your User ID + DB path + Key to ~/.kakaocli-config
# 5. Tests by listing your top 5 chats
# ============================================================================

set -e  # Exit on any error

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'  # No color

# Config
REPO_USER="is-theo"
REPO_NAME="kakao-summary-toolkit"
INSTALL_DIR="$HOME/Applications/kakaocli"
CONFIG_FILE="$HOME/.kakaocli-config"
BINARY_URL="https://github.com/${REPO_USER}/${REPO_NAME}/raw/main/bin/kakaocli"

# ============================================================================
# Helper functions
# ============================================================================

print_step() {
  printf "\n${BOLD}${BLUE}▶ %s${NC}\n" "$1"
}

print_success() {
  printf "${GREEN}✓ %s${NC}\n" "$1"
}

print_warn() {
  printf "${YELLOW}⚠ %s${NC}\n" "$1"
}

print_error() {
  printf "${RED}✗ %s${NC}\n" "$1"
}

print_info() {
  printf "  %s\n" "$1"
}

press_enter() {
  printf "\n${BOLD}계속하려면 Enter 키를 누르세요...${NC}\n"
  read -r _ < /dev/tty
}

# ============================================================================
# Pre-flight checks
# ============================================================================

print_step "환경 확인"

# macOS check
if [[ "$(uname)" != "Darwin" ]]; then
  print_error "이 스크립트는 macOS 전용입니다."
  exit 1
fi
print_success "macOS 확인됨"

# Apple Silicon check (warn but don't fail)
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
  print_warn "Intel Mac이 감지되었습니다 (테스트는 Apple Silicon에서만 됨)"
else
  print_success "Apple Silicon 확인됨"
fi

# KakaoTalk app check
if [[ ! -d "/Applications/KakaoTalk.app" ]]; then
  print_error "카카오톡 앱이 설치되어 있지 않습니다."
  print_info "App Store에서 카카오톡을 설치한 뒤 로그인하고 다시 실행하세요."
  exit 1
fi
print_success "카카오톡 앱 확인됨"

# KakaoTalk container check (means user has logged in at least once)
KAKAO_CONTAINER="$HOME/Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Application Support/com.kakao.KakaoTalkMac"
if [[ ! -d "$KAKAO_CONTAINER" ]]; then
  print_error "카카오톡에 로그인한 적이 없습니다."
  print_info "카카오톡 앱을 켜서 로그인을 완료한 뒤 다시 실행하세요."
  exit 1
fi
print_success "카카오톡 로그인 데이터 확인됨"

# sqlcipher check
if ! command -v sqlcipher &> /dev/null; then
  print_warn "sqlcipher가 설치되어 있지 않습니다."

  if ! command -v brew &> /dev/null; then
    print_error "Homebrew도 없습니다. https://brew.sh 에서 먼저 설치하세요."
    exit 1
  fi

  print_info "Homebrew로 sqlcipher 설치 중..."
  brew install sqlcipher
fi
print_success "sqlcipher 확인됨"

# ============================================================================
# Step 1: Download binary
# ============================================================================

print_step "kakaocli 바이너리 다운로드"

mkdir -p "$INSTALL_DIR"
BINARY_PATH="$INSTALL_DIR/kakaocli"

if [[ -f "$BINARY_PATH" ]]; then
  print_info "기존 바이너리 발견 — 덮어쓰기"
fi

curl -fsSL "$BINARY_URL" -o "$BINARY_PATH"
chmod +x "$BINARY_PATH"

# Remove macOS Gatekeeper quarantine attribute (downloads from internet are quarantined)
xattr -d com.apple.quarantine "$BINARY_PATH" 2>/dev/null || true

# Verify it runs
if ! "$BINARY_PATH" --version &> /dev/null; then
  print_error "바이너리가 동작하지 않습니다. macOS 보안 설정 확인 필요."
  print_info "수동으로 한 번 실행해보세요: $BINARY_PATH --version"
  print_info "'개발자 미확인' 경고 뜨면: 시스템 설정 > 개인정보 보호 및 보안 > '확인 없이 열기' 클릭"
  exit 1
fi

VERSION=$("$BINARY_PATH" --version)
print_success "kakaocli $VERSION 설치됨 → $BINARY_PATH"

# ============================================================================
# Step 2: Full Disk Access guidance
# ============================================================================

print_step "Full Disk Access 권한 부여"

# Check if we already have access by trying to read the container
TEST_FILE=$(ls "$KAKAO_CONTAINER" 2>/dev/null | head -1)

if [[ -n "$TEST_FILE" ]]; then
  print_success "Full Disk Access 이미 부여됨"
else
  print_warn "이 터미널 앱에 Full Disk Access 권한이 필요합니다."
  echo ""
  print_info "1. 시스템 설정이 자동으로 열립니다"
  print_info "2. 사용 중인 터미널 앱(Terminal/iTerm2/Warp 등)을 추가하고 토글을 켜세요"
  print_info "3. ⚠️  권한 부여 후 ${BOLD}터미널 앱을 완전히 종료(Cmd+Q) 후 재실행${NC}하세요"
  print_info "4. 재실행 후 이 스크립트를 다시 한 번 실행하세요"
  echo ""

  # Open System Settings to Full Disk Access pane
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

  press_enter
  echo ""
  print_warn "권한 부여 완료했으면 터미널 재시작 후 이 스크립트 다시 실행하세요"
  print_info "한 번 실행: curl -fsSL https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/main/install.sh | bash"
  exit 0
fi

# ============================================================================
# Step 3: Discover User ID
# ============================================================================

print_step "카카오톡 User ID 자동 탐색"

# Get UUID for key derivation
DEVICE_UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | grep IOPlatformUUID | awk -F'"' '{print $4}')

if [[ -z "$DEVICE_UUID" ]]; then
  print_error "Device UUID를 가져올 수 없습니다."
  exit 1
fi

# Find the DB file
# KakaoTalk's DB filename is a long hex hash. Different versions/accounts
# produce different lengths, so don't rely on exact length — find the largest
# hex-named file in the container directory.
DB_FILE=$(ls -1S "$KAKAO_CONTAINER" 2>/dev/null | grep -E '^[a-f0-9]+$' | head -1)

if [[ -z "$DB_FILE" ]]; then
  print_error "카카오톡 DB 파일을 찾을 수 없습니다."
  print_info "디버깅: 컨테이너 폴더 내용:"
  ls -la "$KAKAO_CONTAINER" 2>&1 | head -20
  print_info ""
  print_info "카카오톡 앱이 켜진 적이 있는지 확인하세요."
  print_info "카카오톡을 실행해서 채팅방을 한 번 열어본 뒤 다시 시도하세요."
  exit 1
fi

DB_PATH="$KAKAO_CONTAINER/$DB_FILE"
print_info "DB 파일 발견: ${DB_FILE:0:24}..."

# Try candidate User IDs from plist
print_info "plist의 후보 ID 시도 중..."
CANDIDATES=$(defaults read com.kakao.KakaoTalkMac AlertKakaoIDsList 2>/dev/null | grep -oE '[0-9]{7,}' | sort -u || true)

USER_ID=""
SECURE_KEY=""

if [[ -n "$CANDIDATES" ]]; then
  for candidate in $(echo "$CANDIDATES"); do
    AUTH_OUTPUT=$("$BINARY_PATH" auth --user-id "$candidate" --verbose 2>&1 || true)
    if echo "$AUTH_OUTPUT" | grep -q "Database opened successfully"; then
      USER_ID="$candidate"
      SECURE_KEY=$(echo "$AUTH_OUTPUT" | grep "Secure key:" | awk '{print $3}')
      print_success "후보 ID로 자동 발견됨: $USER_ID"
      break
    fi
  done
fi

# If candidates failed, try OpenKakao auto-extraction
if [[ -z "$USER_ID" ]]; then
  echo ""
  print_info "후보 ID 모두 실패 — OpenKakao 도구로 자동 추출 시도..."

  # Step A: Check if OpenKakao stored credentials already exist
  OPENKAKAO_CREDS="$HOME/.config/openkakao/credentials.json"

  if [[ -f "$OPENKAKAO_CREDS" ]]; then
    print_info "기존 OpenKakao 자격증명 발견"
    EXTRACTED_ID=$(grep -oE '"user_id"[[:space:]]*:[[:space:]]*[0-9]+' "$OPENKAKAO_CREDS" | grep -oE '[0-9]+' | head -1)
    if [[ -n "$EXTRACTED_ID" ]]; then
      print_info "추출된 User ID: $EXTRACTED_ID — 검증 중..."
      AUTH_OUTPUT=$("$BINARY_PATH" auth --user-id "$EXTRACTED_ID" --verbose 2>&1)
      if echo "$AUTH_OUTPUT" | grep -q "Database opened successfully"; then
        USER_ID="$EXTRACTED_ID"
        SECURE_KEY=$(echo "$AUTH_OUTPUT" | grep "Secure key:" | awk '{print $3}')
        print_success "OpenKakao 자격증명에서 자동 발견됨: $USER_ID"
      fi
    fi
  fi

  # Step B: Install OpenKakao + run login --save if still no User ID
  if [[ -z "$USER_ID" ]]; then
    if ! command -v openkakao-cli &> /dev/null; then
      print_info "OpenKakao 설치 중... (약 30초)"
      brew tap JungHoonGhae/openkakao 2>&1 | tail -3
      brew install openkakao-cli 2>&1 | tail -3
    fi

    if command -v openkakao-cli &> /dev/null; then
      print_info "OpenKakao login --save 실행 중..."
      # Run with stdin from /dev/tty in case it asks for password
      LOGIN_OUTPUT=$(openkakao-cli login --save < /dev/tty 2>&1 || true)

      # Extract User ID from output: "User ID: 42680568"
      EXTRACTED_ID=$(echo "$LOGIN_OUTPUT" | grep -oE 'User ID:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)

      if [[ -n "$EXTRACTED_ID" ]]; then
        print_info "추출된 User ID: $EXTRACTED_ID — 검증 중..."
        AUTH_OUTPUT=$("$BINARY_PATH" auth --user-id "$EXTRACTED_ID" --verbose 2>&1)
        if echo "$AUTH_OUTPUT" | grep -q "Database opened successfully"; then
          USER_ID="$EXTRACTED_ID"
          SECURE_KEY=$(echo "$AUTH_OUTPUT" | grep "Secure key:" | awk '{print $3}')
          print_success "OpenKakao로 자동 발견됨: $USER_ID"
        fi
      else
        print_warn "OpenKakao 출력에서 User ID 못 찾음"
        echo "$LOGIN_OUTPUT" | tail -10
      fi
    fi
  fi
fi

# If still no User ID after all auto methods, prompt manually
if [[ -z "$USER_ID" ]]; then
  echo ""
  print_warn "자동 탐색 실패 — User ID를 직접 입력해야 합니다."
  echo ""
  printf "  ${BOLD}User ID 확인 방법${NC}\n\n"
  printf "  ${BOLD}방법 1${NC}: 카카오 개발자 페이지 (가장 안정적)\n"
  printf "    https://developers.kakao.com → 우측 상단 프로필 → 내 정보\n"
  printf "    회원번호: 표시되는 숫자가 User ID\n\n"
  printf "  ${BOLD}방법 2${NC}: 카카오톡 모바일 앱\n"
  printf "    더보기(...) → 설정 → 카카오계정\n"
  printf "    (앱 버전에 따라 표시 안 될 수 있음)\n\n"

  printf "${BOLD}카카오톡 User ID 입력 (숫자만, 8~10자리): ${NC}"
  read -r USER_ID < /dev/tty

  if [[ ! "$USER_ID" =~ ^[0-9]+$ ]]; then
    print_error "숫자가 아닙니다: '$USER_ID'"
    exit 1
  fi

  # Verify
  AUTH_OUTPUT=$("$BINARY_PATH" auth --user-id "$USER_ID" --verbose 2>&1)
  if ! echo "$AUTH_OUTPUT" | grep -q "Database opened successfully"; then
    print_error "이 User ID로 DB 복호화 실패."
    echo ""
    echo "$AUTH_OUTPUT" | tail -10
    exit 1
  fi
  SECURE_KEY=$(echo "$AUTH_OUTPUT" | grep "Secure key:" | awk '{print $3}')
  print_success "User ID 검증됨: $USER_ID"
fi

# ============================================================================
# Step 4: Save config
# ============================================================================

print_step "설정 저장"

cat > "$CONFIG_FILE" <<EOF
# Kakao Summary Toolkit Config
# Generated: $(date)
# DO NOT COMMIT THIS FILE TO GIT

export KAKAOCLI_BIN="$BINARY_PATH"
export KAKAOCLI_USER_ID="$USER_ID"
export KAKAOCLI_DB="$DB_PATH"
export KAKAOCLI_KEY="$SECURE_KEY"
EOF

chmod 600 "$CONFIG_FILE"
print_success "설정 저장: $CONFIG_FILE (권한: 600, 본인만 읽기 가능)"

# Add to shell profile if not already present
SHELL_RC="$HOME/.zshrc"
SOURCE_LINE="[ -f $CONFIG_FILE ] && source $CONFIG_FILE"

if ! grep -qF "$CONFIG_FILE" "$SHELL_RC" 2>/dev/null; then
  echo "" >> "$SHELL_RC"
  echo "# Kakao Summary Toolkit" >> "$SHELL_RC"
  echo "$SOURCE_LINE" >> "$SHELL_RC"
  print_success ".zshrc에 자동 로드 추가됨"
fi

# Source for current session
source "$CONFIG_FILE"

# ============================================================================
# Step 5: Verification — list top chats
# ============================================================================

print_step "동작 확인 — 상위 채팅방 5개"
echo ""

"$BINARY_PATH" chats --db "$KAKAOCLI_DB" --key "$KAKAOCLI_KEY" --limit 5 --json | \
  python3 -c "
import json, sys
chats = json.load(sys.stdin)
for c in chats:
    name = c.get('display_name', '(unknown)')
    members = c.get('member_count', 0)
    unread = c.get('unread_count', 0)
    last = c.get('last_message_at', '?')
    print(f'  • {name} (멤버 {members:,}명, 안읽음 {unread:,}개) — 최근: {last[:10]}')
"

# ============================================================================
# Done
# ============================================================================

printf "\n${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}\n"
printf "${GREEN}${BOLD}  ✓ 설치 완료!${NC}\n"
printf "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}\n\n"
printf "${BOLD}이제 사용 가능한 명령어:${NC}\n\n"
printf "  ${BOLD}# 채팅방 목록${NC}\n"
printf "  \$KAKAOCLI_BIN chats --db \"\$KAKAOCLI_DB\" --key \"\$KAKAOCLI_KEY\" --limit 20 --json\n\n"
printf "  ${BOLD}# 특정 채팅방 메시지 (어제 24시간치)${NC}\n"
printf "  \$KAKAOCLI_BIN messages --chat-id <ID> --since 24h --limit 5000 --json \\\\\n"
printf "    --db \"\$KAKAOCLI_DB\" --key \"\$KAKAOCLI_KEY\"\n\n"
printf "${BOLD}참고:${NC}\n"
printf "  • 새 터미널 창에서는 환경변수 자동 로드 (.zshrc에 추가됨)\n"
printf "  • 채팅방 이름이 (unknown)으로 보이면: ${BOLD}\$KAKAOCLI_BIN harvest${NC}\n"
printf "    (Accessibility 권한 추가 필요, 카톡 앱 켜져 있어야 함)\n\n"
