# 사이트 기능 캡처

| 파일 | 웹용 해상도 | 화면 |
| --- | --- | --- |
| `images/finder-move-to-paper-library.png` | 2064 × 1188px | Finder에서 PDF를 Paper Library로 보내기 |
| `images/app-overview.webp` | 3200 × 1944px | 제목·분야·핵심 요약으로 논문을 찾아보기 |
| `images/feature-local-storage.webp` | 1840 × 1680px | PDF와 앱 데이터가 이 Mac에 저장되는 위치 확인하기 |

Finder에는 기존에 검토한 2064 × 1188px 원본 캡처를 사용했습니다. 더 큰 실제 원본이 없어 이미지를 확대하지 않고 유지했습니다. 논문 목록은 Attention Is All You Need, ResNet, AlexNet, BERT, Adam, GAN, VAE 등 공개된 대표 논문의 예시 카탈로그입니다.

논문 목록과 저장 위치 화면은 현재 앱의 실제 뷰를 독립 미리보기 앱에서 4배로 다시 렌더링했습니다. 목록은 1600 × 972pt를 6400 × 3888px로, `Library & access` 설정은 460 × 420pt를 1840 × 1680px로 출력했습니다. SwiftUI 표시 배율과 텍스트 그리기 레이어 배율을 4×로 설정해 글리프를 다시 그렸습니다.

사이트와 README용 논문 목록은 6400 × 3888px 마스터 PNG를 Lanczos 방식으로 3200 × 1944px로 축소한 뒤 무손실 WebP로 인코딩했습니다. 저장 위치 화면은 1840 × 1680px를 그대로 무손실 WebP로 인코딩했습니다. 고해상도 마스터는 캡처 작업 폴더에 보관하며, 비트맵을 확대하거나 UI를 합성하지 않았습니다. 미리보기 앱은 메모리에서만 예시 카탈로그를 구성하고, 실제 PDF·사용자 라이브러리·자동화 설정은 변경하지 않습니다.
