package korea.projection.app;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.view.View;

/**
 * QR을 정사각형으로 그리는 뷰. 받은 높이를 다 쓰되(폭이 모자라면 폭에 맞춤) 칸은 정수 픽셀로만 그려
 * 흐려지지 않게 한다. 2026-11-06 니로에서 400dp 고정 크기가 화면 아래로 잘려 찍히지 않았다:
 * 차마다 내비 화면 크기가 달라 고정 크기를 쓸 수 없다.
 */
final class QrView extends View {
    private final QrCode qr;
    private final Paint dark = new Paint();

    QrView(Context c, QrCode qr) {
        super(c);
        this.qr = qr;
        dark.setColor(Color.BLACK);
        dark.setAntiAlias(false);
    }

    @Override
    protected void onMeasure(int wSpec, int hSpec) {
        int w = MeasureSpec.getSize(wSpec), h = MeasureSpec.getSize(hSpec);
        int side = MeasureSpec.getMode(wSpec) == MeasureSpec.UNSPECIFIED ? h
            : MeasureSpec.getMode(hSpec) == MeasureSpec.UNSPECIFIED ? w : Math.min(w, h);
        setMeasuredDimension(side, side);
    }

    @Override
    protected void onDraw(Canvas c) {
        int side = Math.min(getWidth(), getHeight());
        c.drawColor(Color.WHITE);
        if (qr == null) return;
        int[] f = Report.fit(side, qr.size);
        int scale = f[0], off = f[1];
        for (int y = 0; y < qr.size; y++) {
            for (int x = 0; x < qr.size; x++) {
                if (!qr.modules[y][x]) continue;
                int px = off + (x + 4) * scale, py = off + (y + 4) * scale;
                c.drawRect(px, py, px + scale, py + scale, dark);
            }
        }
    }
}
