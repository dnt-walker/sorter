# CLAUDE.md

이 파일은 이 저장소에서 작업하는 Claude Code(및 개발자)를 위한 가이드입니다.

## 프로젝트 개요

**Sorter** — macOS용 네트워크 라우팅 관리 앱 (Swift).

macOS의 라우팅 테이블을 GUI로 관리하는 도구. 사용자가 "목적지 IP는 특정 네트워크 디바이스(인터페이스)로 보내라"는 정책별 라우트(policy route)를 쉽게 추가/수정/삭제할 수 있게 한다. 내부적으로는 macOS의 `route` 명령을 사용한다.

### 핵심 기능

1. **네트워크 디바이스 목록 출력**
   - 현재 시스템에 등록된 네트워크 인터페이스 목록을 표시한다.
   - 세부 정보(인터페이스명, 표시 이름, IP/MAC 주소, 상태(up/down), MTU 등)를 함께 출력할 수 있다.
2. **목적지별 라우팅 추가**
   - 예) 목적지가 `12.12.3.4` 이면 `en0`(eth0) 로 라우팅.
   - 호스트 단위(`-host`) 및 네트워크 단위(`-net`, CIDR) 라우트를 모두 지원.
3. **라우팅 적용은 macOS `route` 명령 사용**
   - 직접 라우팅 테이블 syscall을 호출하지 않고 `/sbin/route` CLI를 호출한다.
4. **라우팅 제거 / 수정**
   - 이미 등록된 라우트를 삭제하거나 목적지/인터페이스를 변경할 수 있다.
5. **기본 라우트 보호**
   - 시스템 기본 라우트(default gateway 등) 및 사용자가 앱으로 추가하지 않은 라우트는 **수정/삭제 금지**.
   - **앱을 통해 사용자가 등록한 라우트만** 수정/삭제 가능.
6. **재반영(re-apply)**
   - 저장된 사용자 라우트가 외부 삭제·재부팅·인터페이스 변경 등으로 라우팅 테이블에서 사라졌을 때, 누락된 항목만 다시 등록한다.
   - 이미 적용된 항목은 건너뛰고, 인터페이스가 사라진 항목은 보고만 한다.

## 아키텍처

### UI
- **SwiftUI** 기반 macOS 앱 (최소 macOS 13 Ventura 권장).
- 주요 화면:
  - `DevicesView` — 네트워크 디바이스 목록 + 세부 정보.
  - `RoutesView` — 라우트 목록(사용자 라우트는 편집 가능, 시스템 라우트는 읽기 전용/잠금 표시).
  - `RouteEditView` — 라우트 추가/수정 폼(목적지, 넷마스크/CIDR, 대상 인터페이스 선택).

### 레이어 구조
```
App (SwiftUI)
 ├─ Views/            화면
 ├─ ViewModels/       상태 관리 (ObservableObject)
 ├─ Services/
 │   ├─ NetworkDeviceService   디바이스 열거/세부정보 조회
 │   ├─ RouteService           route 명령 실행(추가/삭제/조회)
 │   └─ PrivilegedRunner       권한 상승 명령 실행
 ├─ Store/
 │   └─ ManagedRouteStore      "앱이 관리하는 라우트" 영속화
 └─ Models/           Device, Route, ManagedRoute 등
```

### 데이터 모델 (핵심)
- `NetworkDevice`: `bsdName`(en0), `displayName`(Wi-Fi), `ipv4`, `ipv4Prefix`(넷마스크→프리픽스), `ipv6`, `mac`, `gateway`(이 인터페이스의 default 게이트웨이), `isUp`, `mtu`.
  - `isInLocalSubnet(_:)` — 목적지가 이 인터페이스의 로컬 IPv4 서브넷에 속하는지(`SubnetMath` 사용). 게이트웨이 자동 추천/검증의 기준.
- `RouteEntry`: `destination`, `gateway`, `flags`, `interface`, `family`(v4/v6). `netstat -rn` 한 행.
- `ManagedRoute`: 앱이 추가한 라우트 메타데이터. `id(UUID)`, `destination`, `prefix`, `kind`(host/net), `interface`, `gateway?`, `createdAt`. **이 스토어에 있는 라우트만 수정/삭제 허용**의 기준이 된다.

## 시스템 명령 사용법 (구현 참고)

