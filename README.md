# Kakao Summary Toolkit

> macOS 카카오톡 단톡방 메시지를 JSON으로 추출하는 패키지

## 설치 (10분)

```bash
curl -fsSL https://raw.githubusercontent.com/is-theo/kakao-summary-toolkit/main/install.sh | bash
```

설치 스크립트가 자동으로 처리:

- ✅ 의존성 설치 (sqlcipher)
- ✅ 패치된 `kakaocli` 바이너리 다운로드
- ✅ Full Disk Access 권한 안내
- ✅ 카카오 User ID 자동 탐색
- ✅ 설정 저장 (`~/.kakaocli-config`)
- ✅ 동작 확인 (상위 채팅방 5개 표시)

## 사전 요구사항

- macOS 14 이상 (Apple Silicon 권장)
- 카카오톡 Mac 앱 설치 + **로그인 완료**
- Homebrew (없으면 [brew.sh](https://brew.sh))

## 사용법

### 채팅방 목록 보기

```bash
~/Applications/kakaocli/scripts/list-chats.sh
~/Applications/kakaocli/scripts/list-chats.sh 50  # 50개까지
```

### 특정 채팅방 메시지 추출

```bash
# 어제 24시간치 → /tmp/kakao-<chat_id>-YYYY-MM-DD.json
~/Applications/kakaocli/scripts/extract.sh 18471795774277780

# 최근 7일치
~/Applications/kakaocli/scripts/extract.sh 18471795774277780 7d

# 출력 파일 지정
~/Applications/kakaocli/scripts/extract.sh 18471795774277780 24h ~/Desktop/output.json
```

### 직접 명령어 사용

설치 후 새 터미널 창에서는 환경변수가 자동 로드됨:

```bash
$KAKAOCLI_BIN chats --db "$KAKAOCLI_DB" --key "$KAKAOCLI_KEY" --limit 20 --json

$KAKAOCLI_BIN messages --chat-id <ID> --since 24h --limit 5000 --json \
  --db "$KAKAOCLI_DB" --key "$KAKAOCLI_KEY"
```

## 트러블슈팅

### `Permission denied` 또는 `file is not a database`

Full Disk Access 권한 부여 후 **터미널 앱을 완전히 종료(Cmd+Q) 후 재실행**해야 합니다.

### 채팅방 이름이 `(unknown)`으로 표시됨

```bash
# Accessibility 권한 추가 필요 (시스템 설정 > 손쉬운 사용)
# 카카오톡 앱 켜진 상태에서:
$KAKAOCLI_BIN harvest --db "$KAKAOCLI_DB" --key "$KAKAOCLI_KEY"
```

### User ID 자동 탐색 실패

설치 스크립트가 묻는 User ID는 다음 중 하나로 확인:

1. **카카오 개발자 페이지** ([developers.kakao.com](https://developers.kakao.com)) → 내 정보 → 회원번호
2. **OpenKakao 도구** (가장 안정적):
   ```bash
   brew tap JungHoonGhae/openkakao
   brew install openkakao-cli
   openkakao-cli login --save  # 출력에서 'User ID' 확인
   ```

## 출력 JSON 스키마

```json
{
  "chat_id": 18471795774277780,
  "id": 3826061779558066177,
  "is_from_me": false,
  "sender_id": 6643008241609006538,
  "text": "메시지 본문",
  "timestamp": "2026-04-24T14:01:46Z",
  "type": "text"
}
```

| 필드 | 설명 |
|------|------|
| `chat_id` | 채팅방 ID |
| `id` | 메시지 고유 ID (멱등성 처리용) |
| `is_from_me` | 본인 발화 여부 |
| `sender_id` | 발화자 카카오 User ID |
| `text` | 메시지 본문 |
| `timestamp` | ISO8601 UTC |
| `type` | `text`, `unknown` (이미지/파일/링크 등) |

## 보안 주의사항

- `~/.kakaocli-config` 파일에 DB 복호화 키가 저장됩니다 (권한 600)
- 이 파일은 **절대 Git 커밋이나 클라우드 백업에 포함하지 마세요**
- 키는 디바이스 + 카카오 계정 조합으로 결정론적으로 도출됩니다 — 디바이스나 계정 바뀌면 키도 바뀜

## 크레딧

- **kakaocli** — [silver-flight-group](https://github.com/silver-flight-group/kakaocli) (MIT License)
- 이 레포는 kakaocli의 풀 키 출력 패치를 적용한 빌드를 배포합니다

## License

MIT
