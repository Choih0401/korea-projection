# K3 BD PE: 시동 재개 후 CarPlay TBT 잔상 시험

대상: Korea Projection **1.7.2**, K3 **BD PE**. 현상은 네이버 지도 CarPlay 안내 후 시동을 껐다 켜면 경로는 없지만 계기판 안내가 남고 나침반으로 돌아오지 않는 것. NEMESIS의 인포 재부팅으로 해소됨.

이 브랜치는 **Korea Projection 전체 USB 시험판 1.7.2.1**을 제공합니다. 수정 무선 모드 **2.4.1-k3-test.1**을 안에 넣고, 자동 설치용 모드 버전과 체크섬을 함께 반영했습니다. 상태 앱과 K3용 ARM BusyBox는 원래 1.7.2 릴리스의 것을 그대로 포함합니다. 상태 앱 자체의 버전은 1.7.2로 유지되지만 패키지 버전은 1.7.2.1입니다. 실제 차량에서의 해결 여부는 아직 검증하지 않았습니다.

## 수정 소스

바탕은 `StopDragon/HMG-API`의 `b02a1417c485ca8545293dc2b9230f1d3e0c11ec`. 변경은 [소스 패치](../hmgapi-mod/patches/0001-carplay-guidance-resume.patch)에 들어 있습니다. `scripts/build-tbt-resume-test.sh`는 고정 커밋의 소스 체크섬을 확인하고 패치를 적용한 뒤 테스트·컴파일·서명 검증까지 합니다. 대응 소스는 AGPL-3.0이며 기존 저작권 고지를 유지합니다.

- `Dipo.java`: 세션 종료, iAP2 서비스/리스너 해제, 화면 켜짐 때 실제 DiPO 연결·안내 상태 재확인. 화면 이벤트가 빠져도 5초 주기로 확인하며, 메모리에 CP 안내가 없으면 상태 조회를 하지 않습니다. `SCREEN_ON`을 차량 재개의 증거로 가정하지 않습니다.
- `GuidanceSession.java`: 최소 2초 간격의 두 번의 일치하는 관측과 마지막 세션/메시지 후 5초 유예를 요구합니다. 새 세션·새 메시지는 이전 종료 확인을 무효화합니다. 연결이 살아 있고 안내 중이거나 연결 상태를 알 수 없으면 삭제하지 않습니다. Android Auto 안내 중에도 삭제하지 않습니다.
- `CpTurns.java`: 5분 무응답 때 실제 세션 상태 확인을 요청합니다. 무응답만으로 정상 안내를 지우지 않습니다. 종료 확인 후 경로 캐시·회전·남은 거리/시간·목적지·HUD를 정리하고 순정 내비에 복귀 확인을 요청합니다.
- `Wireless.java` / `GuidanceGate.java` / `StockReplay.java`: 연결이 확실히 끝났다면 오래된 CarPlay TBT 플래그가 순정 내비 호출을 계속 막지 않게 합니다. 종료 통지를 받아도 순정 내비 프로세스에서 다시 상태를 확인합니다. 다음 순정 호출이 없어도 기존 복귀 타이머를 시작하며, 새 폰 안내가 있으면 복귀를 취소합니다. 마지막으로 관측한 순정 프레임만 다시 보내고 나침반 값을 임의로 만들지 않습니다.

보통 재개 후 두 번의 종료 확인, 순정 내비 쪽 최대 2초의 연결 확인과 최대 6초의 순정 프레임 복귀 대기가 필요합니다. 화면 켜짐 이벤트 누락 시 5초 감시 주기가 더해집니다. 연결 조회가 계속 실패하거나 순정 상태 자체가 연결 중으로 고착되면 이 수정만으로 해결되지 않을 수 있습니다. 이 경우 아래 로그가 필요합니다.

## 설치: 전체 USB 묶음 사용

[전체 USB 시험판 다운로드](../hmgapi-mod/test-builds/korea-projection-1.7.2.1-usb.zip). **별도의 HMG-API 모드 ZIP 설치는 필요 없습니다.**

이 모드의 개발 서명 UUID는 `aac70953-ee5d-8d38-a7c6-7834f9cbccf9`로 원래 배포자의 키와 다릅니다. 따라서 최초 교체는 기존 Korea Projection을 지운 뒤 전체 묶음을 새로 설치해야 합니다. 서명 검사를 우회하거나 기존 모드 위에 강제로 덮어쓰지 않습니다.

