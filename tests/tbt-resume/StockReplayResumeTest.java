package hmgapi.mods.wireless;
public final class StockReplayResumeTest {
    static void check(String name, boolean value) { if (!value) throw new AssertionError(name); }
    public static void main(String[] args) {
        StockReplay r = new StockReplay();
        check("idle navigation untouched", r.phoneEnded(0L).backupGen == 0);
        r.call("turn", new Object(), new Object(), new Object[] { 8 }, true, 1L);
        r.call("lane", new Object(), new Object(), new Object[] { 0 }, true, 2L);
        StockReplay.Out end = r.phoneEnded(10L);
        check("end notification schedules without another stock call", end.backupGen != 0);
        check("duplicate end does not restart", r.phoneEnded(20L).backupGen == 0);
        StockReplay.Out back = r.backup(end.backupGen);
        check("all remembered stock frames restored", back.resend.size() == 2);
        check("restore finishes once", r.backup(end.backupGen).resend.isEmpty());
        r.call("turn", null, null, new Object[] { 8 }, true, 30L);
        end = r.phoneEnded(40L);
        r.call("turn", null, null, new Object[] { 67 }, true, 50L);
        check("new route cancels previous restoration", r.backup(end.backupGen).resend.isEmpty());
        GuidanceGate gate = new GuidanceGate();
        check("first disconnected read preserves guidance", gate.guiding(false, 0, true, 10000L));
        check("short disconnect preserves guidance", gate.guiding(false, 0, true, 11000L));
        check("handover cancels absence", gate.guiding(false, 1, true, 12000L));
        check("next absence starts anew", gate.guiding(false, 0, true, 13000L));
        check("confirmed disconnected overrides stale CP flag", !gate.guiding(false, 0, true, 15000L));
        check("unknown query preserves guidance", gate.guiding(false, -1, true, 16000L));
        check("AA takeover always preserved", gate.guiding(true, 0, true, 17000L));
        check("normal route end is immediate", !gate.guiding(false, 1, false, 18000L));
        System.out.println("StockReplay resume and guidance gate: 15 checks passed");
    }
}
