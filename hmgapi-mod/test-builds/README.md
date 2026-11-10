# K3 BD PE 시동 재개 TBT 시험판

**차량에는 [Korea Projection 전체 USB 시험판 1.7.2.1](korea-projection-1.7.2.1-usb.zip)을 사용하세요.**

- 설치: NEMESIS에서 기존 Korea Projection 삭제 → 인포 재부팅 → 전체 USB 묶음 설치 → 자동 설정 대기 → 인포 재부팅.
- 수정 무선 모드 2.4.1-k3-test.1은 자동 설치됩니다. HMG-API 모드를 별도로 설치하지 않습니다.
- 서명된 상태 앱과 K3용 BusyBox·라이선스는 원래 배포본 그대로 포함했습니다.
- [설치·원복·시험 안내](../../docs/k3-bdpe-tbt-resume-test.md).
- [원복용 원래 1.7.2 전체 USB](korea-projection-1.7.2-original-usb.zip).
- `wireless-carplay-aa-2.4.1-k3-test.1.zip`은 모드 개발용 단독 산출물입니다. 전체 USB 설치 사용자는 따로 설치할 필요가 없습니다.
- 개발 모드 서명 UUID: `aac70953-ee5d-8d38-a7c6-7834f9cbccf9`. 개인 키는 저장소에 없습니다.
- 대응 소스: HMG-API `b02a1417c485ca8545293dc2b9230f1d3e0c11ec` + [패치](../patches/0001-carplay-guidance-resume.patch).
- 전체 USB 재빌드: `bash scripts/build-k3-test-usb.sh /outside/repo/output`.

호스트 검증을 통과한 시험판입니다. 실제 K3에서 나침반 복귀까지 해결되는지는 차량 시험이 필요합니다.
