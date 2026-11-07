package korea.projection.app;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;

/**
 * NEMESIS Manager > Korea Projection > Launch가 여는 화면. bin/status.sh(root)가 먼저 상태 파일을 쓰고,
 * 이 화면은 그것을 읽어 왼쪽에 상태표, 오른쪽에 제보용 QR을 보여 준다. 판단은 Report에 있다.
 * 1.5.5: 설치가 진행 중이면(서비스의 진행 기록 state=run) 먼저 진행 막대(0~100%)와 단계·경과 시간을 보여 준다.
 * 1초마다 다시 읽고, 끝나면(그리고 status.sh가 상태 파일을 새로 쓰면) 결과 화면으로 바뀐다.
 * 설치는 서비스가 하므로 이 화면을 닫아도 계속된다.
 */
public class StatusActivity extends Activity implements View.OnClickListener, Runnable {
    /** bin/status.sh가 쓰는 파일 (644, 비밀값 없음) */
    static final String STATUS = "/data/local/tmp/korea-projection-status.txt";
    /** svc/hotspot.sh가 쓰는 설치 진행 기록 (644, 비밀값 없음) */
    static final String PROG = "/data/local/tmp/korea-projection-progress.txt";
    static final String BOOT_ID = "/proc/sys/kernel/random/boot_id";
    /** 1.7.0: status.sh --collect가 쓰는 제보 자료 저장 진행 기록(644). 토스트 대신 이 화면 맨 위에 보인다 */
    static final String RPROG = "/data/local/tmp/korea-projection-report-progress.txt";
    /** 1.7.1: svc/hotspot.sh notice가 쓰는 알림 기록(644, 토스트 대신). 이번 부팅의 줄만 보인다 */
    static final String NOTICE = "/data/local/tmp/korea-projection-notice.txt";
    /** 알림을 보여 주는 시간(초): 그보다 오래된 안내는 지난 단계의 것이다 */
    static final long NOTICE_SHOW = 1800;
    /** 저장이 끝난 기록을 결과 화면에 보여 주는 시간(초): 그보다 오래된 완료 기록은 지난 Launch의 것이다 */
    static final int SAVE_SHOW = 600;
    /** 설치가 끝난 뒤 status.sh가 상태 파일을 다시 쓰기를 기다리는 최대 시간(초). 넘으면 있는 대로 보인다. */
    static final int AFTER_WAIT = 25;

    static final int GOOD = 0xFF2E7D32, WARN = 0xFFF9A825, BAD = 0xFFC62828;

