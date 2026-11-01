# 사이트 기능 캡처

| 파일 | 웹용 해상도 | 화면 |
| --- | --- | --- |
| `images/finder-move-to-paper-library.png` | 2064 × 1188px | Finder에서 PDF를 Paper Library로 보내기 |
| `images/app-overview.webp` | 3200 × 1944px | 제목·분야·핵심 요약으로 논문을 찾아보기 |
| `images/feature-edit-paper.webp` | 1496 × 1100px | 논문 정보 편집기에서 분야·저자·요약 수정하기 |

Finder에는 기존에 검토한 2064 × 1188px 원본 캡처를 사용했습니다. 더 큰 실제 원본이 없어 이미지를 확대하지 않고 유지했습니다. 논문 목록은 Attention Is All You Need, ResNet, AlexNet, BERT, Adam, GAN, VAE 등 공개된 대표 논문의 예시 카탈로그입니다.

논문 목록은 현재 앱의 실제 뷰를 독립 미리보기 앱에서 4배로 렌더링했습니다. 목록의 1600 × 972pt를 6400 × 3888px로 출력했습니다. SwiftUI 표시 배율과 텍스트 그리기 레이어 배율을 4×로 설정해 글리프를 다시 그렸습니다.

사이트의 기능별 화면에 쓰는 논문 목록은 6400 × 3888px 마스터 PNG를 Lanczos 방식으로 3200 × 1944px로 축소한 뒤 무손실 WebP로 인코딩했습니다.

편집 화면에는 앱의 `PaperEditorView`에 *Attention Is All You Need*의 예시 데이터를 넣었습니다. 748 × 550pt 편집 영역을 2배 해상도로 캡처한 뒤 무손실 WebP로 저장했습니다. 미리보기는 메모리에서만 동작합니다.

저장소 README는 웹사이트의 논문 서가에서 *Attention Is All You Need* 요약을 펼친 화면을 사용합니다. 이미지는 `.github/site-preview.webp`입니다.
