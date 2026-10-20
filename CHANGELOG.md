# Changelog - EzWoW - Best Gear Finder

## v2.0.0
- 드래그 시 마우스 포인터와 아이콘/프레임 좌표가 어긋나거나 벌어지는 스케일 오차(`EffectiveScale`) 및 초기 점프 현상 수정
- **아키텍처 재설계 및 모듈화 (`Core/`, `Data/`, `Modules/`, `UI/`)**:
  - `Core/Init.lua`(점수 계산 엔진 및 비동기 아이템 큐), `Core/Locales.lua`(8개 국어 사전), `Core/UIKit.lua`(공통 UI 프레임워크) 분리
  - `Modules/LiveLearner.lua`(실시간 전리품·퀘스트·상인 획득처 학습기), `Modules/TooltipHook.lua`(툴팁 점수·획득처 훅) 모듈화
  - `UI/MainWindow.lua`, `UI/SearchWindow.lua`, `UI/OptionsWindow.lua`, `UI/Launcher.lua` 계층 분리
- **신규 및 개선 기능**:
  - `EzWoW-MapFinder` 연동 추가: 추천 목록 및 검색 창에서 아이템 우클릭 시 월드맵에서 드랍 보스/퀘스트/상인 위치 즉시 검색
  - `EzWoWStyle` 골드(`#EFC55A`) 전용 설정창(`/ezbg config`) 및 블리자드 애드온 설정 런처 추가
  - 아이템 마우스오버 시 현재 착용 장비 비교 툴팁(`showEquipCompare`) 자동 표시 옵션 추가
  - 4단계 우선순위 비동기 아이템 조회 큐 및 역할별 점수 메모이제이션 캐시 적용으로 대량 검색 속도 개선
  - 슬래시 명령어 체계 정비 (`/ezbg`, `/bestgear`, `/내템`)

## v1.0.15
- 30레벨 PvE BiS 목록 및 대체 장비 업데이트 (전사, 성기사, 도적, 주술사, 드루이드 17개 진영/특성 조합)
- 신규 장비 ID 34종 및 드랍 출처 추가
- 마우스 휠 스크롤 속도 보정 (`Shift + 마우스 휠` 시 4배속 스크롤) 및 슬롯별 접기/펼치기(`+`/`-`) 헤더 개선