### 네트워크 디바이스 열거
- 권한 불필요. 우선순위:
  1. **SystemConfiguration / `getifaddrs`** (API 기반, 권장) — 가능하면 셸 호출보다 우선.
  2. 보조: `networksetup -listallhardwareports`, `ifconfig`, `ipconfig getifaddr en0`.
- BSD 이름(en0)과 사용자 표시 이름(Wi-Fi/Ethernet) 매핑은 `networksetup -listallhardwareports` 로 얻는다.

### 라우트 조회
```sh
netstat -rn            # 전체 라우팅 테이블 (IPv4/IPv6)
route -n get <dest>    # 특정 목적지 라우트 조회
```
> 앱이 표시하는 "사용자 라우트"는 시스템 라우팅 테이블이 아니라 `ManagedRouteStore`를 source of truth로 삼고, 실제 적용 상태는 `netstat`/`route get`으로 교차 확인한다.
>
> ⚠️ **적용 여부 판정 주의(실제 버그였음):** `route get <dest>` 는 목적지가 무엇이든 **항상 기본 라우트로라도 응답**하고 출력에 `interface:` 가 늘 들어 있다. 따라서 "응답이 있는가"로 판정하면 **항상 적용됨으로 오판**한다. 반드시 해석된 `interface:` (게이트웨이 라우트면 `gateway:` 까지)가 `ManagedRoute`의 값과 **일치하는지** 비교해야 한다. (`RouteService.isApplied` / `parseRouteGet`)

### 라우트 추가/삭제 (권한 필요)
```sh
# 호스트 라우트: 12.12.3.4 를 en0 인터페이스로
sudo route -n add -host 12.12.3.4 -interface en0

# 네트워크 라우트 (CIDR)
sudo route -n add -net 12.12.3.0/24 -interface en0

# 게이트웨이 지정 라우트
sudo route -n add -host 12.12.3.4 192.168.0.1

# 삭제
sudo route -n delete -host 12.12.3.4
sudo route -n delete -net 12.12.3.0/24
```
> **수정(modify)** 은 `route change` 대신 **delete → add** 로 구현하는 것을 기본으로 한다(인터페이스/타입 변경 시 더 안정적).

## 라우팅 정책: interface 라우트 vs gateway 라우트 (반드시 준수)

> 이 구분을 틀리면 라우트는 등록되지만 **통신이 안 된다**. 실제 버그로 확인된 사항.

- `route add ... -interface en13` (게이트웨이 없음) → **interface(link-level) 라우트**. 플래그 `UHLS`(L=link-level), gateway 자리에 인터페이스 MAC. 목적지를 **해당 링크에 직접 연결된 장비로 간주**하고 ARP를 보낸다.
  - ✅ 목적지가 그 인터페이스의 **로컬 서브넷 안**일 때만 올바르다.
  - ❌ 공인 IP 등 **비로컬 목적지에 쓰면 패킷이 로컬 링크 밖으로 못 나가 도달 실패**.
- `route add ... <gatewayIP>` → **gateway 라우트**. 플래그 `UGHS`(G=gateway). 목적지를 **next-hop 라우터로 전달**한다.
  - ✅ 비로컬 목적지는 반드시 이 방식. 보통 그 인터페이스의 default 게이트웨이를 next-hop으로 쓴다.

### 앱의 규칙 (A안 — 구현 완료)
1. 인터페이스 선택 시, 목적지가 그 인터페이스의 로컬 서브넷 **밖**이면(`NetworkDevice.isInLocalSubnet == false`) **게이트웨이를 자동 추천**해 채운다(인터페이스의 default 게이트웨이 = `NetworkDevice.gateway`).
2. 사용자가 직접 입력한 게이트웨이는 보존한다(자동 추천값 추적).
3. 추천 게이트웨이가 없으면 경고를 표시하고 수동 입력을 요구한다.
4. 저장 가드(`RoutesViewModel.save`): 비로컬 목적지인데 게이트웨이가 비어 있으면 **저장 차단**(UI 우회 방지).
- 인터페이스의 default 게이트웨이는 `netstat -rnf inet` 의 `default <ip> ... <netif>` 행에서 추출(`link#` 게이트웨이는 제외). 로컬 서브넷 판정은 `getifaddrs`의 넷마스크에서 계산한 `ipv4Prefix` + `SubnetMath.sameSubnetIPv4`.

## 재반영(re-apply) 정책

