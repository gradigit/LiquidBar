# LiquidBar

[English](README.md)

![LiquidBar wordmark](Assets/Brand/liquidbar-brand-bar-transparent.png)

**macOS용 오픈 소스 Liquid Glass 작업 표시줄 및 Cmd-Tab 윈도우 전환기입니다.**

LiquidBar는 macOS에서 부족했던 윈도우 제어 경험을 보완합니다. 실제 작업
표시줄, 큰 윈도우 썸네일, Windows Alt-Tab에 가까운 전환 동작, 시스템
표시기, 깊이 있는 설정을 macOS다운 Liquid Glass 스타일로 제공합니다.

## 왜 LiquidBar인가요?

많은 macOS 작업 표시줄 앱은 닫힌 소스이면서 손쉬운 사용, 화면 기록, 입력
모니터링 같은 강력한 권한을 요청합니다. LiquidBar는 반대로 접근합니다. 코드를
검토할 수 있고, 직접 빌드할 수 있으며, 권한이 필요한 기능이 무엇인지 문서로
확인할 수 있습니다.

## 주요 기능

![LiquidBar Cmd-Tab switcher animation](Assets/Screenshots/cmd-tab-switcher.gif)

- **윈도우 중심 Cmd-Tab 전환기:** 큰 썸네일, MRU 방식 왕복 전환,
  `Cmd-Shift-Tab` 역방향 이동, 클릭 선택을 지원합니다.
- **네이티브 작업 표시줄:** 하단, 상단, 왼쪽, 오른쪽 배치와 아이콘 전용 모드,
  앱 그룹, 고정 앱, 사용자 항목을 지원합니다.
- **Liquid Glass 스타일:** macOS에 어울리는 비브런시, 글래스 타일, 호버,
  포커스 표시를 사용합니다.
- **시스템 표시기:** CPU, GPU, RAM, 온도를 막대 안에 표시하고 위치, 색상,
  새로 고침 간격, 표시 방식을 조정할 수 있습니다.
- **멀티 모니터 지원:** 모든 디스플레이, 주 디스플레이만, 디스플레이별 윈도우
  표시 방식을 선택할 수 있습니다.
- **오픈 확장 기반:** 플러그인 및 미디어 컨트롤 같은 확장을 위한 기반이
  포함되어 있습니다.

## 기본 단축키

| 동작 | 기본값 |
| --- | --- |
| 전환기 열기 / 다음 윈도우 | `Cmd-Tab` |
| 이전 윈도우 | `Cmd-Shift-Tab` |
| 전환기 항목 선택 | 마우스 클릭 |
| 작업 표시줄에서 윈도우 순환 | 막대 위에서 스크롤 |
| 환경설정 열기 | 메뉴 막대 아이콘 또는 작업 표시줄 컨텍스트 메뉴 |

## 권한

- **손쉬운 사용:** 윈도우 포커스, 숨기기, 최소화, 닫기, 선택적 윈도우 위치 조정에
  사용합니다.
- **화면 기록:** 작업 표시줄 미리 보기와 전환기 썸네일을 캡처하는 데 사용합니다.
  계속 녹화하는 방식이 아니라 정적 썸네일을 사용합니다.
- **입력 모니터링:** `Cmd-Tab`처럼 macOS가 먼저 처리하는 전역 단축키를 가로채야
  할 때 사용합니다.
- **자동화:** 선택적 제공자나 미디어 제어 기능이 다른 앱을 제어할 때 표시될 수
  있습니다.

권한은 강력합니다. LiquidBar의 장점은 오픈 소스라는 점입니다. 코드를 직접
검토하고, 빌드하고, 사용하지 않는 기능을 끌 수 있습니다.

## 설치 및 빌드

소스에서 실행:

```sh
swift build
swift test -c debug
swift run LiquidBar
```

릴리스 앱 번들 및 DMG 만들기:

```sh
LIQUIDBAR_CREATE_DMG=1 LIQUIDBAR_CREATE_ZIP=0 ./scripts/build_release_app.sh
open build/release/LiquidBar.app
```

초기 릴리스는 Developer ID 서명 및 공증 전까지 ad-hoc 서명 또는 미서명으로
제공될 수 있습니다. macOS Gatekeeper 경고가 표시될 수 있으며, 릴리스 자산은
항상 이 저장소의 공식 릴리스에서만 받으세요.

## 설정

설정 파일 위치:

```text
~/Library/Application Support/LiquidBar/config.json
```

언어는 **환경설정 -> 일반 -> 시스템 -> 언어**에서 바꿀 수 있습니다. 시스템,
영어, 한국어를 선택할 수 있습니다.

## 문서

- `docs/START_HERE.md`: 처음 시작할 때 읽는 안내
- `docs/ARCHITECTURE.md`: 구조와 런타임 흐름
- `docs/DEVELOPMENT.md`: 개발 환경과 명령어
- `docs/TESTING.md`: 테스트와 시각적 QA
- `docs/PERFORMANCE.md`: 성능 측정 및 A/B 비교
- `docs/RELEASE.md`: 릴리스 패키징과 서명/공증 계획

## 라이선스

LiquidBar는 MIT License로 배포됩니다. 자세한 내용은 `LICENSE`를 참고하세요.
