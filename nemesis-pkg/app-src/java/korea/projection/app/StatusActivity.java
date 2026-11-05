package korea.projection.app;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.FileInputStream;
import java.io.InputStream;

/**
 * NEMESIS Manager > Korea Projection > Launch가 여는 화면. bin/status.sh(root)가 먼저 상태 파일을 쓰고,
 * 이 화면은 그것을 읽어 왼쪽에 상태표, 오른쪽에 제보용 QR을 보여 준다. 판단은 Report에 있다.
 */
public class StatusActivity extends Activity implements View.OnClickListener {
    /** bin/status.sh가 쓰는 파일 (644, 비밀값 없음) */
    static final String STATUS = "/data/local/tmp/korea-projection-status.txt";

    static final int GOOD = 0xFF2E7D32, WARN = 0xFFF9A825, BAD = 0xFFC62828;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        Report r = Report.parse(read(STATUS));

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

        left.addView(text("Korea Projection", 24, Color.WHITE));
        TextView verdict = text(r.verdict(), 19, Color.WHITE);
        int lv = r.level();
        verdict.setBackgroundColor(lv == 0 ? GOOD : lv == 1 ? WARN : BAD);
        if (lv == 1) verdict.setTextColor(Color.BLACK);
        verdict.setPadding(dp(10), dp(6), dp(10), dp(6));
        LinearLayout.LayoutParams vp = new LinearLayout.LayoutParams(-1, -2);
        vp.topMargin = dp(6);
        vp.bottomMargin = dp(8);
        left.addView(verdict, vp);

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

        TextView hint = text("오른쪽 QR을 폰 카메라로 찍으면 내용이 채워진 제보 화면(GitHub)이 열립니다. "
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
        TextView made = text("  확인 " + r.get("made") + " · 화면 " + dm.widthPixels + "x" + dm.heightPixels
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