- source of truth는 `ManagedRouteStore`. 재반영은 저장된 라우트와 실제 테이블(`route -n get`)을 비교해 **누락분만** 다시 `add` 한다.
- 이미 적용된 항목은 건너뛴다.
- 인터페이스가 사라진(이름 변경 등) 항목은 적용하지 않고 사용자에게 보고한다(자동으로 다른 인터페이스에 매핑하지 않는다 — 사용자 판단 필요).
- **여러 라우트를 한 번의 권한 인증으로** 적용한다: `PrivilegedRunner.runRouteBatch` 가 여러 `route` 명령을 `;` 로 이어 osascript 권한 호출을 1회만 띄운다.

## 권한(Privilege) 처리 — 중요

`route add/delete` 는 **root 권한**이 필요하다. 구현 옵션(권장 순):

1. **SMAppService / SMJobBless 권한 헬퍼(권장, 배포용)**
   - 별도 privileged helper(launchd daemon)를 등록해 IPC(XPC)로 route 명령 실행.
   - 사용자 한 번 인증 후 매번 비밀번호 입력 불필요. App Store/공증 배포에 적합.
2. **AuthorizationServices (`AuthorizationExecuteWithPrivileges`)**
   - 구식/deprecated 이지만 빠른 프로토타입에 사용 가능.
3. **`osascript ... with administrator privileges`** (개발/프로토타입용)
   - `do shell script "route ..." with administrator privileges` → GUI 비밀번호 프롬프트.
   - **MVP 단계에서는 이 방식으로 시작**하고, 이후 1번 헬퍼로 전환.

`PrivilegedRunner` 프로토콜로 추상화해 백엔드(osascript ↔ XPC helper)를 교체 가능하게 한다.
- `runRoute(arguments:)` — 단일 명령. 기본 구현은 `runRouteBatch`에 위임.
- `runRouteBatch(argumentLists:)` — **여러 route 명령을 한 번의 권한 인증으로** 실행(재반영 등 일괄 처리). 인증 프롬프트 남발을 막는다.
- 현재 osascript 방식은 작업마다 비밀번호를 요구한다. "매번 입력 없이"가 필요하면 SMAppService 권한 헬퍼(1번)로 전환해야 하며, 이는 Developer ID 서명이 전제다.

## 기본 라우트 보호 규칙 (반드시 준수)

- 라우트의 편집/삭제 가능 여부는 **오직 `ManagedRouteStore`에 등록된 항목인지**로 판단한다.
- 시스템/기타 라우트는 UI에서 **잠금 아이콘 + 비활성화** 처리하고, 삭제·수정 액션을 노출하지 않는다.
- 추가 안전장치(권장):
  - `default` 목적지 라우트는 절대 삭제 대상에서 제외.
  - 삭제/수정 직전, 대상이 `ManagedRouteStore`에 존재하는지 한 번 더 검증(서비스 레이어 가드).
- 앱 제거/재설치 후에도 일관성을 위해 `ManagedRouteStore`는 영속화한다(Application Support 디렉터리의 JSON 권장).

## 입력 검증

- 목적지: 유효한 IPv4/IPv6 주소 또는 CIDR 인지 검증(`inet_pton`).
- 인터페이스: 현재 존재하는 `NetworkDevice.bsdName` 목록에서만 선택 가능.
- 중복 라우트 추가 방지(같은 destination+prefix).
- 모든 외부 명령 인자는 화이트리스트 검증 후 전달(셸 인젝션 방지 — 가능하면 `Process` 인자 배열 사용, 셸 문자열 결합 금지).

## 프로젝트 셋업 / 빌드

- Xcode 프로젝트(`Sorter.xcodeproj`) 생성 완료. SwiftUI, Swift 언어 모드 5.0(컴파일러 Swift 6.2), 최소 배포 타깃 macOS 13.0.
- 번들 ID: `com.cheilpengtai.Sorter`.
- 빌드(CLI):
  ```sh
  xcodebuild -scheme Sorter -configuration Debug -destination 'platform=macOS' build
  ```
- 로컬 서명: ad-hoc(`CODE_SIGN_IDENTITY = "-"`, Manual). 별도 개발팀 없이 빌드/실행 가능.
- 외부 명령을 실행하므로 **App Sandbox 미사용**(엔타이틀먼트 없음). 샌드박스를 켜면 `Process`로 `/sbin/route` 직접 실행이 막히므로 켜지 말 것. 향후 XPC 권한 헬퍼 도입 시 별도 설계 필요.

