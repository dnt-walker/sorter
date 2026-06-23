<div align="center">

<img src="assets/icon.png" width="128" alt="Sorter app icon" />

# Sorter

**macOS 네트워크 라우팅 · SSH 터널 관리 앱**

목적지 IP를 원하는 네트워크 인터페이스로 보내는 정책 라우트와 SSH 포트 포워딩 터널을 GUI로 손쉽게 관리합니다.

</div>

---

## 소개

Sorter는 macOS의 네트워크 설정을 GUI로 다루는 유틸리티입니다.

- **라우팅 관리** — "목적지가 `x.x.x.x` 이면 `en0`(USB 이더넷)으로 보내라" 같은 **정책별 라우트** 를 터미널 없이 추가·수정·삭제합니다.
- **SSH 터널링** — `ssh -L localPort:remoteHost:remotePort user@server` 와 동일한 포트 포워딩 터널을 GUI로 관리합니다. 여러 터널을 저장해 두고 한 번의 클릭으로 연결할 수 있습니다.

## 주요 기능

### 디바이스
- 시스템에 등록된 네트워크 인터페이스 목록 (인터페이스명, 표시 이름, IPv4/IPv6, MAC, 상태, MTU)

### 라우팅
- 호스트(`-host`)와 네트워크(CIDR) 라우트 추가·수정·삭제
- 게이트웨이 자동 추천 — 비로컬 목적지에 next-hop 게이트웨이를 자동으로 채워 "등록은 됐지만 통신이 안 되는" 실수를 방지
- 기본 라우트 보호 — 시스템 라우트는 잠금 처리되어 절대 수정·삭제 불가
- 재반영(re-apply) — 재부팅·외부 삭제로 사라진 라우트를 한 번의 인증으로 다시 등록

### SSH 터널 *(1.2.0 신규)*
- 비밀번호 / 공개키(Ed25519, RSA) 인증 모두 지원
- 비밀번호는 macOS Keychain에 안전하게 저장
- SSH 명령어 문자열 붙여넣기 → 자동 파싱으로 설정 입력 간소화  
  예) `ssh -L 43389:172.25.4.100:3389 dig@server.example.com -p2222` 입력 후 **채우기**
- 현재 입력값으로 SSH 명령어 자동 생성 및 복사
- 연결 상태 실시간 표시 (연결 중 / 연결됨 / 오류)
- 터널이 외부에서 끊어지면 자동 감지 및 상태 업데이트
- 앱 종료 시 모든 터널 자동 해제

## 구동 환경

| 항목 | 요구 사항 |
|------|-----------|
| 운영체제 | **macOS 13 (Ventura) 이상** |
| 아키텍처 | Apple Silicon · Intel (Universal) |
| 권한 | 라우트 변경 시 **관리자(sudo) 비밀번호** 입력 필요 |
| 기타 | 별도 런타임/의존성 없음 |

## 다운로드 & 설치

1. [**Releases**](../../releases/latest) 페이지에서 `Sorter-1.2.0.dmg` 를 내려받습니다.
2. DMG를 열고 `Sorter.app` 을 **Applications** 폴더로 끌어다 놓습니다.

### ⚠️ 최초 실행 (필수)

이 앱은 Apple 공증(notarization)을 받지 않은 빌드라, 처음 실행 시 *"확인되지 않은 개발자"* 경고가 표시됩니다. 아래 중 하나로 **한 번만** 허용하면 됩니다.

**방법 A — 시스템 설정 (권장)**
1. `Sorter.app` 실행 → 차단됨
2. **시스템 설정 → 개인정보 보호 및 보안**
3. 아래쪽 **"Sorter을(를) 열도록 허용"** 클릭 → 다시 실행 후 **열기**

**방법 B — 터미널**
```sh
xattr -dr com.apple.quarantine /Applications/Sorter.app
```

## 사용법

### 1) 디바이스 확인
사이드바의 **디바이스** 탭에서 라우팅 대상이 될 인터페이스의 이름(en0, en13 …)과 IP를 확인합니다.

### 2) 라우트 추가
1. **라우트** 탭 → **라우트 추가** 클릭
2. **목적지 유형** 선택 (호스트 / 네트워크)
3. **목적지** 입력 (예: `1.1.1.1`)
4. **대상 인터페이스** 선택 (예: `en0`)
5. 목적지가 인터페이스의 로컬 서브넷 밖이면 **게이트웨이가 자동 추천**됩니다.
6. 실행될 `route` 명령 **미리보기**를 확인하고 **추가·적용** → 관리자 비밀번호 입력

> 💡 공인 IP 같은 비로컬 목적지는 반드시 게이트웨이(next-hop 라우터)를 지정해야 합니다. Sorter가 자동으로 추천·검증합니다.

### 3) SSH 터널 추가 및 연결
1. **SSH 터널** 탭 → **터널 추가** 클릭
2. 기존 SSH 명령어가 있으면 상단 입력란에 붙여넣고 **채우기** — 자동으로 각 항목이 채워집니다.
3. 이름, SSH 서버, 인증 방식, 포워딩 포트를 설정하고 **추가**
4. 목록에서 해당 터널의 **연결** 버튼 클릭 → 로컬 포트로 접속 가능

### 4) 수정 / 삭제 / 재반영
- 사용자 라우트: 행의 **수정 / 삭제** 버튼 사용. 시스템 라우트는 🔒 잠금.
- 라우팅 테이블에서 사라진 라우트(⚠️ 표시): 상단 **재반영** 버튼으로 일괄 복구.

## 동작 원리 & 보안

- 라우트 변경은 macOS 표준 `/sbin/route` 명령으로 수행합니다(직접 syscall 호출 없음).
- root 권한이 필요한 작업은 실행 직전 **명령 내용을 미리 보여주고**, macOS 인증 프롬프트로만 권한을 얻습니다.
- SSH 비밀번호는 **macOS Keychain에만 저장**되며, 로그·파일에 기록하지 않습니다.
- 앱이 추가한 라우트는 `~/Library/Application Support/Sorter/managed-routes.json` 에, 터널 설정은 `tunnel-configs.json` 에 저장됩니다(비밀번호 제외).

## 소스에서 빌드

```sh
git clone <this-repo>
cd Sorter
xcodebuild -scheme Sorter -configuration Release \
  -derivedDataPath ./build -destination 'platform=macOS' build
# 결과물: build/Build/Products/Release/Sorter.app
```
- Xcode 16+ / Swift 6.2 (언어 모드 5.0)
- App Sandbox 미사용 (외부 명령 실행 필요)

## 라이선스

[MIT License](LICENSE) © 2026 dnt-walker

---

<div align="center">
<sub>⚠️ 라우팅 테이블 변경은 시스템 네트워크에 영향을 줍니다. 테스트는 무해한 목적지(예: <code>192.0.2.0/24</code>, TEST-NET)로 먼저 확인하세요.</sub>
</div>
