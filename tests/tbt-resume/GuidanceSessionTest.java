package hmgapi.mods.wireless.dipo;

public final class GuidanceSessionTest {
    static int checks;
    static void check(String name, boolean value) {
        if (!value) throw new AssertionError(name);
        checks++;
    }
    public static void main(String[] args) {
        GuidanceSession s = new GuidanceSession();
        s.activity(10000L);
        check("connected route kept despite silence", !s.shouldClear(1, 1, false, 400000L));
        check("unknown connection is not a disconnect", !s.shouldClear(-1, -1, false, 400001L));
        check("first real disconnect is debounced", !s.shouldClear(0, 1, false, 400002L));
        check("short handover kept", !s.shouldClear(0, 1, false, 401000L));
        check("connected cancels the old end", !s.shouldClear(1, 1, false, 401001L));
        check("new absence needs two samples", !s.shouldClear(0, 1, false, 403001L));
        check("resume with stale TBT flag clears", s.shouldClear(0, 1, false, 405001L));
        s.activity(410000L);
        check("new-session generation changed", s.generation() == 2);
        check("new session gets route startup grace", !s.shouldClear(1, 0, false, 411000L));
        check("no-route first sample", !s.shouldClear(1, 0, false, 415000L));
        check("no-route confirmed", s.shouldClear(1, 0, false, 417000L));
        s.activity(420000L);
        check("disconnect first sample", !s.shouldClear(0, 1, false, 420000L));
        check("AA takeover protected", !s.shouldClear(0, 1, true, 422000L));
        check("AA cancels pending clear", !s.shouldClear(0, 1, false, 424000L));
        check("unknown sample cancels pending clear", !s.shouldClear(-1, 0, false, 426000L));
        check("known disconnect after unknown starts anew", !s.shouldClear(0, 0, false, 428000L));
        s.activity(429000L);
        check("fresh phone data cancels old absence", !s.shouldClear(0, 0, false, 430000L));
        check("fresh phone data gets grace even with a lagging connection flag", !s.shouldClear(0, 0, false, 432000L));
        check("absence after fresh-data grace starts anew", !s.shouldClear(0, 0, false, 434000L));
        check("newly confirmed absence", s.shouldClear(0, 0, false, 436000L));
        s.activity(440000L);
        check("unknown guidance with live connection preserved", !s.shouldClear(1, -1, false, 900000L));
        System.out.println("GuidanceSession: " + checks + " checks passed");
    }
}
