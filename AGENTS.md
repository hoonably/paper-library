# 작업 규칙

## 릴리스 서명과 버전

- 사용자 릴리스 요청 때는 `release.json`의 표시 버전과 항상 증가하는 빌드 번호를 사용한다. 버전 표시를 바꿔도 빌드 번호를 되돌리지 않는다.
- MacBook·Mac mini 어디서 요청하든 `signed-release.yml` 중앙 워크플로로 빌드·서명한다. 키는 저장소 Actions의 `SPARKLE_PRIVATE_KEY`, 공개키는 `release.json`의 `public_key_file`로 고정한다. 개인키를 새로 만들거나 공개키를 자동 교체하지 않는다.
- `python3 scripts/release.py prepare`, `status`, `download`, `stage`, `publish` 순서로 진행한다. 배포된 버전은 덮어쓰지 않는다. baseline/history reset은 사용자가 명시적으로 승인한 v1.0.0 재출시 때만 허용한다.
- 실제 설치 파일과 업데이트 파일이 같은 앱인지, 다음 버전의 다운로드·서명·임시 앱 교체와 변조 거절이 통과해야 공개한다. 검증은 일회용 앱/고유 설정에서만 하고 사용자 앱·데이터는 변경하지 않는다.
- 설치 자산을 올리고 익명 다운로드·서명을 확인한 다음 appcast를 마지막에 게시한다. 비공개 소스는 공개하지 않는다. Pickly·Talk Zero의 Releases는 원래 비공개 저장소에 기록하고, 기존 Cloudflare Pages에 익명 다운로드와 서명된 피드를 게시한다. 별도 공개 저장소를 만들지 않는다.

- 릴리스 본문은 제품 소개 한 문장만 쓴다. 기능 목록·지원 환경·버전 반복·DMG 설치법·내부 서명 이력을 넣지 않는다.
- 공개 Releases에 체크섬 TXT를 첨부하지 않는다. 내부 해시·서명·익명 다운로드 검증은 유지한다.
