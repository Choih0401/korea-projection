package korea.projection.app;

import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 상태 파일(bin/status.sh가 root로 쓰는 key=value 줄)을 읽어 화면에 보일 줄과 QR에 담을 제보 링크를 만든다.
 * 안드로이드 클래스를 쓰지 않아 PC에서 시험할 수 있다(tests/ReportTest.java).
 * 상태 파일에는 SSID, 비밀번호, 휴대폰 이름, MAC, IP가 없다. 이 클래스도 그런 값을 만들지 않는다.
 */
final class Report {
    static final String ISSUES = "https://github.com/StopDragon/korea-projection/issues/new?template=car-report.yml";
    /** QR이 내비 화면에서 찍히도록 링크 길이를 제한한다 (QR 버전이 커지면 칸이 작아진다) */
    static final int MAX_URL = 560;

    final Map<String, String> v = new LinkedHashMap<String, String>();

    static Report parse(String text) {
        Report r = new Report();
        if (text == null) return r;
        for (String line : text.split("\n")) {
            int i = line.indexOf('=');
            if (i <= 0) continue;
            r.v.put(line.substring(0, i).trim(), line.substring(i + 1).trim());
        }
        return r;
    }

    String get(String k) { String s = v.get(k); return s == null ? "" : s; }
    boolean yes(String k) { return "yes".equals(v.get(k)); }
    boolean empty() { return v.isEmpty(); }
    /** 한국 차를 지원하지 않는 다른 무선 모드가 있고, 그 모드로 카플레이가 연결돼 있지 않음 */
    boolean foreign() { return yes("mod_foreign") && (get("cp_conn").isEmpty() || "0".equals(get("cp_conn"))); }

    /**
     * busybox가 없는 내비(K3·K8, tcc803x)인가. 1.5.5부터 status.sh가 이런 내비에서는 짧은 상태 파일
     * (support=nobb, product, platform, pkgver, usb, made)만 쓴다. 무선 설정은 하지 않는다.
     */
    boolean nobb() { return "nobb".equals(v.get("support")); }

    /** busybox 없는 내비의 제보 파일 칸: saved(USB에 저장함) / fail(USB에 쓰지 못함) / none(USB 없음) */
    private String usbCell() {
        String u = get("usb");
        if ("saved".equals(u)) return "USB의 KoreaProjection-report 폴더에 저장함";
        if ("fail".equals(u)) return "USB에 쓰지 못함 (다른 USB로 다시 해 보세요)";
        return "USB를 꽂고 Launch를 다시 누르면 만듭니다";
    }

    /** README "필요한 것"과 같은 최소 버전 (바꾸면 README와 설치 가이드도 함께 고친다) */
    static final String MIN_HMGAPI = "1.0.2";
    static final String MIN_NEMESIS = "1.16";

    /**
     * 1.6.2: 순정이 카플레이 AP를 직접 띄운 차(K3 BDPE 등, 상태 파일 ap_mode=stock). 이때 우리 핫스팟·DHCP가 꺼져 있는
     * 것이 정상이다(서비스가 일부러 켜지 않는다). 예전 상태 파일(ap_mode 없음)은 false.
     */
    boolean stockAp() { return "stock".equals(get("ap_mode")); }