1. **USB를 꽂지 않은 상태에서** NEMESIS Manager → My Packages → **Korea Projection**을 삭제합니다. HMG-API 앱 자체를 삭제하지 않습니다.
2. 삭제 출력에서 함께 설치했던 HMG-API 무선 모드의 삭제가 완료됐는지 확인합니다. `무선 모드 지우기 실패`, `데몬 응답 없음`, `적용 필요`가 나오면 다음 설치를 진행하지 말고 출력을 확인합니다. 본인이 별도로 설치했던 모드는 기존 삭제 로직이 보존하므로, 그런 경우에도 먼저 현재 상태를 확인해야 합니다.
3. NEMESIS의 재부팅으로 인포를 재부팅합니다. 시동 OFF/ON만으로 대신하지 않습니다.
4. FAT32 USB 맨 위에 전체 ZIP 안의 파일·폴더를 복사합니다. `NEMESIS.data`, `README.txt`, `BUSYBOX-LICENSE.txt`, `TEST-GUIDE.md`, `packages/korea.projection.zip`이 있어야 하며, 안쪽 패키지 ZIP은 풀지 않습니다.
5. 내비 화면이 다 뜨면 USB를 꽂고 NEMESIS 설치 질문에 **예**를 선택합니다.
6. 설치 후 USB를 빼고 **3~5분** 기다립니다. Korea Projection의 **Launch**에서 자동 설치 진행을 확인합니다.
7. 재부팅 안내가 나오면 NEMESIS로 인포를 재부팅합니다.
8. 패키지 **1.7.2.1**, 무선 모드 **2.4.1-k3-test.1**을 확인합니다. 상태 앱 버전이 **1.7.2**인 것은 정상입니다.

기존 자동 설치 모드는 Korea Projection의 삭제 절차가 정리하고, 새 모드는 새 패키지의 자동 설정이 설치합니다. 기존 차 지도는 삭제하지 않습니다. 동일 시험판을 다시 설치할 때는 같은 시험 서명 키를 사용하지만, 최초 공식판↔시험판 전환에는 위 삭제·재설치 순서를 사용합니다.

## 차량 시험

먼저 정차 상태에서 시험합니다. 인포 전체 재부팅 직후 정상 상태를 확인하고 다음 순서를 최소 3회 반복합니다.

1. CarPlay 연결 → 네이버 지도 경로 안내 → 계기판 TBT 확인.
2. 안내를 직접 종료하지 않은 채 시동을 끕니다.
3. 기존 문제가 발생했던 것과 같은 대기 후 시동을 켭니다. 완전 재부팅 여부도 기록합니다.
4. CarPlay 연결 여부, 폰 경로 유무, 계기판 잔상 유무, 나침반 복귀 여부 및 걸린 초를 기록합니다. CarPlay가 다시 연결되면 경로가 실제로 살아 있는지 구분합니다.
5. CarPlay를 재연결하고 새 경로를 시작해 이전 종료 작업이 새 안내를 지우지 않는지 확인합니다.

함께 확인할 경우:

- 정상적인 네이버 지도 안내 종료 → 회전·거리·목적지 잔상 없음.
- 짧은 무선 재연결 → 살아 있는 경로가 갑자기 지워지지 않음.
- 안내 갱신이 적은 긴 구간 → 5분이 지났다는 이유만으로 안내가 지워지지 않음.
- 순정 내비로 전환 → 순정 안내 복귀. 사용 가능하다면 Android Auto로 전환해 안내가 지워지지 않는지도 확인.

## 로그와 이슈 초안

문제 재현 또는 개선 확인 **직후, 인포를 재부팅하기 전에** USB를 꽂고 Korea Projection의 Launch로 제보 파일을 저장합니다. 저장 완료 후 `1-report.md`, `2-car-report.json`, `3-log.txt`를 확인합니다. 비공개 디버그 파일은 공개 이슈에 올리지 않습니다.

수정 모드가 남기는 핵심 줄:

- `CarPlay: stale guidance cleared reason=... connected=... guiding=...`
- `CarPlay: turn-by-turn cleared, ...`
- `navigation: stock cluster values resent after phone guidance, round ...`
- `CarPlay guidance state unavailable` (상태 조회 실패 시)

