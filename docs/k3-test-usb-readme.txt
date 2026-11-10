Korea Projection 1.7.2.1 - K3 BD PE TBT 시동 재개 시험판
포함 무선 모드: 2.4.1-k3-test.1

이 묶음 전체를 사용합니다. HMG-API 무선 모드 ZIP을 따로 설치하지 않습니다.

중요: 최초 교체 전에 아래 1~2번을 먼저 끝내세요.
1. USB를 꽂지 않은 상태에서 NEMESIS Manager > My Packages > Korea Projection을 삭제합니다.
   함께 설치한 HMG-API 무선 모드 삭제가 완료됐는지 삭제 출력을 확인합니다.
   '모드 지우기 실패', '데몬 응답 없음', '적용 필요'가 나오면 설치를 진행하지 말고 출력 내용을 확인합니다.
2. NEMESIS의 재부팅으로 인포를 재부팅합니다. 시동 OFF/ON만으로 대신하지 않습니다.
3. FAT32 USB 맨 위에 이 ZIP 안의 파일·폴더를 복사합니다.
   NEMESIS.data, README.txt, BUSYBOX-LICENSE.txt, TEST-GUIDE.md, packages 폴더가 바로 보여야 합니다.
   packages/korea.projection.zip은 풀지 않습니다.
4. 내비 화면이 다 뜨면 USB를 꽂고 NEMESIS 설치 질문에 '예'를 선택합니다.
5. 설치 후 USB를 빼고 3~5분 기다립니다. Korea Projection의 Launch에서 진행 상태를 확인합니다.
6. 재부팅 안내가 나오면 NEMESIS로 인포를 재부팅합니다.
7. Launch에 패키지 1.7.2.1, HMG-API 무선 모드에 2.4.1-k3-test.1이 설치됐는지 확인합니다.
   상태 앱 자체의 버전이 1.7.2로 표시되는 것은 정상입니다. 원래 서명된 앱을 유지했습니다.

HMG-API 앱 자체는 삭제하지 않습니다. 기존 버전 위에 바로 업데이트하면 모드 서명이 달라 교체되지 않을 수 있습니다.
이 시험판과 원래 배포 모드의 서명은 다릅니다. 서명 검사를 끄거나 강제로 덮어쓰지 않습니다.

시험: CarPlay 네이버 지도 안내 > 시동 OFF > 기존 문제가 발생했던 시간 후 ON > 이전 TBT 잔상·나침반 복귀 확인.
결과 기록·로그·주의점은 TEST-GUIDE.md를 참고하세요. 실제 차량에서의 해결 여부는 아직 검증 전입니다.

원복: NEMESIS에서 이 시험판 Korea Projection 삭제 > 인포 재부팅 > 원래 1.7.2 전체 USB 묶음 설치 > 자동 설정 대기 > 인포 재부팅.