    /** 맨 위 한 줄: 무선 카플레이가 될 준비가 됐는지, 아니면 무엇이 빠졌는지 */
    String verdict() {
        if (empty()) return "상태를 읽지 못했습니다. NEMESIS Manager에서 Launch를 다시 눌러 주세요.";
        if (nobb()) return "이 내비에서는 아직 동작하지 않습니다(지원 조사 중). 무선 설정은 하지 않았습니다.";
        if (!yes("tested")) return "확인되지 않은 차입니다. 핫스팟은 켜지 않고 대기 중입니다. QR로 제보해 주세요.";
        if (hmgapiVer().isEmpty()) return "HMG-API가 없습니다. HMG-API " + MIN_HMGAPI + " 이상을 설치해 주세요.";
        if (older(hmgapiVer(), MIN_HMGAPI) != 0)
            return "지원하지 않는 HMG-API 버전입니다. " + MIN_HMGAPI + " 이상으로 업데이트해 주세요.";
        // 1.6.1: 차에 있는 무선 모드가 한국 차를 지원하지 않는 다른 판(서비스는 덮어쓰지 않음). 토스트 대신 여기서 알린다.
        // 그 모드로 이미 카플레이가 연결돼 있으면 안내하지 않는다(판단은 mod.json의 region만 보므로).
        if (foreign()) return "차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다. HMG-API 앱에서 그 모드를 지우고 적용한 뒤 재부팅해 주세요.";
        if ("no".equals(get("mod"))) return "HMG-API 무선 모드가 없습니다. HMG-API 앱에서 설치해 주세요.";
        if ("no".equals(get("mod_on")))
            return "HMG-API 무선 모드가 꺼져 있습니다. HMG-API 앱에서 켜고 Apply changes 후 다시 시작해 주세요.";
        if ("off".equals(get("bridge")))
            return "무선 모드의 'Wireless CarPlay' 설정이 꺼져 있습니다. HMG-API 앱에서 켜고 Apply changes 후 다시 시작해 주세요.";
        if ("off".equals(get("hooks"))) return hooksOffAdvice();
        // 1.7.2: HMG-API가 이 차에서 무선 모드의 훅을 켜지 않음(차에 없는 훅 지점이 있음, 스포티지 NQ5 #46)
        if ("off".equals(get("mod_hooks")))
            return "HMG-API가 이 차에서 무선 모드를 켜지 못했습니다(이 차와 맞지 않는 부분이 있음). 내비를 재부팅해 보시고, 그래도 같으면 USB를 꽂고 Launch로 리포트를 보내 주세요.";
        if (!yes("feat_carplay")) return "무선 카플레이 기능이 꺼져 있습니다. HMG-API 무선 모드를 확인해 주세요.";
        // 1.6.2: 순정 카플레이 AP를 쓰는 차인데 지금 순정 Wi-Fi가 꺼져 있음(서비스는 우리 핫스팟을 켜지 않고 기다린다)
        if (!stockAp() && yes("stock_seen") && !yes("our_ap"))
            return "내비 Wi-Fi(무선 카플레이용)가 지금 꺼져 있습니다. 아이폰을 연결해 보고, 안 되면 내비를 재부팅해 주세요.";
        // 1.7.0: Wi-Fi 칩은 있는데 드라이버가 올라오지 않아 wlan0가 없다(그랜저 IG #52·#53). 재부팅으로 풀리는지 보고, 아니면 제보
        if (!stockAp() && yes("nowlan") && !yes("our_ap"))
            return "Wi-Fi 장치가 켜지지 않아 핫스팟을 켜지 못했습니다. 내비를 재부팅해 보시고, 그래도 같으면 USB를 꽂고 Launch로 리포트를 보내 주세요.";
        if (!stockAp() && (!yes("our_ap") || !yes("our_dhcp"))) return "핫스팟이 꺼져 있습니다. 내비를 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 다시 확인해 주세요.";
        if (older(get("nemesis"), MIN_NEMESIS) != 0)
            return "NEMESIS를 " + MIN_NEMESIS + " 이상으로 업데이트해 주세요.";
        if (!"0".equals(get("cp_conn")) && !get("cp_conn").isEmpty()) return "무선 카플레이 연결됨";
        if (stockAp()) return "무선 카플레이 준비됨(내비 Wi-Fi 사용). 아이폰을 연결해 보세요.";
        return "무선 카플레이 준비됨. 아이폰을 연결해 보세요.";
    }

    /** 0: 좋음, 1: 확인 필요, 2: 문제 (화면 색) */
    int level() {
        if (empty()) return 2;
        if (nobb()) return 1;
        if (!yes("tested")) return 1;
        if (!yes("feat_carplay")) return 2;
        if (hmgapiVer().isEmpty() || older(hmgapiVer(), MIN_HMGAPI) != 0) return 2;
        if (foreign()) return 2;
        if ("no".equals(get("mod")) || "no".equals(get("mod_on")) || "off".equals(get("bridge"))) return 2;
        if ("off".equals(get("mod_hooks"))) return 2;
        // 훅 기록은 지난 부팅 것일 수 있어 노랑
        if ("off".equals(get("hooks"))) return 1;
        if (!stockAp() && (!yes("our_ap") || !yes("our_dhcp"))) return 1;
        if (older(get("nemesis"), MIN_NEMESIS) != 0) return 1;
        return 0;
    }