### 소스 구조
```
Sorter/
  SorterApp.swift            앱 진입점
  Models/                    NetworkDevice, RouteEntry, ManagedRoute
  Services/                  CommandRunner, IPValidator(+SubnetMath), RouteTableParser,
                             PrivilegedRunner, RouteService, NetworkDeviceService
  Store/                     ManagedRouteStore (JSON 영속화)
  ViewModels/                DevicesViewModel, RoutesViewModel
  Views/                     ContentView, DevicesView, RoutesView, RouteEditView
  Assets.xcassets/           AppIcon, AccentColor
tools/                       make_icon.swift (아이콘 생성 스크립트), icon_1024.png
dist-assets/                 설치안내-README.txt (배포 동봉용)
dist/                        빌드 산출물(.dmg/.zip) — 커밋 대상 아님
```

- 영속화 위치: `~/Library/Application Support/Sorter/managed-routes.json` (ISO8601 날짜, pretty-printed).

## 배포(Distribution) 정책

이 앱은 **App Sandbox 미사용 + `route`/osascript 권한 명령**을 쓰므로 배포 경로가 제한된다.

- **Mac App Store: 불가.** 샌드박스 필수 + 권한 명령 금지 정책에 위배.
- **현재 방식(무료): ad-hoc 서명.** Apple Developer Program 미가입 상태. `CODE_SIGN_IDENTITY = "-"`, `TeamIdentifier=not set`, 공증 없음.
  - 받는 사람이 **첫 실행 시 Gatekeeper 1회 우회** 필요: 시스템 설정 → 개인정보 보호 및 보안 → "열도록 허용", 또는 `xattr -dr com.apple.quarantine /Applications/Sorter.app`.
  - 사내/소수 Mac 배포에 적합. 안내문은 `dist-assets/설치안내-README.txt`.
- **권장(외부/마찰 없는 배포): Developer ID 서명 + notarytool 공증 + staple.** Apple Developer Program($99/년) 가입 전제. 가입 시 hardened runtime이 활성화되고(현재 ad-hoc은 비활성), 경고 없이 실행된다.

### 배포 패키지 생성
```sh
xcodebuild -scheme Sorter -configuration Release -derivedDataPath ./build -destination 'platform=macOS' build
# .app → DMG(앱 + /Applications 링크 + README) / ZIP(ditto)
```

## 앱 아이콘

- 모티프: 하나의 소스 노드 → 여러 인터페이스로 라우팅 분기(블루→인디고 그라데이션 둥근 사각형).
- `tools/make_icon.swift`(AppKit)로 1024px 마스터를 그린다. 디자인 변경 시 이 스크립트를 수정 후 재생성:
  ```sh
  swift tools/make_icon.swift tools/icon_1024.png
  # sips로 16~1024px 10종 생성 → Assets.xcassets/AppIcon.appiconset/
  ```
- `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 설정 필요. 모든 크기는 규격 픽셀(16/32/32/64/128/256/256/512/512/1024)에 정확히 맞춰야 경고가 없다.

## 개발 컨벤션

- Swift 표준 네이밍(타입 `UpperCamelCase`, 멤버 `lowerCamelCase`).
- 외부 명령 실행은 `Services` 레이어에만 둔다(View/ViewModel에서 직접 `Process` 호출 금지).
- `route`/`netstat` 출력 파싱은 별도 파서 함수로 분리하고 단위 테스트를 작성한다.
- 에러는 `throws` + 타입드 에러(`enum RouteError`)로 전달하고 UI에서 사용자 친화 메시지로 변환.
- 권한이 필요한 작업은 실행 전 사용자에게 무엇이 실행되는지(명령 내용) 명시.

## 작업 시 주의 (Claude 용)

- 라우팅 테이블을 실제로 변경하는 명령은 **사용자 시스템에 영향**을 준다. 테스트 시 무해한 목적지(예: 문서화용 `192.0.2.0/24`, TEST-NET) 또는 dry-run 우선.
- 기본 라우트 보호 규칙을 우회하는 코드(시스템 라우트 삭제 허용 등)는 작성하지 않는다.
- 비밀번호/인증 흐름을 임의로 저장하거나 로깅하지 않는다.
