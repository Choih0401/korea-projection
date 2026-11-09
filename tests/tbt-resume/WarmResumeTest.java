package hmgapi.mods.wireless.dipo;

import hmgapi.hook.Cluster;

/** Public synthetic messages only: no car/phone data or Android device required. */
public final class WarmResumeTest {
    static int checks;
    static void check(String name, boolean ok) {
        if (!ok) throw new AssertionError(name);
        checks++;
    }
    public static void main(String[] args) {
        Cluster c = new Cluster();
        CpTurns t = new CpTurns(new android.content.Context(), c, null);
        final int[] silence = { 0 }, cleared = { 0 };
        t.onSilence = new Runnable() { public void run() { silence[0]++; } };
        t.onCleared = new Runnable() { public void run() { cleared[0]++; } };
        t.clock = 1000000L;
        t.maneuver(CpTurnsTest.maneuver(0, 2, 1, 0, 90, "Synthetic road", 100));
        t.routeGuidance(CpTurnsTest.msg(0, CpTurnsTest.U16, CpTurnsTest.i(1),
                1, CpTurnsTest.ENUM, CpTurnsTest.i(1), 11, CpTurnsTest.STR, CpTurnsTest.s("100"),
                12, CpTurnsTest.ENUM, CpTurnsTest.i(2), 13, CpTurnsTest.U16, CpTurnsTest.i(0)));
        check("fixture initially guides", t.active() && t.hasGuidance());
        c.calls.clear();
        t.clock += CpTurns.REFRESH_MAX_MS;
        t.refresh();
        check("silence asks for real connection check", silence[0] == 1);
        check("silence does not blindly erase a live route", c.calls.isEmpty());
        check("stale display remains visible to watchdog", t.hasGuidance());
        GuidanceSession s = new GuidanceSession();
        s.activity(1000000L);
        check("live connection protected after long straight", !s.shouldClear(1, 1, false, t.clock));
        check("unknown query protected", !s.shouldClear(-1, -1, false, t.clock));
        check("first resume-disconnected sample waits", !s.shouldClear(0, 1, false, t.clock));
        check("second disconnected sample confirmed", s.shouldClear(0, 1, false, t.clock + 2000L));
        t.disconnected();
        check("turn cleared on confirmed end", c.calls.contains(CpTurnsTest.CLEAR_TBT));
        check("remaining trip cleared", c.calls.contains(CpTurnsTest.CLEAR_SUB));
        check("HUD cleared", c.calls.contains(CpTurnsTest.CLEAR_2C));
        check("stock restoration notified", cleared[0] == 1);
        check("cached guidance removed", !t.active() && !t.hasGuidance());
        c.calls.clear();
        t.refresh();
        t.disconnected();
        check("old turn never reappears; cleanup idempotent", c.calls.isEmpty() && cleared[0] == 1);
        System.out.println("Warm resume: " + checks + " checks passed");
    }
}
