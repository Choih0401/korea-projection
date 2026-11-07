# 고지 (NOTICE)

Korea Projection은 GNU AGPL-3.0입니다(`LICENSE`). 아래는 다른 프로젝트에서 가져오거나 바탕으로 삼은 부분과 그 원저작권입니다.

## NEMESIS (xwtk, AGPL-3.0)

- https://github.com/xwtk/hmg_nemesis
- Korea Projection은 NEMESIS 패키지(`korea.projection`)로 설치되고, NEMESIS의 패키지 형식(`NEMESIS.data`)과 서비스 실행 방식을 따릅니다.

## HMG-API (VysseCodes, AGPL-3.0)

- https://github.com/Open-HMG/HMG-API (예전 주소 `VysseCodes/HMG-API`)
- `nemesis-pkg/korea.projection/hmgapi/wireless-carplay-aa.zip`: HMG-API v1.0.2의 "Wireless CarPlay + Android Auto" 모드 2.1.0에 한국 차 데이터를 더하고 Korea Projection 개발 키로 다시 서명한 것입니다.
  - 바꾼 부분과 대응 소스, 다시 만드는 방법은 `hmgapi-mod/README.md`에 있습니다.
  - 1.5.6까지는 코드(`hooks.jar`)가 업스트림과 같습니다.
- `nemesis-pkg/korea.projection/hmgapi/maps/`: HMG-API 지도 형식의 차별 훅 지도입니다. HMG-API `tools/report-map.py`로 만들었습니다.
- `nemesis-pkg/app-src/java/korea/projection/app/QrCode.java`: HMG-API의 QR 코드 생성 코드에서 `package` 줄만 바꿨습니다.
- 1.5.7부터 모드 코드(`hooks.jar`, 모드 2.1.1)가 업스트림과 다릅니다. 소스는 포크 `StopDragon/HMG-API`의 `korea-build` 브랜치(업스트림 `v1.0.2`에서 시작)에 있습니다.
  - 업스트림 main의 커밋 `83eb4ef`(Narayan, "Fix CarPlay turns for left-hand traffic and omitted angles")를 그대로 가져왔습니다.
  - 계기판·HUD 회전 안내(`dipo/CpTurns.java`, `dipo/Dipo.java`)를 고쳤습니다. 바꾼 내용과 날짜는 파일 머리말 주석에 있습니다.

## HMG-Seogaemo (seogaemo, AGPL-3.0)

- https://github.com/seogaemo/hmg-seogaemo (커밋 `26eeb97e`)
- 1.5.7 모드의 `dipo/CpTurns.java`에 seogaemo의 `modules/wireless-carplay-and-aa/payload/src/hmgapi/mods/wireless/dipo/CpTurns.java.src`에서 다음을 옮겨 쓰고 HMG-API 구조에 맞게 고쳤습니다.
  - 아이콘 대체 규칙(`fallbackIcon`, `bandedTurn`, `roundaboutIcon`, 빈 아이콘 `NO_ICON`)
  - HUD 빈 목록, 앞쪽 회전 아이콘 47~50
  - 안내 상태 주기 재전송(refresh)과 HUD 목록 재전송
- 옮긴 부분은 소스 주석에 "from HMG-Seogaemo"로 표시했습니다.
