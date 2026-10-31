# 서명된 Mac 앱 릴리스

## 두 Mac의 같은 업데이트 체인

`release.json`이 버전·빌드·Bundle ID·배포 저장소·공개키 경로의 기준이다. 앱별 Ed25519 키를 유지하며 MacBook과 Mac mini의 같은 키를 검증했다. 로컬 키는 앱별 Application Support 폴더(0600)와 로그인 Keychain에 보관하고 Git에는 공개키만 둔다. 중앙 빌드는 저장소 Actions secret `SPARKLE_PRIVATE_KEY`를 사용하므로 어느 Mac에서 요청하든 서명 주체가 같다. 키가 없거나 공개키와 다르면 생성·교체하지 않고 실패한다.

## 다음 버전 준비

1. `release.json`의 `version`과 `build`를 올린다. build는 직전 appcast보다 커야 한다.
2. 변경을 검사·커밋하고 main에 푸시한다.
3. 아래 명령으로 중앙 서명 빌드를 요청한다. `GH_TOKEN` 또는 기존 Git credential helper의 로그인 정보만 사용하며 토큰을 소스에 저장하지 않는다.

```sh
python3 scripts/release.py prepare
python3 scripts/release.py status
python3 scripts/release.py download
python3 scripts/release.py stage
python3 scripts/release.py publish
```

워크플로 성공 뒤 download가 검증된 파일을 받는다. stage는 비공개 draft에 자산을 준비하고 기존 릴리스를 보존한다. publish는 익명 다운로드와 서명을 다시 검사하고 피드를 마지막에 게시한다. 일반 릴리스는 기존 버전·태그를 덮어쓰지 않는다. 소스가 비공개인 앱은 `repository`에 지정된 공개 배포 전용 저장소만 사용한다.

## 필수 검증

- 고정된 공개키와 개인키 일치, 키 유실·불일치 시 중단
- DMG와 업데이트 ZIP 안의 앱·Bundle ID·버전·빌드·서명 일치
- 실제 Sparkle을 통한 다음 버전 발견·다운로드·검증·일회용 앱 교체
- 변조한 피드와 설치 파일 거절
- 공개 다운로드 파일의 SHA-256·EdDSA 서명, 피드 게시 순서

새 버전 검사와 알림은 사용자 설정을 따르며, 자동 설치 동의를 임의로 켜지 않는다. 테스트 후보는 no-op 실행 파일과 고유 임시 Bundle ID를 사용하므로 사용자 앱·사진·논문·녹음·카카오톡은 실행하거나 수정하지 않는다.

Apple Developer ID 코드 서명·공증은 Sparkle 업데이트 서명과 별개다. 현재 중앙 배포는 기존 ad-hoc 정책을 명시적으로 사용해 각 Mac의 개발 인증서를 자동 선택하지 않는다. Developer ID를 도입할 때는 중앙 배포 환경의 동일 인증서·공증 자격증명으로만 전환한다. 공증되지 않은 결과를 공증된 결과로 표시하지 않는다.
