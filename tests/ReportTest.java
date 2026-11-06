package korea.projection.app;

/**
 * PC에서 상태 화면의 판단(Report)과 QR 크기를 시험한다. tests/stub-test.sh가 javac로 컴파일해 돌린다.
 * 실패하면 "FAIL ..."을 찍고 종료 코드 1.
 */
public class ReportTest {
    static int fails = 0;

    static void check(String name, boolean ok) {
        System.out.println((ok ? "ok   " : "FAIL ") + name);
        if (!ok) fails++;
    }

    static final String GOOD =
        "product=DEPEHEV.KOR.0000.V039.001.260902\n" +
        "targetdir=/system/onebin/depehev_kr\n" +
        "pkgver=1.4\ntested=yes\nhmgapi=version 1.0.2 build 180185d 2026-11-04\nnemesis=1.16.7\n" +
        "wp=no\nmod=yes\nmod_on=yes\nbridge=on\nhooks=on\nfeat_carplay=yes\nfeat_aa=yes\nfeat_wifi=no\nwlan0=yes\n" +
        "softap_strings=4\nssid_len=8\npass_len=12\nour_ap=yes\nour_dhcp=yes\nother_ap=no\nwpa=no\n" +
        "cp_conn=0\nmade=2026-11-06 06:00\n";

    static String row(Report r, String title) {
        for (String[] x : r.rows()) if (x[0].equals(title)) return x[1];
        return null;
    }

