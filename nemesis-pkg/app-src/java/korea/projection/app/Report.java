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

    /** 맨 위 한 줄: 무선 카플레이가 될 준비가 됐는지, 아니면 무엇이 빠졌는지 */
    String verdict() {
        if (empty()) return "상태를 읽지 못했습니다. NEMESIS Manager에서 Launch를 다시 눌러 주세요.";
        if (!yes("tested")) return "확인되지 않은 차입니다. 핫스폿은 켜지 않고 대기 중입니다. QR로 제보해 주세요.";
        if (!yes("feat_carplay")) return "무선 카플레이 기능이 꺼져 있습니다. HMG-API 무선 모드를 확인해 주세요.";
        if (!yes("our_ap") || !yes("our_dhcp")) return "핫스폿이 꺼져 있습니다. 차를 껐다 켠 뒤 다시 확인해 주세요.";
        if (!"0".equals(get("cp_conn")) && !get("cp_conn").isEmpty()) return "무선 카플레이 연결됨";
        return "무선 카플레이 준비됨. 아이폰을 연결해 보세요.";
    }

    /** 0: 좋음, 1: 확인 필요, 2: 문제 (화면 색) */
    int level() {
        if (empty() || !yes("feat_carplay")) return 2;
        if (!yes("tested") || !yes("our_ap") || !yes("our_dhcp")) return 1;
        return 0;
    }

    /** 화면 왼쪽 표: {제목, 값} */
    List<String[]> rows() {
        List<String[]> out = new ArrayList<String[]>();
        out.add(new String[] { "내비 소프트웨어", get("product") });
        out.add(new String[] { "확인된 차", yn("tested") });
        out.add(new String[] { "Korea Projection", get("pkgver") });
        out.add(new String[] { "HMG-API", get("hmgapi") });
        out.add(new String[] { "NEMESIS", get("nemesis") });
        out.add(new String[] { "무선 카플레이 기능", yn("feat_carplay") });
        out.add(new String[] { "무선 안드로이드 오토 기능", yn("feat_aa") });
        out.add(new String[] { "Wi-Fi 장치", yn("wlan0") });
        out.add(new String[] { "핫스폿 (hostapd)", yn("our_ap") });
        out.add(new String[] { "IP 나눠 주기 (DHCP)", yn("our_dhcp") });
        out.add(new String[] { "순정 핫스폿", yn("other_ap") });
        out.add(new String[] { "카플레이 연결", get("cp_conn") + "개" });
        out.add(new String[] { "wireless.projection", yn("wp") });
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
        String[] keys = { "targetdir", "pkgver", "tested", "feat_carplay", "our_ap", "our_dhcp", "other_ap",
            "cp_conn", "wlan0", "softap_strings", "ssid_len", "pass_len", "wp", "mod", "feat_aa", "feat_wifi",
            "wpa", "hmgapi", "nemesis", "made" };
        List<String> lines = new ArrayList<String>();
        lines.add("(QR summary)");
        for (String k : keys) if (v.containsKey(k)) lines.add(k + ": " + v.get(k));
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