    final Handler handler = new Handler();
    String boot;
    boolean watching;
    /** 1.7.0: 제보 자료 저장(RPROG)을 1초마다 읽는 중 */
    boolean saving;
    ProgressBar saveBar;
    TextView saveText;
    long finishedAt;
    ProgressBar bar;
    TextView pctText, stageText, timeText, noticeText;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        start();
    }

    /** Launch를 다시 누르면(singleTask) 같은 화면을 새 상태로 다시 그린다 */
    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        setIntent(i);
        handler.removeCallbacks(this);
        start();
    }

    void start() {
        String bid = read(BOOT_ID);
        boot = bid == null ? null : bid.trim();
        finishedAt = 0;
        Report p = Report.parse(read(PROG));
        if (p.progRunning(boot, System.currentTimeMillis() / 1000)) {
            showProgress(p);
            watching = true;
            handler.postDelayed(this, 1000);
        } else {
            watching = false;
            showStatus();
        }
    }

    /** 화면이 가려지면 읽기를 멈추고, 다시 보이면 이어서 */
    @Override
    protected void onPause() {
        handler.removeCallbacks(this);
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (watching || saving) {
            handler.removeCallbacks(this);
            handler.postDelayed(this, 1000);
        }
    }

    @Override
    protected void onDestroy() {
        watching = false;
        saving = false;
        handler.removeCallbacks(this);
        super.onDestroy();
    }

    /** 1초마다: 진행 기록을 다시 읽어 막대를 고치고, 끝났으면 결과 화면으로 */
    @Override
    public void run() {
        if (!watching) {
            if (saving) saveTick();
            return;
        }
        Report p = Report.parse(read(PROG));
        long now = System.currentTimeMillis() / 1000;
        if (p.progRunning(boot, now)) {
            update(p, now);
            handler.postDelayed(this, 1000);
            return;
        }
        // 끝남: status.sh(--wait)가 상태 파일을 새로 쓸 때까지 잠시(최대 AFTER_WAIT초) "결과 정리 중"
        if (finishedAt == 0) finishedAt = now;
        long t = 0;
        try { t = Long.parseLong(p.get("t")); } catch (NumberFormatException e) { t = 0; }
        long st = new File(STATUS).lastModified() / 1000;
        if (st >= t || now - finishedAt >= AFTER_WAIT) {
            watching = false;
            showStatus();
            return;
        }
        if (bar != null) bar.setProgress(100);
        if (pctText != null) pctText.setText("100%");
        if (stageText != null) stageText.setText("끝났습니다. 결과를 정리하는 중입니다…");
        handler.postDelayed(this, 1000);
    }

    /** 설치 진행 화면: 막대, %, 지금 단계, 경과 시간, 안내 */
    void showProgress(Report p) {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xFF121212);
        int pad = dp(24);
        root.setPadding(pad, pad, pad, pad);
        root.setGravity(Gravity.CENTER_VERTICAL);

        root.addView(text("Korea Projection " + appVersion() + " 설치 중", 26, Color.WHITE));
        stageText = text(p.get("stage"), 20, Color.WHITE);
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, -2);
        sp.topMargin = dp(16);
        root.addView(stageText, sp);

        bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(100);
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(-1, dp(28));
        bp.topMargin = dp(12);
        root.addView(bar, bp);

        LinearLayout line = new LinearLayout(this);
        line.setOrientation(LinearLayout.HORIZONTAL);
        pctText = text("", 22, Color.WHITE);
        line.addView(pctText, new LinearLayout.LayoutParams(0, -2, 1f));
        timeText = text("", 18, 0xFFB0B0B0);
        line.addView(timeText);
        root.addView(line);

        // 1.7.1: 설치 중 알림(토스트 대신)은 단계 아래에 최근 것 하나
        noticeText = text("", 17, 0xFFFFE082);
        LinearLayout.LayoutParams ntp = new LinearLayout.LayoutParams(-1, -2);
        ntp.topMargin = dp(10);
        root.addView(noticeText, ntp);

        TextView hint = text("설치가 끝날 때까지 기다려 주세요(보통 3~5분). 이 화면을 닫아도 설치는 계속됩니다. "
            + "그동안 내비를 끄거나 재부팅하지 마세요. 끝나면 이 화면이 결과로 바뀝니다.", 16, 0xFFB0B0B0);
        LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(-1, -2);
        hp.topMargin = dp(18);
        root.addView(hint, hp);

        Button close = new Button(this);
        close.setText("닫기");
        close.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        close.setOnClickListener(this);
        LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(dp(160), -2);
        cp.topMargin = dp(18);
        root.addView(close, cp);

        setContentView(root);
        update(p, System.currentTimeMillis() / 1000);
    }

    void update(Report p, long now) {
        int pct = p.progPct();
        if (bar != null) bar.setProgress(pct);
        if (pctText != null) pctText.setText(pct + "%");
        if (stageText != null) stageText.setText(p.get("stage"));
        if (timeText != null) timeText.setText("경과 " + Report.mmss(p.progElapsed(now)));
        if (noticeText != null) {
            java.util.List<String[]> ns = Report.notices(read(NOTICE), boot, 1, now, NOTICE_SHOW);
            noticeText.setText(ns.isEmpty() ? "" : "알림 " + clock(ns.get(0)[0]) + "  " + ns.get(0)[1]);
        }
    }

    /** 알림 시각(초) → "HH:MM". 읽지 못하면 빈 값 */
    static String clock(String sec) {
        try {
            java.util.Calendar c = java.util.Calendar.getInstance();
            c.setTimeInMillis(Long.parseLong(sec) * 1000L);
            return String.format(java.util.Locale.US, "%02d:%02d", c.get(java.util.Calendar.HOUR_OF_DAY), c.get(java.util.Calendar.MINUTE));
        } catch (Exception e) {
            return "";
        }
    }

    String appVersion() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "";
        }
    }

    /**
     * 1.7.0: 제보 자료 저장 진행(RPROG). 진행 중이면 막대와 %, 끝나면 초록 "완료: USB를 빼셔도 됩니다", 실패면 빨강.
     * 이번 부팅의 기록만 본다. 진행 중 기록이 오래 갱신되지 않으면(STALE) 멈춘 것으로 보고 읽기를 그만둔다.
     */
    void saveTick() {
        Report rp = Report.parse(read(RPROG));
        long now = System.currentTimeMillis() / 1000;
        if (saveText == null) { saving = false; return; }
        String st = rp.get("state");
        if (rp.progRunning(boot, now)) {
            int pct = rp.progPct();
            saveText.setText("제보 자료 저장 중 " + pct + "% · " + rp.get("stage") + " (USB를 빼지 마세요)");
            saveText.setBackgroundColor(0xFF263238);
            saveText.setTextColor(Color.WHITE);
            if (saveBar != null) { saveBar.setVisibility(View.VISIBLE); saveBar.setProgress(pct); }
            handler.postDelayed(this, 1000);
            return;
        }
        saving = false;
        if (saveBar != null) saveBar.setVisibility(View.GONE);
        if ("done".equals(st)) {
            saveText.setText(rp.get("stage"));
            saveText.setBackgroundColor(GOOD);
            saveText.setTextColor(Color.WHITE);
        } else if ("fail".equals(st)) {
            saveText.setText(rp.get("stage"));
            saveText.setBackgroundColor(BAD);
            saveText.setTextColor(Color.WHITE);
        } else {
            saveText.setText("제보 자료 저장 상태를 알 수 없습니다. USB의 KoreaProjection-report 폴더를 확인해 주세요.");
            saveText.setBackgroundColor(WARN);
            saveText.setTextColor(Color.BLACK);
        }
    }

    /** 이번 부팅에, 최근(SAVE_SHOW초 안) 쓰인 저장 기록이 있는가 */
    boolean saveRecent(Report rp) {
        if (!rp.progThisBoot(boot)) return false;
        try {
            return System.currentTimeMillis() / 1000 - Long.parseLong(rp.get("t")) <= SAVE_SHOW;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    /** 결과 화면(1.5.4까지의 화면). 설치 결과가 재부팅 필요·실패면 맨 위 판정을 그 문구로 바꾼다. */
    void showStatus() {
        bar = null; pctText = null; stageText = null; timeText = null; noticeText = null;
        saveBar = null; saveText = null; saving = false;
        Report r = Report.parse(read(STATUS));
        Report p = Report.parse(read(PROG));

        // 가로로 둘: 왼쪽은 글(판정·표·안내·버튼), 오른쪽은 화면 높이를 다 쓰는 정사각형 QR.
        // QR을 먼저(가중치 없이) 재므로 높이만큼 자리를 먼저 받고, 왼쪽이 남은 폭을 쓴다.
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.HORIZONTAL);
        root.setBackgroundColor(0xFF121212);
        int pad = dp(12);
        root.setPadding(pad, pad, pad, pad);

        LinearLayout left = new LinearLayout(this);
        left.setOrientation(LinearLayout.VERTICAL);
        left.setPadding(0, 0, dp(16), 0);

        left.addView(text("Korea Projection " + r.get("pkgver"), 24, Color.WHITE));
        String pv = p.progVerdict(boot);
        TextView verdict = text(pv != null ? pv : r.verdict(), 19, Color.WHITE);
        int lv = pv != null ? p.progLevel() : r.level();
        verdict.setBackgroundColor(lv == 0 ? GOOD : lv == 1 ? WARN : BAD);
        if (lv == 1) verdict.setTextColor(Color.BLACK);
        verdict.setPadding(dp(10), dp(6), dp(10), dp(6));
        LinearLayout.LayoutParams vp = new LinearLayout.LayoutParams(-1, -2);
        vp.topMargin = dp(6);
        vp.bottomMargin = dp(8);
        left.addView(verdict, vp);

        // 1.7.1: 알림(토스트 대신): 이번 부팅의 최근 3개, 새것이 위
        for (String[] n : Report.notices(read(NOTICE), boot, 3, System.currentTimeMillis() / 1000, NOTICE_SHOW)) {
            TextView nt = text("알림 " + clock(n[0]) + "  " + n[1], 16, Color.BLACK);
            nt.setBackgroundColor(0xFFFFE082);
            nt.setPadding(dp(10), dp(4), dp(10), dp(4));
            LinearLayout.LayoutParams np = new LinearLayout.LayoutParams(-1, -2);
            np.bottomMargin = dp(4);
            left.addView(nt, np);
        }

        // 1.7.0: 제보 자료 저장 진행(토스트 대신)
        Report rp = Report.parse(read(RPROG));
        if (saveRecent(rp)) {
            saveText = text("", 17, Color.WHITE);
            saveText.setPadding(dp(10), dp(6), dp(10), dp(6));
            left.addView(saveText, new LinearLayout.LayoutParams(-1, -2));
            saveBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
            saveBar.setMax(100);
            LinearLayout.LayoutParams sbp = new LinearLayout.LayoutParams(-1, dp(14));
            sbp.bottomMargin = dp(8);
            left.addView(saveBar, sbp);
            saving = true;
            saveTick();
        }

        LinearLayout table = new LinearLayout(this);
        table.setOrientation(LinearLayout.VERTICAL);
        for (String[] row : r.rows()) {
            LinearLayout line = new LinearLayout(this);
            line.setOrientation(LinearLayout.HORIZONTAL);
            line.addView(text(row[0], 16, 0xFFB0B0B0), new LinearLayout.LayoutParams(0, -2, 1.1f));
            line.addView(text(row[1], 16, Color.WHITE), new LinearLayout.LayoutParams(0, -2, 1f));
            line.setPadding(0, dp(2), 0, dp(2));
            table.addView(line);
        }
        ScrollView sv = new ScrollView(this);
        sv.addView(table);
        left.addView(sv, new LinearLayout.LayoutParams(-1, 0, 1f));

        TextView hint = text(r.nobb()
            ? "오른쪽 QR을 폰 카메라로 찍으면 제보 화면(GitHub)이 열립니다. USB의 KoreaProjection-report 폴더 파일을 "
                + "함께 올려 주시면 지원을 검토하는 데 도움이 됩니다. 개인정보는 들어 있지 않습니다."
            : "오른쪽 QR을 폰 카메라로 찍으면 내용이 채워진 제보 화면(GitHub)이 열립니다. "
                + "비밀번호, SSID, 휴대폰 이름, MAC은 들어 있지 않습니다.", 14, 0xFFB0B0B0);
        hint.setPadding(0, dp(6), 0, dp(6));
        left.addView(hint);

        LinearLayout bottom = new LinearLayout(this);
        bottom.setOrientation(LinearLayout.HORIZONTAL);
        bottom.setGravity(Gravity.CENTER_VERTICAL);
        Button close = new Button(this);
        close.setText("닫기");
        close.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        // 익명 클래스 대신 이 화면이 직접 받는다 (JDK 21 + d8 8.2가 익명 클래스에서 멈춤)
        close.setOnClickListener(this);
        bottom.addView(close, new LinearLayout.LayoutParams(dp(160), -2));
        android.util.DisplayMetrics dm = getResources().getDisplayMetrics();
        TextView made = text("  확인 " + r.get("made") + " · 앱 " + appVersion() + " · 화면 " + dm.widthPixels + "x" + dm.heightPixels
            + " (밀도 " + dm.density + ")", 12, 0xFF808080);
        bottom.addView(made);
        left.addView(bottom);

        QrCode q = null;
        try {
            q = QrCode.encode(r.issueUrl().getBytes("UTF-8"));
        } catch (Exception e) {
            q = null;
        }
        QrView qr = new QrView(this, q);
        // 높이는 부모를 꽉 채우고, 폭은 QrView가 높이와 같게 정한다
        root.addView(qr, new LinearLayout.LayoutParams(-2, -1));
        root.addView(left, 0, new LinearLayout.LayoutParams(0, -1, 1f));
        setContentView(root);
    }

    @Override
    public void onClick(View v) {
        finish();
    }

    TextView text(String s, int sp, int color) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        return t;
    }

    int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }

    static String read(String path) {
        InputStream in = null;
        try {
            in = new FileInputStream(path);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            return out.toString("UTF-8");
        } catch (Exception e) {
            return null;
        } finally {
            if (in != null) try { in.close(); } catch (Exception ignored) { }
        }
    }

}
