Korea Projection 1.7.2.2 - 그랜저 IG Wi-Fi 초기화 제한 복구 시험판
대상: IGPEHEV.KOR.*.260902 / IGPE21.KOR.*.260902

원래 1.7.2에서 Wi-Fi 초기화가 실패하는 차의 시험용입니다. 하드웨어 수리나 성공을 보장하지 않습니다.
K3 TBT 시험판과는 별도입니다. 원래 상태 앱·무선 모드 2.4.0의 서명을 유지합니다.

1. FAT32 USB 맨 위에 이 ZIP의 내용물을 복사합니다. packages/korea.projection.zip은 풀지 않습니다.
2. 기존 원래 Korea Projection 1.7.2 위에 NEMESIS의 일반 업데이트 방식으로 설치합니다.
3. 인포를 NEMESIS로 재부팅합니다. HMG-API 모드를 따로 설치하지 않습니다.
4. 정차 상태로 기다립니다. 부팅 4분 이후, 실패 근거가 있는 경우에만 최대 3회 복구합니다.
   명령이 멈추거나 두 부팅 연속 실패하면 다음 자동 시도를 차단합니다. 블루투스가 잠시 끊길 수 있습니다.
5. 복구 후에는 wlan0만이 아니라 Launch의 핫스팟·DHCP와 실제 CarPlay 연결까지 확인합니다.
6. 재부팅하기 전에 Launch로 진단 파일을 저장합니다. 공개용 KoreaProjection-report의 파일 3개만 보냅니다.

중단: recovery-controls/kp-ig-wifi-off를 USB 맨 위로 복사합니다.
상세 동작·재설정·제한·원복은 IG-WIFI-GUIDE.md를 읽어 주세요.
원복: NEMESIS에서 시험판 Korea Projection 삭제 > 인포 재부팅 > 원래 1.7.2 전체 묶음 설치 > 설정 대기 > 재부팅.

K3 시험판 등 다른 서명 모드를 쓰고 있다면 그 시험판의 원복 절차로 원래 1.7.2를 먼저 복구합니다.