    public static void main(String[] a) throws Exception {
        Report r = Report.parse(GOOD);
        check("상태 파일 해석", "DEPEHEV.KOR.0000.V039.001.260902".equals(r.get("product")) && r.yes("our_ap"));
        check("모두 정상 → '준비됨', 초록", r.verdict().startsWith("무선 카플레이 준비됨") && r.level() == 0);
        check("연결 수가 있으면 → '연결됨'", Report.parse(GOOD.replace("cp_conn=0", "cp_conn=1")).verdict().equals("무선 카플레이 연결됨"));
        check("확인 안 된 차 → 대기 안내, 노랑", Report.parse(GOOD.replace("tested=yes", "tested=no")).verdict().startsWith("확인되지 않은 차") &&
            Report.parse(GOOD.replace("tested=yes", "tested=no")).level() == 1);
        check("무선 기능 꺼짐 → 빨강", Report.parse(GOOD.replace("feat_carplay=yes", "feat_carplay=no")).level() == 2);
        check("핫스팟 꺼짐 → 안내", Report.parse(GOOD.replace("our_ap=yes", "our_ap=no")).verdict().startsWith("핫스팟이 꺼져"));
        check("파일 없음 → 다시 눌러 달라는 안내", Report.parse(null).verdict().startsWith("상태를 읽지 못했습니다") && Report.parse(null).level() == 2);
        check("표는 15줄, 예/아니요로 표시", r.rows().size() == 15 && "예".equals(r.rows().get(1)[1]));
        check("정상이면 버전 칸은 버전만 (HMG-API 1.0.2, NEMESIS 1.16.7)", "1.0.2".equals(row(r, "HMG-API")) && "1.16.7".equals(row(r, "NEMESIS")));

        // 필요 조건: README "필요한 것"과 같은 최소 버전
        Report old = Report.parse(GOOD.replace("version 1.0.2 build", "version 1.0.1 build"));
        check("HMG-API 1.0.1 → '지원하지 않는 버전', 빨강", old.verdict().startsWith("지원하지 않는 HMG-API 버전") && old.level() == 2);
        check("  버전 칸에 '지원 안 함, 1.0.2 이상 필요'", "1.0.1 (지원 안 함, 1.0.2 이상 필요)".equals(row(old, "HMG-API")));
        Report beta = Report.parse(GOOD.replace("version 1.0.2 build", "version 1.0.0-beta.5 build"));
        check("  1.0.0-beta.5도 낮은 버전", beta.level() == 2 && row(beta, "HMG-API").contains("지원 안 함"));
        Report newer = Report.parse(GOOD.replace("version 1.0.2 build", "version 1.1.0 build"));
        check("  1.1.0은 통과 (1.0.10 > 1.0.2 같은 숫자 비교)", newer.level() == 0 && Report.older("1.0.10", "1.0.2") == 0 && Report.older("1.0.1", "1.0.10") == 1);
        Report none = Report.parse(GOOD.replace("hmgapi=version 1.0.2 build 180185d 2026-11-04\n", ""));
        check("HMG-API 없음 → 설치 안내, 빨강, '없음 (1.0.2 이상 필요)'", none.verdict().startsWith("HMG-API가 없습니다") && none.level() == 2 && "없음 (1.0.2 이상 필요)".equals(row(none, "HMG-API")));
        Report odd = Report.parse(GOOD.replace("version 1.0.2 build", "version dev build"));
        check("숫자가 아닌 버전 → '버전 확인 안 됨', 빨강 (멈추지 않음)", odd.level() == 2 && row(odd, "HMG-API").contains("버전 확인 안 됨"));
        Report nomod = Report.parse(GOOD.replace("mod=yes\nmod_on=yes", "mod=no\nmod_on=no"));
        check("무선 모드 없음 → 설치 안내, 빨강, '없음 (필요)'", nomod.verdict().startsWith("HMG-API 무선 모드가 없습니다") && nomod.level() == 2 && "없음 (필요)".equals(row(nomod, "HMG-API 무선 모드")));
        Report modoff = Report.parse(GOOD.replace("mod_on=yes", "mod_on=no"));
        check("무선 모드 꺼짐(11-06 시험 상태) → 켜기 안내, 빨강, '꺼짐 (켜야 함)'", modoff.verdict().startsWith("HMG-API 무선 모드가 꺼져") && modoff.level() == 2 && "꺼짐 (켜야 함)".equals(row(modoff, "HMG-API 무선 모드")));
        Report broff = Report.parse(GOOD.replace("bridge=on", "bridge=off"));
        check("Wireless CarPlay 설정 꺼짐 → 켜기 안내, 빨강", broff.verdict().contains("'Wireless CarPlay' 설정이 꺼져") && broff.level() == 2 && row(broff, "HMG-API 무선 모드").contains("설정 꺼짐"));
        check("정상이면 무선 모드 칸 '켜짐'", "켜짐".equals(row(r, "HMG-API 무선 모드")));
        Report oldfile = Report.parse(GOOD.replace("mod_on=yes\nbridge=on\n", ""));
        check("예전 상태 파일(mod_on·bridge 없음)도 초록, 칸은 '예'", oldfile.level() == 0 && "예".equals(row(oldfile, "HMG-API 무선 모드")));
        Report hoff = Report.parse(GOOD.replace("hooks=on", "hooks=off\nhookmap=mapped"));
        check("훅 꺼짐(mapped) → 'Check the map on this car' 안내, 노랑(지난 기록일 수 있음)", hoff.verdict().contains("Check the map on this car") && hoff.level() == 1 && row(hoff, "HMG-API 훅").startsWith("꺼짐 (mapped"));
        check("  none → 지도 없음 제보 안내", Report.parse(GOOD.replace("hooks=on", "hooks=off\nhookmap=none")).verdict().contains("지도가 없어"));
        check("  mismatch → 소프트웨어 불일치 안내", Report.parse(GOOD.replace("hooks=on", "hooks=off\nhookmap=mismatch")).verdict().contains("맞지 않아"));
        check("  상태 모름 → 껐다 켜기 안내", Report.parse(GOOD.replace("hooks=on", "hooks=off")).verdict().contains("마지막 부팅 기록"));
        check("확인 안 된 차는 HMG-API가 없어도 노랑(문구와 색이 맞음)", Report.parse(GOOD.replace("tested=yes", "tested=no").replace("hmgapi=version 1.0.2 build 180185d 2026-11-04\n", "")).level() == 1);
        Report hunk = Report.parse(GOOD.replace("hooks=on\n", "hooks=\n"));
        check("훅 기록 없음 → 판정에 쓰지 않고 '-'", hunk.level() == 0 && "-".equals(row(hunk, "HMG-API 훅")));
        Report nold = Report.parse(GOOD.replace("nemesis=1.16.7", "nemesis=1.15.2"));
        check("NEMESIS 1.15 → 업데이트 안내, 노랑", nold.verdict().startsWith("NEMESIS를 1.16 이상") && nold.level() == 1 && row(nold, "NEMESIS").contains("1.16 이상 필요"));
        check("wireless.projection 칸에 '필요 없음'", "아니요 (필요 없음)".equals(row(r, "wireless.projection")));

        String url = r.issueUrl();
        check("제보 링크: 우리 저장소의 양식", url.startsWith("https://github.com/StopDragon/korea-projection/issues/new?template=car-report.yml&title="));
        check("  양식 항목 product·report를 미리 채움", url.contains("&product=DEPEHEV.KOR.0000.V039.001.260902") && url.contains("&report="));
        check("  길이 " + url.length() + " <= " + Report.MAX_URL, url.length() <= Report.MAX_URL);
        check("  공백은 %20 (+ 아님)", !url.contains("+") && url.contains("%20"));
        String dec = java.net.URLDecoder.decode(url, "UTF-8");
        check("  요약에 길이만 있고 값은 없음", dec.contains("ssid_len: 8") && dec.contains("pass_len: 12"));
        check("  중요한 항목은 링크에 남음", dec.contains("feat_carplay: yes") && dec.contains("our_ap: yes") && dec.contains("targetdir: "));

        // 아주 긴 값이 와도 링크가 늘어나지 않는다
        StringBuilder big = new StringBuilder(GOOD);
        big.append("made=").append(new String(new char[2000]).replace('\0', 'x')).append('\n');
        String u2 = Report.parse(big.toString()).issueUrl();
        check("긴 값이 와도 링크 <= " + Report.MAX_URL + " (뒤 줄부터 뺌)", u2.length() <= Report.MAX_URL);

        QrCode q = QrCode.encode(url.getBytes("UTF-8"));
        QrCode q2 = QrCode.encode(u2.getBytes("UTF-8"));
        check("QR 버전 " + q.version + " (최대 길이 " + q2.version + ")", q2.version <= 18);
        // 화면 높이를 다 쓰는 정사각형(여백 12dp씩 뺌): 흔한 내비 화면 높이 480, 600, 720 px에서
        for (int h : new int[] { 480, 600, 720 }) {
            int side = h - 24;
            int[] f = Report.fit(side, q2.size);
            boolean inside = f[1] >= 0 && f[1] + f[0] * (q2.size + 8) <= side;
            check("화면 높이 " + h + "px: 칸 " + f[0] + "px (>= 4), QR이 화면 안에 다 들어감", f[0] >= 4 && inside);
        }
        int[] tiny = Report.fit(50, q2.size);
        check("아주 작은 자리도 칸 1px 이상, 음수 여백 없음", tiny[0] >= 1 && tiny[1] >= 0);

        System.out.println(fails == 0 ? "Java 모두 통과" : "Java 실패 " + fails + "개");
        System.exit(fails == 0 ? 0 : 1);
    }
}
