# 배포 가이드

공식 배포는 [서명된 릴리스 절차](SIGNED_RELEASES.md)의 중앙 워크플로를 사용합니다. 아래 로컬 패키징은 검토용이며, 다른 키나 Mac별 개발 인증서로 배포하지 않습니다.

새 설치에는 **DMG**, 앱 내부 Sparkle 업데이트에는 **ZIP**을 제공합니다. 같은 검증된 앱을 두 파일에 넣고 기존 업데이트 서명 키를 유지합니다.

## 로컬 패키징

macOS 14 이상, Xcode Command Line Tools, `uv`가 필요합니다.

```sh
scripts/build-local-app.sh
```

생성 파일:

- `dist/Paper Library.app` — 로컬 확인용 앱
- `dist/Paper-Library-v<version>-macos-<architecture>.dmg` — 앱을 Applications로 드래그하는 설치 파일
- `dist/Paper-Library.zip` — 기존 Sparkle 업데이트 경로를 유지하는 압축 파일

DMG에는 실제 실행 파일의 아키텍처를 표시합니다. 현재 로컬 빌드는 Apple Silicon용이며 Intel 지원으로 소개하지 않습니다. 앱 서명, DMG 무결성, 이미지 안의 앱 서명과 Applications 링크를 검사한 뒤 최종 파일을 교체합니다. Finder 자동화 권한은 필요하지 않습니다.

출력 경로가 앱 서명을 변경하는 메타데이터를 붙이면 느슨한 `.app` 사본을 제거하고 검증된 DMG·ZIP만 남깁니다. 불완전한 베타 SDK를 쓰는 환경은 `MACOS_SDK_PATH=/path/to/MacOSX.sdk`로 안정 SDK를 지정할 수 있습니다.

기존에 빌드한 앱으로 DMG만 다시 만들려면:

```sh
scripts/build-mac-dmg.sh '/path/to/Paper Library.app' '/path/to/output'
```

## 서명과 공증

기본 스크립트는 ad-hoc 서명한 초기 베타 빌드를 만듭니다. **Apple Developer ID 서명·공증을 받은 배포물은 아닙니다.** 릴리스 설명에 이 상태를 명확히 적고, 실행이 막힌 경우 개인정보 보호 및 보안의 **그래도 열기**를 안내합니다.

넓은 배포에는 Apple Developer Program 계정, Developer ID 인증서와 전체 Xcode를 사용하세요. `PaperLibrary.xcodeproj`에서 보관·Developer ID 내보내기·공증을 마친 뒤 티켓을 붙입니다.

```sh
xcrun stapler staple '/path/to/Paper Library.app'
scripts/verify-release-app.sh '/path/to/Paper Library.app'
```

이 검증은 정식 배포 기준이며 ad-hoc 서명, 미공증 또는 비유니버설 앱을 거절합니다. 통과한 앱으로 DMG를 만들고 `ditto -c -k --sequesterRsrc --keepParent`로 동일 앱의 `Paper-Library.zip`을 생성하세요. ad-hoc 빌드 결과를 공증된 결과로 소개하지 않습니다.

이 앱은 의도적으로 App Sandbox를 사용하지 않습니다. 앱과 필요할 때 실행되는 정리기가 같은 Application Support 라이브러리를 사용합니다.

## 릴리스 준비

사용자가 릴리스를 결정한 경우에만 버전·빌드 번호를 변경합니다. `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `scripts/build-local-app.sh`의 기본값을 함께 맞춥니다. 일반 수정이나 미리보기 때문에 버전을 올리지 않습니다.

```sh
swift build --disable-keychain
scripts/run-core-checks.sh
scripts/check-update-preferences.sh
scripts/prepare-release.sh
```

`prepare-release.sh`는 빌드·DMG·ZIP을 만들고 **appcast.xml을 변경**합니다. 앱을 검토하는 단계에서는 실행하지 마세요. 자동 커밋·푸시·릴리스 발행은 하지 않습니다.

Sparkle EdDSA 키는 Apple 인증서와 별개입니다. `PaperLibrary/Info.plist`에 공개 키가 있고, 개인 키 기본 위치는 다음과 같습니다.

```text
~/Library/Application Support/Paper Library Development/sparkle-private-key
```

개인 키를 저장소나 릴리스에 넣지 마세요. 다른 Mac에서는 안전하게 복원한 키를 `SPARKLE_PRIVATE_KEY_FILE`로 지정할 수 있습니다. 생성기는 키가 앱의 공개 키와 일치하는지 확인하고 ZIP·appcast를 서명합니다. 기존 사용자의 신뢰를 깨는 키 교체를 임의로 하지 않습니다.

승인된 릴리스에는 검증한 **DMG와 정확히 그때 만든 `Paper-Library.zip` 두 파일**을 올립니다. appcast는 ZIP을 계속 가리킵니다. 서명 후 ZIP이나 appcast를 임의로 교체하지 않습니다. Sparkle을 포함하지 않았던 이전 버전은 한 번 수동 설치가 필요합니다.

## 릴리스 문구

[릴리스 문구 기준과 초안](RELEASE_NOTES.md)을 GitHub 릴리스 본문에 사용합니다. 한 문장 요약, 주요 변경 3~5개, 필요한 설치·업데이트 안내로 구성하고 같은 버전 제목을 본문에 반복하지 않습니다. 별도 Markdown 파일을 릴리스 첨부 자산으로 올리지 않습니다.

## 배포 전 확인

- 새 설치: 첫 화면의 저장 위치·Documents 권한 안내, 거절 후 재시도, Codex 설정을 확인합니다.
- 기존 설치: 논문·목록·설정이 유지되고 초기 안내가 다시 나타나지 않는지 확인합니다.
- Finder 서비스: 일회용 PDF로 이동을 확인하고 앱 창·업데이트 창 없이 정리기가 종료되는지 확인합니다.
- 업데이트: 알림 체크가 재실행 후 유지되고 자동 설치와 독립적인지 확인합니다. 새 버전 확인·네트워크 실패·서명 실패·실제 교체는 릴리스용 테스트 환경에서 확인합니다.
- DMG: 응용 프로그램으로 드래그한 앱을 열어봅니다. 서명·공증 검사는 배포 유형에 맞게 수행합니다.

저장 PDF는 `~/Documents/Paper Library/Papers`, 카탈로그와 설정은 `~/Library/Application Support/Paper Library`에 있습니다. Spotlight 검증은 해당 PDF 폴더만 대상으로 하고 전체 볼륨 재색인을 하지 않습니다.
