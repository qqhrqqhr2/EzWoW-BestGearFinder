# v2.0.18

### 한국어
- 데이터 공유 현황 창을 추가했습니다. `/공유` 또는 `/ezshare`로 열면 받은 기록, 보낸 사람, 보낸 기록, 종류별 현황과 새로 받은 기록만 따로 볼 수 있습니다.
- 공유 데이터를 채널로도 보내 더 빨리 퍼지게 했습니다.
- 데이터 채널의 사용자 명단이 새로 갱신되지 않아 일부 사용자와 귓속말로 공유 기록을 주고받지 못하던 문제를 고쳤습니다.
- 퀘스트 보상, 트레이너가 가르치는 주문, 오브젝트 이름도 다른 사용자와 공유합니다.
- 게임패드: 전투가 끝나면 EzWoW 창이 패드 조작을 가져가던 문제를 고쳤습니다. 전투 전에 EzWoW 창을 조작하던 경우에만 되돌립니다.
- 직접 기록한 획득처가 하나도 없으면 다른 사용자가 공유한 획득처가 목록·검색·툴팁에 나오지 않던 문제를 고쳤습니다. 공유받은 획득처에 "(직접 확인)"이 붙던 것도 고쳤습니다.
- 획득처 목록을 만드는 동안 얻은 장비를 모두 "획득처를 기록했습니다"로 알리고 저장하던 문제를 고쳤습니다.
- 언어를 바꾸면 아이템 검색 창이 비어 버리던 문제를 고쳤습니다.
- 착용 미리보기 칸 툴팁에서 "클릭: 다른 순위 고르기" 줄이 사라지던 문제를 고쳤습니다.
- 툴팁의 긴 획득처 줄이 "…"로 잘리던 문제를 고쳤습니다. 긴 줄은 여러 줄로 나눠 보여 줍니다.
- 다른 언어에서 일부 지역 이름(달라란 등)이 한국어로 나오던 문제를 고쳤습니다.
- 공유 기록을 설치된 EzWoW 애드온 중 최대 2개에만 저장해 접속·다시 불러오기가 빨라지고 저장 파일이 작아집니다. 업데이트 후 게임을 한 번 완전히 다시 시작하면 적용됩니다.

### English
- Added a data sharing window. Open it with `/ezshare` to see received records, players, sent records, totals by kind, and only the newly received records.
- Shared data is now also sent through the channel, so it spreads faster.
- Fixed shared records not being exchanged by whisper with some players because the data channel's player list was not refreshed.
- Quest rewards, trainer spells and object names are now shared with other players too.
- Gamepad: EzWoW windows no longer take over the pad after combat; it returns only if you were using an EzWoW window before the fight.
- Fixed sources shared by other players not showing in the list, search and tooltips until you had recorded one yourself. Shared sources no longer say "(seen by you)".
- Fixed every piece of looted gear being announced and saved as a new source while the source list was still being built.
- Fixed the item search window going blank after changing the language.
- Fixed the "Click: pick another rank" line disappearing from try-on slot tooltips.
- Fixed long source lines in tooltips being cut with "…"; they are now split into several lines.
- Fixed some zone names (Dalaran and others) showing in Korean in other languages.
- Shared records are now saved by at most 2 of your installed EzWoW addons, so logins and reloads are faster and save files smaller. Takes effect after one full game restart following the update.
