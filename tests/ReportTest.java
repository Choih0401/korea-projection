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
        // 1.6.1: 차에 맞지 않는 다른 무선 모드(HMG-API 기본판) → 토스트 대신 Launch 화면 맨 위에서 지우라고 안내
        Report fm = Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=yes"));
        check("다른 판 무선 모드 → 지우고 재부팅 안내, 빨강, 칸 '한국 차용 아님'", fm.verdict().startsWith("차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다")
            && fm.level() == 2 && row(fm, "HMG-API 무선 모드").startsWith("한국 차용 아님") && fm.verdict().length() <= 80);
        Report fmc = Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=yes").replace("cp_conn=0", "cp_conn=1"));
        check("다른 판이어도 카플레이가 연결돼 있으면 빨강 안내 안 함", fmc.verdict().equals("무선 카플레이 연결됨") && fmc.level() == 0);
        check("확인 안 된 차는 그 안내가 먼저", Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=yes").replace("tested=yes", "tested=no")).verdict().startsWith("확인되지 않은 차"));
        check("QR 요약: mod_foreign은 yes일 때만", fm.issueUrl().contains("mod_foreign") && !Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=no")).issueUrl().contains("mod_foreign"));
        check("mod_foreign=no면 그대로 '준비됨'", Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=no")).verdict().startsWith("무선 카플레이 준비됨"));
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
        check("  상태 모름 → 재부팅 안내", Report.parse(GOOD.replace("hooks=on", "hooks=off")).verdict().contains("마지막 부팅 기록"));
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

        // 1.5.5 설치 진행 기록
        String PR = "pct=40\nstate=run\nstage=이 차의 지도를 만드는 중입니다(1~2분)\nstart=1000\nt=1100\nboot=abc-123\n";
        Report pr = Report.parse(PR);
        check("진행 기록: 이번 부팅이면 진행 중, 40%, 경과 2분 05초", pr.progRunning("abc-123\n") && pr.progPct() == 40
            && "2분 05초".equals(Report.mmss(pr.progElapsed(1125))));
        check("  지난 부팅의 기록이면 진행 막대를 보이지 않음", !pr.progRunning("other") && !pr.progRunning(null));
        check("  15분 넘게 새로 쓰이지 않은 기록은 멈춘 것으로 봄", pr.progRunning("abc-123", 1100 + 900) && !pr.progRunning("abc-123", 1100 + 901));
        check("  진행 중이면 맨 위 판정을 바꾸지 않음", pr.progVerdict("abc-123") == null);
        Report rb = Report.parse(PR.replace("state=run", "state=reboot").replace("stage=이 차의 지도를 만드는 중입니다(1~2분)", "stage=무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요."));
        check("  재부팅 필요 → 그 문구가 판정, 노랑", "무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요.".equals(rb.progVerdict("abc-123")) && rb.progLevel() == 1);
        Report rf = Report.parse(PR.replace("state=run", "state=fail").replace("stage=이 차의 지도를 만드는 중입니다(1~2분)", "stage=HMG-API가 없습니다."));
        check("  실패 → 그 문구가 판정, 빨강", "HMG-API가 없습니다.".equals(rf.progVerdict("abc-123")) && rf.progLevel() == 2);
        check("  준비됨(done)은 판정을 바꾸지 않음(상태표 판정 그대로)", Report.parse(PR.replace("state=run", "state=done")).progVerdict("abc-123") == null);
        check("  진행률이 이상하면 0~100으로", Report.parse("pct=250").progPct() == 100 && Report.parse("pct=x").progPct() == 0 && Report.parse("pct=-5").progPct() == 0);
        check("  시간: 59초, 1분 00초, 시작 기록 없으면 -", "59초".equals(Report.mmss(59)) && "1분 00초".equals(Report.mmss(60)) && "-".equals(Report.mmss(Report.parse("").progElapsed(5))));

        // 1.5.5 busybox 없는 내비(K3·K8): status.sh가 짧은 상태 파일만 쓴다
        String NB = "support=nobb\nproduct=BDPE.KOR.0000.V039.001.260902\nplatform=tcc803x\npkgver=1.5.5\nusb=saved\nmade=11-07 03:00\n";
        Report nb = Report.parse(NB);
        check("busybox 없는 내비 → '아직 동작하지 않습니다(지원 조사 중)', 노랑", nb.nobb()
            && nb.verdict().startsWith("이 내비에서는 아직 동작하지 않습니다") && nb.level() == 1);
        check("  표는 6줄: 플랫폼, 지원 안 됨, 무선 설정 안 함, 제보 파일 저장함", nb.rows().size() == 6
            && "tcc803x".equals(row(nb, "내비 종류(플랫폼)")) && row(nb, "제보 파일").startsWith("USB의 KoreaProjection-report")
            && row(nb, "무선 설정").startsWith("하지 않았습니다"));
        check("  USB가 없으면 Launch를 다시 누르라고, 쓰지 못했으면 다른 USB", row(Report.parse(NB.replace("usb=saved", "usb=none")), "제보 파일").startsWith("USB를 꽂고")
            && row(Report.parse(NB.replace("usb=saved", "usb=fail")), "제보 파일").startsWith("USB에 쓰지 못함"));
        check("  QR 링크에 support·platform이 들어감", nb.issueUrl().contains("support%3A%20nobb") && nb.issueUrl().contains("platform%3A%20tcc803x"));
        check("  보통 상태 파일은 busybox 없는 내비가 아님(표 15줄 그대로)", !r.nobb() && r.rows().size() == 15);

        // 1.6.2: 순정 카플레이 AP(K3 #15: our_ap=no, our_dhcp는 오판이 고쳐져 no, other_ap=yes)
        String STOCK = GOOD.replace("our_ap=yes", "our_ap=no").replace("our_dhcp=yes", "our_dhcp=no").replace("other_ap=no", "other_ap=yes")
            + "stock_ssid=carplay\nap_mode=stock\n";
        Report st = Report.parse(STOCK);
        check("1.6.2: 순정 카플레이 AP → '준비됨(내비 Wi-Fi 사용)', 초록, 재부팅 안내 없음",
            st.verdict().equals("무선 카플레이 준비됨(내비 Wi-Fi 사용). 아이폰을 연결해 보세요.") && st.level() == 0 && !st.verdict().contains("재부팅"));
        check("  순정 AP + 연결 수 있음 → '연결됨'", Report.parse(STOCK.replace("cp_conn=0", "cp_conn=1")).verdict().equals("무선 카플레이 연결됨"));
        check("  순정 AP여도 무선 모드가 꺼져 있으면 그 안내(빨강)", Report.parse(STOCK.replace("mod_on=yes", "mod_on=no")).verdict().contains("꺼져 있습니다") &&
            Report.parse(STOCK.replace("mod_on=yes", "mod_on=no")).level() == 2);
        check("  순정 AP여도 bridge가 꺼져 있으면 그 안내", Report.parse(STOCK.replace("bridge=on", "bridge=off")).verdict().contains("'Wireless CarPlay' 설정이 꺼져"));
        check("  표에 '무선 카플레이 Wi-Fi: 내비 순정 Wi-Fi'와 핫스팟 칸 설명", "내비 순정 Wi-Fi".equals(row(st, "무선 카플레이 Wi-Fi")) &&
            row(st, "핫스팟 (hostapd)").startsWith("아니요 (순정 Wi-Fi를 쓰므로"));
        Report hs = Report.parse(GOOD.replace("our_ap=yes", "our_ap=no").replace("other_ap=no", "other_ap=yes") + "stock_ssid=hotspot\nap_mode=none\n");
        check("  순정 일반 핫스팟(ap_mode=none)은 예전처럼 '핫스팟이 꺼져' 안내, 노랑", hs.verdict().startsWith("핫스팟이 꺼져") && hs.level() == 1 &&
            "없음".equals(row(hs, "무선 카플레이 Wi-Fi")));
        check("  ap_mode=ours는 예전과 같은 '준비됨'", Report.parse(GOOD + "stock_ssid=none\nap_mode=ours\n").verdict().equals("무선 카플레이 준비됨. 아이폰을 연결해 보세요."));
        check("  예전 상태 파일(ap_mode 없음)은 표 15줄 그대로", r.rows().size() == 15 && row(r, "무선 카플레이 Wi-Fi") == null);
        String sd = java.net.URLDecoder.decode(st.issueUrl(), "UTF-8");
        check("  QR 요약에 ap_mode·stock_ssid", sd.contains("ap_mode: stock") && sd.contains("stock_ssid: carplay"));
        Report off = Report.parse(GOOD.replace("our_ap=yes", "our_ap=no").replace("our_dhcp=yes", "our_dhcp=no") + "stock_ssid=none\nap_mode=none\nstock_seen=yes\n");
        check("  순정 AP를 쓰는 차인데 지금 꺼져 있으면 '내비 Wi-Fi가 꺼져' 안내(우리 핫스팟 재부팅 안내 아님), 노랑",
            off.verdict().startsWith("내비 Wi-Fi(무선 카플레이용)가 지금 꺼져 있습니다") && off.level() == 1);
        // 1.7.0: Wi-Fi 장치(wlan0)가 생기지 않아 핫스팟을 못 켬(그랜저 IG #52·#53)
        Report nw = Report.parse(GOOD.replace("our_ap=yes", "our_ap=no") + "nowlan=yes\nap_mode=none\n");
        check("1.7.0 wlan0 없음 → 'Wi-Fi 장치가 켜지지 않아' 안내(재부팅·리포트)", nw.verdict().startsWith("Wi-Fi 장치가 켜지지 않아 핫스팟을 켜지 못했습니다"));
        check("  nowlan=no면 예전 '핫스팟이 꺼져' 안내", Report.parse(GOOD.replace("our_ap=yes", "our_ap=no") + "nowlan=no\n").verdict().startsWith("핫스팟이 꺼져"));
        check("  무선 AA 칸: aa=yes '켜짐', aa=no '꺼짐(kp-aa-off)', 표 줄 수는 그대로", row(Report.parse(GOOD + "aa=yes\n"), "무선 안드로이드 오토 기능").endsWith("· 켜짐")
            && row(Report.parse(GOOD + "aa=no\n"), "무선 안드로이드 오토 기능").endsWith("· 꺼짐(kp-aa-off)") && Report.parse(GOOD + "aa=yes\n").rows().size() == 15);
        String nq = java.net.URLDecoder.decode(Report.parse(GOOD + "state=reboot\naa=yes\nnowlan=yes\n").issueUrl(), "UTF-8");
        check("  QR 요약에 state·aa·nowlan", nq.contains("state: reboot") && nq.contains("aa: yes") && nq.contains("nowlan: yes"));
        // 1.7.1: 알림 기록(토스트 대신), 모드 업데이트 대기
        String nt = "1700000000 boot-A 첫 안내\n1700000100 boot-B 지난 부팅 안내\n1700000200 boot-A 두 번째 안내\n1700000300 boot-A 세 번째\n1700000400 boot-A 네 번째\nbroken\n1700000500 boot-A \n";
        java.util.List<String[]> ns = Report.notices(nt, "boot-A", 3);
        check("1.7.1 알림: 이번 부팅 줄만, 새것부터 최대 3개, 빈 문구·깨진 줄은 건너뜀", ns.size() == 3 && "네 번째".equals(ns.get(0)[1]) && "1700000400".equals(ns.get(0)[0])
            && "두 번째 안내".equals(ns.get(2)[1]));
        check("  부팅 id를 모르거나 기록이 없으면 없음", Report.notices(nt, null, 3).isEmpty() && Report.notices(null, "boot-A", 3).isEmpty() && Report.notices(nt, "boot-C", 3).isEmpty());
        java.util.List<String[]> fresh = Report.notices(nt, "boot-A", 3, 1700000500L, 250);
        check("  보여 주는 시간이 지난 줄(리뷰 M3)은 뺌", fresh.size() == 2 && "네 번째".equals(fresh.get(0)[1]) && "세 번째".equals(fresh.get(1)[1]));
        check("  문구 안의 띄어쓰기는 그대로", "지난 부팅 안내".equals(Report.notices(nt, "boot-B", 1).get(0)[1]));
        check("1.7.1 모드 칸: 새 판 대기 중이면 차의 판과 '대기 중', 아니면 판만, 예전 파일은 '켜짐' 그대로",
            "켜짐 (2.2.0, 새 판으로 바꾸기 대기 중)".equals(row(Report.parse(GOOD + "modver=2.2.0\nmod_pending=yes\n"), "HMG-API 무선 모드"))
            && "켜짐 (2.3.0)".equals(row(Report.parse(GOOD + "modver=2.3.0\nmod_pending=no\n"), "HMG-API 무선 모드"))
            && "켜짐".equals(row(r, "HMG-API 무선 모드")));
        String mq = java.net.URLDecoder.decode(Report.parse(GOOD + "modver=2.2.0\nmod_pending=yes\n").issueUrl(), "UTF-8");
        check("  QR 요약 앞쪽에 mod_pending과 차의 판", mq.contains("mod_pending: yes (2.2.0)"));
        System.out.println(fails == 0 ? "Java 모두 통과" : "Java 실패 " + fails + "개");
        System.exit(fails == 0 ? 0 : 1);
    }
}
