/*
 * HMG-API(VysseCodes, AGPL-3.0)의 core/app/java/hmgapi/app/QrCode.java를 그대로 가져왔다.
 * 바꾼 것은 package 줄 하나뿐이다. 원본: https://github.com/VysseCodes/HMG-API (커밋 180185d)
 */
package korea.projection.app;

/**
 * A QR code for a short text (byte mode, error correction M, the smallest version
 * that fits, mask 0): enough for the Car Report's issue link, so a phone can scan it
 * off the head unit's screen. Plain Java; the steps follow the QR spec (ISO 18004):
 * data bits, Reed-Solomon blocks interleaved, function patterns, the zigzag
 * placement, the mask, format and version bits.
 */
final class QrCode {
    public final int version, size;
    /** modules[y][x]: true is dark */
    public final boolean[][] modules;
    final boolean[][] function;

    static final int MASK = 0;
    static final int[] ECC_PER_BLOCK = { -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
        26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28 };
    static final int[] BLOCKS = { -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21,
        23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49 };

    public static QrCode encode(byte[] data) {
        for (int v = 1; v <= 40; v++) {
            int bits = 4 + (v <= 9 ? 8 : 16) + data.length * 8;
            if (bits <= dataCodewords(v) * 8) return new QrCode(v, data);
        }
        throw new IllegalArgumentException("too long for a QR code");
    }

    QrCode(int ver, byte[] text) {
        version = ver;
        size = ver * 4 + 17;
        modules = new boolean[size][size];
        function = new boolean[size][size];
        drawFunctionPatterns();
        drawCodewords(interleave(dataBytes(text)));
        applyMask();
        drawFormatBits();
    }

    // ---- data

    static int rawModules(int ver) {
        int r = (16 * ver + 128) * ver + 64;
        if (ver >= 2) {
            int n = ver / 7 + 2;
            r -= (25 * n - 10) * n - 55;
            if (ver >= 7) r -= 36;
        }
        return r;
    }

    static int dataCodewords(int ver) {
        return rawModules(ver) / 8 - ECC_PER_BLOCK[ver] * BLOCKS[ver];
    }

    byte[] dataBytes(byte[] text) {
        int cap = dataCodewords(version);
        byte[] out = new byte[cap];
        int[] bit = { 0 };
        put(out, bit, 0x4, 4);
        put(out, bit, text.length, version <= 9 ? 8 : 16);
        for (byte b : text) put(out, bit, b & 0xff, 8);
        put(out, bit, 0, Math.min(4, cap * 8 - bit[0]));
        bit[0] = (bit[0] + 7) / 8 * 8;
        for (int pad = 0xec; bit[0] < cap * 8; pad ^= 0xec ^ 0x11) put(out, bit, pad, 8);
        return out;
    }

    static void put(byte[] out, int[] bit, int val, int len) {
        for (int i = len - 1; i >= 0; i--, bit[0]++) {
            if (((val >>> i) & 1) != 0) out[bit[0] >>> 3] |= (byte) (0x80 >>> (bit[0] & 7));
        }
    }

    byte[] interleave(byte[] data) {
        int blocks = BLOCKS[version], ecc = ECC_PER_BLOCK[version], raw = rawModules(version) / 8;
        int shortBlocks = blocks - raw % blocks, shortLen = raw / blocks;
        byte[][] bs = new byte[blocks][];
        byte[] div = divisor(ecc);
        for (int i = 0, k = 0; i < blocks; i++) {
            int n = shortLen - ecc + (i < shortBlocks ? 0 : 1);
            byte[] dat = new byte[n];
            System.arraycopy(data, k, dat, 0, n);
            k += n;
            byte[] e = remainder(dat, div);
            byte[] b = new byte[shortLen + 1];
            System.arraycopy(dat, 0, b, 0, n);
            System.arraycopy(e, 0, b, shortLen + 1 - ecc, ecc);
            bs[i] = b;
        }
        byte[] out = new byte[raw];
        int k = 0;
        for (int i = 0; i < shortLen + 1; i++) {
            for (int j = 0; j < blocks; j++) {
                if (i != shortLen - ecc || j >= shortBlocks) out[k++] = bs[j][i];
            }
        }
        return out;
    }

    static byte[] divisor(int degree) {
        byte[] r = new byte[degree];
        r[degree - 1] = 1;
        int root = 1;
        for (int i = 0; i < degree; i++) {
            for (int j = 0; j < degree; j++) {
                r[j] = (byte) mul(r[j] & 0xff, root);
                if (j + 1 < degree) r[j] ^= r[j + 1];
            }
            root = mul(root, 0x02);
        }
        return r;
    }