    // --- 설치 진행 기록(1.5.5, 서비스가 쓰는 /data/local/tmp/korea-projection-progress.txt) ---
    // 이 Report를 진행 기록 파일로 만들었을 때 쓴다. boot는 지금 부팅 id(/proc/sys/kernel/random/boot_id):
    // 지난 부팅의 기록은 무시한다(재부팅 전 "진행 중"이 남아 있어도 막대를 보이지 않게).

    /** 이번 부팅의 기록인가 */
    boolean progThisBoot(String boot) {
        return !empty() && boot != null && boot.trim().equals(get("boot"));
    }

    /** 진행 기록이 이만큼(초) 새로 쓰이지 않으면 멈춘 것으로 본다(status.sh --wait의 15분과 같다) */
    static final long STALE = 900;

    /** 이번 부팅에 설치가 진행 중인가(진행 막대를 보일지) */
    boolean progRunning(String boot) {
        return progThisBoot(boot) && "run".equals(get("state"));
    }

    /** progRunning이면서 최근(STALE초 안)에 쓰인 기록인가. now: 지금 시각(초) */
    boolean progRunning(String boot, long now) {
        if (!progRunning(boot)) return false;
        try {
            return now - Long.parseLong(get("t")) <= STALE;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    /** 진행률 0~100 (읽지 못하면 0) */
    int progPct() {
        try {
            int p = Integer.parseInt(get("pct"));
            return p < 0 ? 0 : p > 100 ? 100 : p;
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /** 시작한 지 몇 초 (now: 지금 시각 초). 읽지 못하면 -1 */
    long progElapsed(long now) {
        try {
            long s = Long.parseLong(get("start"));
            return now >= s ? now - s : -1;
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    /** "3분 05초" */
    static String mmss(long sec) {
        if (sec < 0) return "-";
        long m = sec / 60, ss = sec % 60;
        return (m > 0 ? m + "분 " : "") + (ss < 10 && m > 0 ? "0" : "") + ss + "초";
    }

    /**
     * 설치가 끝난 결과가 맨 위 판정을 대신할 때의 문구. 재부팅 필요·실패만(이번 부팅 기록일 때). 아니면 null.
     * 재부팅이 필요한데 상태표만 보면 "무선 모드가 없습니다"처럼 보여 사용자가 오해하기 쉽다.
     */
    String progVerdict(String boot) {
        if (!progThisBoot(boot)) return null;
        String st = get("state");
        if ("reboot".equals(st) || "fail".equals(st)) return get("stage").isEmpty() ? null : get("stage");
        return null;
    }

    /** progVerdict의 색: 재부팅 필요는 노랑(1), 실패는 빨강(2) */
    int progLevel() {
        return "fail".equals(get("state")) ? 2 : 1;
    }

    /** 훅이 꺼진 이유(HMG-API CarMap 상태)별 안내 */
    String hooksOffAdvice() {
        String m = get("hookmap");
        if ("mapped".equals(m))
            return "HMG-API 훅이 꺼져 있습니다. HMG-API 앱 Settings에서 'Check the map on this car'를 누른 뒤 내비를 재부팅해 주세요.";
        if ("none".equals(m))
            return "HMG-API에 이 차의 지도가 없어 훅이 꺼져 있습니다. QR로 제보해 주세요.";
        if ("mismatch".equals(m))
            return "HMG-API 지도가 이 차의 소프트웨어와 맞지 않아 훅이 꺼져 있습니다. QR로 제보해 주세요.";
        return "HMG-API 훅이 꺼져 있습니다(마지막 부팅 기록). 내비를 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 다시 확인해 주세요.";
    }

    /** status.sh의 hmgapi 값("version 1.0.2 build 180185d 2026-11-04")에서 버전만. 없으면 "" */
    String hmgapiVer() {
        String s = get("hmgapi");
        int i = s.indexOf("version ");
        if (i < 0) return "";
        String rest = s.substring(i + 8).trim();
        int sp = rest.indexOf(' ');
        return sp < 0 ? rest : rest.substring(0, sp);
    }

    /**
     * have가 need보다 낮은가: 0 아니요(같거나 높음), 1 낮음, 2 숫자로 읽지 못함.
     * 앞의 숫자 부분만 본다("1.0.0-beta.5"는 1.0.0). 빈 값도 2.
     */
    static int older(String have, String need) {
        int[] a = nums(have), b = nums(need);
        if (a == null || b == null) return 2;
        for (int i = 0; i < Math.max(a.length, b.length); i++) {
            int x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
            if (x != y) return x < y ? 1 : 0;
        }
        return 0;
    }

    private static int[] nums(String s) {
        if (s == null) return null;
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("^\\s*(\\d+(?:\\.\\d+)*)").matcher(s);
        if (!m.find()) return null;
        String[] p = m.group(1).split("\\.");
        int[] r = new int[p.length];
        try {
            for (int i = 0; i < p.length; i++) r[i] = Integer.parseInt(p[i]);
        } catch (NumberFormatException e) {
            return null;
        }
        return r;
    }

    /** 무선 모드 칸: 없음 / 꺼짐 / 켜짐(무선 카플레이 설정 꺼짐) / 켜짐. 예전 상태 파일(mod만 있음)도 읽는다 */
    private String modCell() {
        if (yes("mod_foreign")) return "한국 차용 아님 (지워야 함)";
        if ("no".equals(get("mod"))) return "없음 (필요)";
        if ("no".equals(get("mod_on"))) return "꺼짐 (켜야 함)";
        if ("off".equals(get("bridge"))) return "켜짐, Wireless CarPlay 설정 꺼짐";
        if ("off".equals(get("mod_hooks"))) return "켜짐, 훅이 안 켜짐 (리포트 참고)";
        if (yes("mod_on")) return "켜짐" + pendingNote();
        return yn("mod");
    }

    /** 1.7.1: 우리가 넣은 모드가 패키지의 새 판으로 바뀌기를 기다리는 중(부팅 약 2분 뒤 자동). 차의 판을 함께 보인다 */
    private String pendingNote() {
        if (!yes("mod_pending")) return get("modver").isEmpty() ? "" : " (" + get("modver") + ")";
        return " (" + (get("modver").isEmpty() ? "이전 판" : get("modver")) + ", 새 판으로 바꾸기 대기 중)";
    }

    /**
     * 1.7.1: 알림 기록(svc/hotspot.sh notice, 토스트 대신). 한 줄에 "<시각(초)> <부팅 id> <문구>".
     * 이번 부팅의 줄만, 새것부터 최대 max개. 돌려주는 값은 {시각(초), 문구}.
     * now·maxAge(초)를 주면 그보다 오래된 줄은 뺀다(지난 단계의 안내가 계속 남아 오해하지 않게, 리뷰 M3).
     */
    static List<String[]> notices(String text, String boot, int max) {
        return notices(text, boot, max, 0, 0);
    }

    static List<String[]> notices(String text, String boot, int max, long now, long maxAge) {
        List<String[]> out = new ArrayList<String[]>();
        if (text == null || boot == null || boot.isEmpty()) return out;
        String[] lines = text.split("\n");
        for (int i = lines.length - 1; i >= 0 && out.size() < max; i--) {
            String l = lines[i].trim();
            int a = l.indexOf(' ');
            int b = a < 0 ? -1 : l.indexOf(' ', a + 1);
            if (b < 0) continue;
            if (!boot.equals(l.substring(a + 1, b))) continue;
            String msg = l.substring(b + 1).trim();
            if (msg.isEmpty()) continue;
            if (maxAge > 0) {
                long t;
                try { t = Long.parseLong(l.substring(0, a)); } catch (NumberFormatException e) { continue; }
                if (now - t > maxAge) continue;
            }
            out.add(new String[] { l.substring(0, a), msg });
        }
        return out;
    }

    /** 1.7.2: 안내가 이만큼(초) 지나면 보이지 않는다(서비스도 10분 뒤 지운다. 서비스가 멈춰 남은 안내를 가리려고) */
    static final long HINT_SHOW = 600;

    /**
     * 1.7.2: 서비스(svc/hotspot.sh hint_write)가 30초마다 정하는 상태 안내(/data/local/tmp/korea-projection-hint.txt, key=value).
     * 이번 부팅의 것만 보인다. 돌려주는 값은 {수준(0 좋음·1 확인 필요), 문구, 시각(초, 문구 옆에 HH:MM로 붙일 때만, 아니면 "")}.
     * 확인이 필요한 것(설정 바뀜·아이폰·AA 안내)을 먼저, "준비됨·연결됨"은 뒤에 둔다. 문구는 내비 화면에서 읽기 좋게 한두 문장.
     */
    static List<String[]> hints(String text, String boot, long now) {
        List<String[]> out = new ArrayList<String[]>();
        Report h = parse(text);
        if (boot == null || boot.isEmpty() || !boot.trim().equals(h.get("boot"))) return out;
        if ("wait".equals(h.get("conf")))
            out.add(new String[] { "1", "Wi-Fi 설정이 바뀌었습니다. 카플레이 연결이 끝나면 핫스팟을 다시 시작합니다.", "" });
        if ("wifi".equals(h.get("iph")) && h.fresh("iph_t", now))
            out.add(new String[] { "1", "아이폰이 차 Wi-Fi에 오지 않습니다. 아이폰 설정 → Wi-Fi에서 차 네트워크를 지우고 다시 연결하세요.", "" });
        String aa = h.get("aa");
        boolean aaNow = h.fresh("aa_t", now);
        if ("bt".equals(aa) && aaNow)
            out.add(new String[] { "1", "안드로이드 폰의 블루투스를 껐다 켜 주세요(또는 내비 블루투스 화면에서 폰을 다시 연결).", "" });
        if ("cpwait".equals(aa) && aaNow)
            out.add(new String[] { "1", "카플레이가 연결되어 있어 안드로이드 오토는 기다립니다.", "" });
        if ("ok".equals(aa) && aaNow)
            out.add(new String[] { "0", "무선 안드로이드 오토 연결됨", h.get("aa_t") });
        else if (h.num("aa_ready") > 0)
            out.add(new String[] { "0", "무선 안드로이드 오토 준비됨", h.get("aa_ready") });
        return out;
    }

    /** 숫자 값(초). 없거나 숫자가 아니면 0 */
    long num(String k) {
        try { return Long.parseLong(get(k)); } catch (NumberFormatException e) { return 0; }
    }

    /** 시각 k가 있고 HINT_SHOW초 안인가 */
    boolean fresh(String k, long now) {
        long t = num(k);
        return t > 0 && now - t <= HINT_SHOW;
    }

    /** 버전 칸: 값 옆에 필요 조건을 붙인다 */
    private static String ver(String have, String need) {
        if (have == null || have.isEmpty()) return "없음 (" + need + " 이상 필요)";
        int o = older(have, need);
        if (o == 1) return have + " (지원 안 함, " + need + " 이상 필요)";
        if (o == 2) return have + " (버전 확인 안 됨, " + need + " 이상 필요)";
        return have;
    }

    /** 화면 왼쪽 표: {제목, 값}. 필요한 것(버전·모드·훅)을 위에 둔다 */
    List<String[]> rows() {
        List<String[]> out = new ArrayList<String[]>();
        if (nobb()) {
            out.add(new String[] { "내비 소프트웨어", get("product") });
            out.add(new String[] { "내비 종류(플랫폼)", get("platform") });
            out.add(new String[] { "Korea Projection", get("pkgver") });
            out.add(new String[] { "지원", "아직 안 됨 (이 내비 종류는 조사 중)" });
            out.add(new String[] { "무선 설정", "하지 않았습니다 (차의 파일을 바꾸지 않음)" });
            out.add(new String[] { "제보 파일", usbCell() });
            return out;
        }
        out.add(new String[] { "내비 소프트웨어", get("product") });
        out.add(new String[] { "확인된 차", yn("tested") });
        out.add(new String[] { "Korea Projection", get("pkgver") });
        out.add(new String[] { "HMG-API", ver(hmgapiVer(), MIN_HMGAPI) });
        out.add(new String[] { "HMG-API 무선 모드", modCell() });
        String h = get("hooks");
        out.add(new String[] { "HMG-API 훅", "on".equals(h) ? "켜짐" : "off".equals(h) ? "꺼짐 (" + (get("hookmap").isEmpty() ? "?" : get("hookmap")) + ", 마지막 부팅 기록)" : "-" });
        out.add(new String[] { "NEMESIS", ver(get("nemesis"), MIN_NEMESIS) });
        out.add(new String[] { "무선 카플레이 기능", yn("feat_carplay") });
        // 1.7.0: 우리 무선 AA 설정(aa=yes 기본, no면 USB kp-aa-off로 끔). 줄 수는 그대로 둔다
        String aa = get("aa");
        out.add(new String[] { "무선 안드로이드 오토 기능", yn("feat_aa") + ("yes".equals(aa) ? " · 켜짐" : "no".equals(aa) ? " · 꺼짐(kp-aa-off)" : "") });
        out.add(new String[] { "Wi-Fi 장치", yn("wlan0") });
        String am = get("ap_mode");
        if (!am.isEmpty())
            out.add(new String[] { "무선 카플레이 Wi-Fi", "stock".equals(am) ? "내비 순정 Wi-Fi" : "ours".equals(am) ? "Korea Projection 핫스팟" : "없음" });
        out.add(new String[] { "핫스팟 (hostapd)", yn("our_ap") + (stockAp() ? " (순정 Wi-Fi를 쓰므로 꺼 둠)" : "") });
        out.add(new String[] { "IP 나눠 주기 (DHCP)", yn("our_dhcp") });
        out.add(new String[] { "순정 핫스팟", yn("other_ap") });
        out.add(new String[] { "카플레이 연결", get("cp_conn") + "개" });
        out.add(new String[] { "wireless.projection", yn("wp") + " (필요 없음)" });
        return out;
    }

    private String yn(String k) {
        String s = v.get(k);
        if ("yes".equals(s)) return "예";
        if ("no".equals(s)) return "아니요";
        return s == null ? "-" : s;
    }

    /**
     * QR에 담을 제보 링크. GitHub 이슈 양식은 항목 id로 미리 채울 수 있다(title, product, report).
     * report는 영문 key: value로 짧게 쓴다(한글은 링크에서 9배로 길어진다). 링크가 MAX_URL을 넘으면
     * 뒤쪽 줄부터 뺀다.
     */
    String issueUrl() {
        // 중요한 것부터: 링크가 길면 뒤에서부터 뺀다 (product는 제목·항목에 따로 들어간다)
        String[] keys = { "support", "state", "platform", "targetdir", "pkgver", "tested", "feat_carplay", "ap_mode", "our_ap", "our_dhcp", "other_ap", "stock_ssid", "stock_seen",
            "cp_conn", "aa", "nowlan", "wlan0", "softap_strings", "ssid_len", "pass_len", "wp", "mod", "mod_on", "bridge", "hooks", "hookmap", "feat_aa", "feat_wifi",
            "wpa", "hmgapi", "nemesis", "made", "modver" };
        List<String> lines = new ArrayList<String>();
        lines.add("(QR summary)");
        for (String k : keys) if (v.containsKey(k)) lines.add(k + ": " + v.get(k));
        // mod_foreign은 yes일 때만(링크 길이를 아낀다), 앞쪽에 넣는다
        if (yes("mod_foreign")) lines.add(1, "mod_foreign: yes");
        // 1.7.1: 모드 업데이트 대기도 yes일 때만 앞쪽에(리포트를 새 판 전에 만들었다는 표시)
        if (yes("mod_pending")) lines.add(1, "mod_pending: yes (" + get("modver") + ")");
        // 1.7.2: 무선 모드 훅이 안 켜졌으면 앞쪽에
        if ("off".equals(get("mod_hooks"))) lines.add(1, "mod_hooks: off");
        String url = build(lines);
        while (url.length() > MAX_URL && lines.size() > 2) {
            lines.remove(lines.size() - 1);
            url = build(lines);
        }
        return url;
    }

    private String build(List<String> lines) {
        StringBuilder body = new StringBuilder();
        for (String l : lines) body.append(l).append('\n');
        String product = get("product");
        return ISSUES + "&title=" + enc("차량 제보: " + product) + "&product=" + enc(product)
            + "&report=" + enc(body.toString());
    }

    /**
     * 한 변 side 픽셀 안에 QR(칸 qrSize개 + 양쪽 여백 4칸)을 정수 픽셀 칸으로 넣는 크기: {칸 픽셀, 가장자리 여백}.
     * 칸이 1px보다 작아지면 1px로 둔다(그 화면에서는 어차피 찍기 어렵다).
     */
    static int[] fit(int side, int qrSize) {
        int n = qrSize + 8;
        int scale = Math.max(1, side / n);
        int off = Math.max(0, (side - scale * n) / 2);
        return new int[] { scale, off };
    }

    static String enc(String s) {
        try {
            return URLEncoder.encode(s, "UTF-8").replace("+", "%20");
        } catch (UnsupportedEncodingException e) {
            throw new IllegalStateException(e);
        }
    }
}
