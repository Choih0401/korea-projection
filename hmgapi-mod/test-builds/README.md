# K3 BD PE TBT 시동 재개 시험판

- `wireless-carplay-aa-2.4.1-k3-test.1.zip`: **HMG-API 모드 ZIP**. NEMESIS 패키지가 아닙니다.
- 개발 서명 UUID: `aac70953-ee5d-8d38-a7c6-7834f9cbccf9`.
- 원래 모드와 키가 다르므로 삭제·적용 후 교체 설치가 필요합니다. 개인 키는 이 저장소에 없습니다.
- [설치·원복·시험 안내](../../docs/k3-bdpe-tbt-resume-test.md)를 먼저 확인하세요.
- 대응 소스: HMG-API `b02a1417c485ca8545293dc2b9230f1d3e0c11ec` + [패치](../patches/0001-carplay-guidance-resume.patch).
- 재빌드: `bash scripts/build-tbt-resume-test.sh /outside/repo/author.key /outside/repo/output`.
- `SHA256SUMS`의 ZIP 해시와 압축 안 `hooks.jar` 해시를 각각 확인할 수 있습니다.
- 원복용 공식 2.4.0 ZIP: [기존 배포 모드](../../nemesis-pkg/korea.projection/hmgapi/wireless-carplay-aa.zip).

이 시험판은 호스트 테스트·Android DEX 빌드·모드 서명·ZIP 무결성을 검증했습니다. 실제 K3에서 나침반 복귀까지 해결되는지는 사용자 차량 시험이 필요합니다. 원래 Korea Projection 배포 묶음은 변경하지 않았습니다.
