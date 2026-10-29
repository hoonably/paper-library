# 개발 가이드

Paper Library는 SwiftUI 앱이며, Finder 서비스로 받은 PDF만 처리하는 Codex 기반 정리기를 포함합니다. 사용자 PDF와 카탈로그를 테스트 데이터로 사용하지 마세요.

## 실행과 검증

macOS 14 이상, Xcode Command Line Tools, Node.js가 필요합니다. DMG 생성에는 `uv`를 사용합니다.

```sh
swift build --disable-keychain
scripts/run-core-checks.sh
scripts/check-update-preferences.sh
scripts/build-local-app.sh
```

- `swift build`는 앱 코드를 컴파일합니다. 정상 실행·권한·업데이트 확인은 `dist/Paper Library.app`을 사용하세요.
- 핵심 검사는 임시 라이브러리에서 CSV·경로 안전성·파일 이동·저장소·모델 목록을 확인하고, 별도 앱에서 Finder 서비스 수명 주기를 검사합니다.
- 업데이트 검사는 임의의 테스트 번들 ID로 실제 Sparkle 설정 저장·재실행 복원·알림과 자동 다운로드의 분리, 작업 중 설치 대기·완료 후 재개를 확인합니다. 운영 앱의 설정이나 릴리스 피드를 사용하지 않습니다.
- 패키징은 검증된 앱, 설치 DMG, Sparkle용 ZIP을 만듭니다. 릴리스 발행·버전 증가·appcast 변경은 하지 않습니다.

## 주요 파일

| 위치 | 역할 |
| --- | --- |
| `Views/ContentView.swift` | 첫 실행 저장소 안내, 검색·필터, 3열 라이브러리 |
| `Views/OrganizerStatusHeader.swift` | 정리 상태, 모델·언어, 설정 진입 |
| `Views/AutomationSetupView.swift` | Codex 연결과 요약 언어 |
| `App/UpdateController.swift` | 업데이트 창과 Sparkle 설정 |
| `Services/LibraryStore.swift` | 앱 상태, 저장소 준비·재시도, 자동 정리 |
| `Services/LibraryLayout.swift` | 앱 전용 저장소와 초기 설정 판단 |

위 경로는 `Sources/PaperLibrary/` 기준입니다.

## 화면 확인

첫 실행에서 접근 이유가 파일 접근보다 먼저 보이는지, 허용·거절 후 재시도가 가능한지 확인합니다. 기존 라이브러리는 다시 초기 설정을 요구하지 않아야 합니다. Documents 권한은 OS 동의로 처리하며 전체 디스크 권한이나 접근성을 요청하지 않습니다.

좁은 창과 밝은·어두운 모드에서 검색·활성 필터·결과 없음·첫 PDF 안내·설정·업데이트 창을 확인합니다. Finder 서비스로 추가할 때는 앱 창이나 업데이트 창을 띄우지 않아야 합니다.

기존 논문 삭제·이동·재분류 테스트에는 별도 임시 데이터를 사용합니다. 릴리스 검사는 [배포 가이드](DISTRIBUTION.md)를 따르세요.

소개용 캡처는 `docs/images/app-overview.webp`를 README와 사이트가 함께 사용합니다.
현재 화면을 2×로 렌더한 3200×1880 원본이며, 이전 이미지를 확대하지 않습니다.
Attention, ResNet, AlexNet, BERT, Adam, GAN, VAE의 공식 서지 정보로 예시 목록을
구성하고 사용자의 PDF·라이브러리·계정은 캡처에 사용하지 않습니다. 새 캡처도
현재 앱의 글자와 아이콘을 실제 해상도로 렌더하고 WebP 변환 시 추가 손실을 피합니다.