    static byte[] remainder(byte[] data, byte[] div) {
        byte[] r = new byte[div.length];
        for (byte b : data) {
            int f = (b ^ r[0]) & 0xff;
            System.arraycopy(r, 1, r, 0, r.length - 1);
            r[r.length - 1] = 0;
            for (int i = 0; i < r.length; i++) r[i] ^= (byte) mul(div[i] & 0xff, f);
        }
        return r;
    }

    static int mul(int x, int y) {
        int z = 0;
        for (int i = 7; i >= 0; i--) {
            z = (z << 1) ^ ((z >>> 7) * 0x11d);
            z ^= ((y >>> i) & 1) * x;
        }
        return z;
    }

    // ---- the picture

    void set(int x, int y, boolean dark) {
        modules[y][x] = dark;
        function[y][x] = true;
    }

    void drawFunctionPatterns() {
        for (int i = 0; i < size; i++) {
            set(6, i, i % 2 == 0);
            set(i, 6, i % 2 == 0);
        }
        finder(3, 3);
        finder(size - 4, 3);
        finder(3, size - 4);
        int[] al = alignment();
        for (int i = 0; i < al.length; i++) {
            for (int j = 0; j < al.length; j++) {
                if ((i == 0 && j == 0) || (i == 0 && j == al.length - 1) || (i == al.length - 1 && j == 0)) continue;
                for (int dy = -2; dy <= 2; dy++) {
                    for (int dx = -2; dx <= 2; dx++) set(al[i] + dx, al[j] + dy, Math.max(Math.abs(dx), Math.abs(dy)) != 1);
                }
            }
        }
        drawFormatBits();   // reserves the area; drawn again after the mask
        if (version >= 7) {
            int rem = version;
            for (int i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
            long bits = (long) version << 12 | rem;
            for (int i = 0; i < 18; i++) {
                boolean b = ((bits >>> i) & 1) != 0;
                int a = size - 11 + i % 3, c = i / 3;
                set(a, c, b);
                set(c, a, b);
            }
        }
    }

    void finder(int x, int y) {
        for (int dy = -4; dy <= 4; dy++) {
            for (int dx = -4; dx <= 4; dx++) {
                int d = Math.max(Math.abs(dx), Math.abs(dy)), xx = x + dx, yy = y + dy;
                if (xx >= 0 && xx < size && yy >= 0 && yy < size) set(xx, yy, d != 2 && d != 4);
            }
        }
    }

    int[] alignment() {
        if (version == 1) return new int[0];
        int n = version / 7 + 2;
        int step = version == 32 ? 26 : (version * 4 + n * 2 + 1) / (n * 2 - 2) * 2;
        int[] r = new int[n];
        r[0] = 6;
        for (int i = n - 1, pos = size - 7; i >= 1; i--, pos -= step) r[i] = pos;
        return r;
    }

    void drawFormatBits() {
        int data = 0 << 3 | MASK;   // error correction M = 00
        int rem = data;
        for (int i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
        int bits = (data << 10 | rem) ^ 0x5412;
        for (int i = 0; i <= 5; i++) set(8, i, bit(bits, i));
        set(8, 7, bit(bits, 6));
        set(8, 8, bit(bits, 7));
        set(7, 8, bit(bits, 8));
        for (int i = 9; i < 15; i++) set(14 - i, 8, bit(bits, i));
        for (int i = 0; i < 8; i++) set(size - 1 - i, 8, bit(bits, i));
        for (int i = 8; i < 15; i++) set(8, size - 15 + i, bit(bits, i));
        set(8, size - 8, true);
    }

    static boolean bit(int x, int i) {
        return ((x >>> i) & 1) != 0;
    }

    void drawCodewords(byte[] data) {
        int i = 0;
        for (int right = size - 1; right >= 1; right -= 2) {
            if (right == 6) right = 5;
            for (int vert = 0; vert < size; vert++) {
                for (int j = 0; j < 2; j++) {
                    int x = right - j;
                    boolean up = ((right + 1) & 2) == 0;
                    int y = up ? size - 1 - vert : vert;
                    if (!function[y][x] && i < data.length * 8) {
                        modules[y][x] = bit(data[i >>> 3] & 0xff, 7 - (i & 7));
                        i++;
                    }
                }
            }
        }
    }

    void applyMask() {
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                if (!function[y][x] && (x + y) % 2 == 0) modules[y][x] = !modules[y][x];   // mask 0
            }
        }
    }

    /** test: prints the modules of a text's code, one row per line ("1" dark) */
    public static void main(String[] a) throws Exception {
        QrCode q = encode(a[0].getBytes("UTF-8"));
        System.out.println(q.version);
        for (boolean[] row : q.modules) {
            StringBuilder s = new StringBuilder();
            for (boolean m : row) s.append(m ? '1' : '0');
            System.out.println(s);
        }
    }
}