이슈 본문 예시:

```text
차량: K3 BD PE
내비 펌웨어:
Korea Projection: 1.7.2.1 (상태 앱 1.7.2)
HMG-API:
무선 모드: 2.4.1-k3-test.1 (aac70953-ee5d-8d38-a7c6-7834f9cbccf9)
iOS / 네이버 지도 버전:

재현: CarPlay 네이버 지도 안내 → 시동 OFF → __초 대기 → 시동 ON (인포 완전 부팅 아님)
재개 직후 CarPlay 연결: O/X
폰에 실제 경로: O/X
기존 2.4.0: 이전 TBT 유지, NEMESIS 재부팅 시 정상
테스트 모드 결과: __회 중 __회 나침반 복귀, 약 __초
새 경로 재연결 / 순정 내비 전환 결과:
첨부: 공개용 제보 파일 3개
```

## 원복

[원래 1.7.2 전체 USB 묶음](../hmgapi-mod/test-builds/korea-projection-1.7.2-original-usb.zip)을 제공합니다. 원본은 StopDragon/korea-projection v1.7.2 공개 릴리스이며 SHA-256 `628d274f0e7f862e01cf31cc28085d9f2ad6a583c3d8eee60f17b935dedfd666`으로 확인했습니다.

**NEMESIS에서 시험판 Korea Projection 삭제 → 인포 재부팅 → 원래 1.7.2 전체 USB 묶음 설치 → 자동 설정 대기 → 인포 재부팅** 순서입니다. HMG-API 앱에서 모드를 따로 교체하거나 순정 파일을 직접 수정할 필요는 없습니다. 시험판 삭제에서 모드 삭제 실패 등이 나타나면 진행 전에 출력을 확인합니다.

## 호스트 검증과 재빌드

서명용 키는 저장소 밖에 보관합니다. 키를 새로 만들면 UUID도 달라지므로 자체 빌드의 UUID를 위 설치 안내와 혼동하지 마세요.

```sh
# JDK 및 Android SDK build-tools 37.0.0 / android-19 플랫폼이 준비된 Linux에서
export ANDROID_HOME=/path/to/android-sdk
bash scripts/build-tbt-resume-test.sh /outside/repo/mod-author.key /outside/repo/build-output
```

서명 키 생성은 대응 HMG-API 소스의 `hmgapi.engine.Signing keygen`을 사용합니다. 빌드 스크립트는 기존 키를 요구하며 키를 출력하거나 저장소로 복사하지 않습니다. 출력 모드 ZIP의 서명과 압축 무결성을 검사하고 `SHA256SUMS`와 테스트 로그를 만듭니다. 이 명령은 모드 개발용이며, 차량 설치용 전체 USB 묶음은 아래 명령으로 만듭니다.

```sh
bash scripts/build-k3-test-usb.sh /outside/repo/usb-output
```

이 명령은 원래 1.7.2 전체 릴리스를 고정 SHA-256으로 검증한 뒤 서명된 앱·ARM BusyBox·라이선스 파일을 유지하고 현재 저장소의 수정 모드·서비스 체크섬·패키지 버전을 합칩니다. 완성된 USB 안의 모든 단계와 모드 서명을 검사하고, 기존 모드 자동 삭제→새 모드 자동 설치→재실행 시 중복 설치 방지를 모의 플랫폼으로 검사합니다. 원복용 원래 전체 USB ZIP도 출력합니다.

호스트 검증 결과: 기존 CarPlay 200개 + 종료 판정/재개/복귀 회귀 검증 50개 + 기존 Android Auto·순정 복귀·막대 등 177개, 총 **427개 통과**. Android API 19 대상 DEX 빌드, HMG-API 서명 검증, ZIP 무결성 검사도 통과했습니다. 차량 시험은 미실행입니다.

전체 패키지 추가 검증: 원래 서명된 APK의 바이트 동일성과 API 19 서명 검증, BusyBox 바이너리·실행 권한·라이선스, NEMESIS→자동 설치→모드 버전/MD5 연결, 모드 ECDSA 서명/각 파일 SHA-256, 자동 삭제·신규 설치·반복 실행 시 중복 설치 방지 3개 시나리오 통과. 차량 시험은 미실행입니다.
