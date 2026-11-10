#!/bin/bash
# Exercise the real package uninstall + auto-install functions with isolated head-unit tools.
set -e
B=$(cd "$(dirname "$0")/../.." && pwd)
P=${1:-$B/nemesis-pkg/korea.projection}
T=$(mktemp -d)
trap '/bin/rm -rf "$T"' EXIT
export T P
mkdir -p "$T/bin" "$T/hd/maps/kia/bdpe/kor/260902" "$T/hd/public" "$T/bk" "$T/work" "$T/hd/mods/wireless-carplay-aa"
printf '{"system":[{"region":"KOR"}],"version":"2.4.0"}\n' > "$T/hd/mods/wireless-carplay-aa/mod.json"
printf '{}\n' > "$T/hd/maps/kia/bdpe/kor/260902/car.json"
printf 'test-boot\n' > "$T/boot"
touch "$T/hd/public/wifi-chip" "$T/bk/mod.ours" "$T/bk/mod.tried"
printf '#!/bin/sh\nexec "$@"\n' > "$T/bin/bb"
cat > "$T/bin/hmgapid" <<'TOOL'
#!/bin/sh
printf '%s\n' "$*" >> "$T/calls"
case "$1 $2" in
  'ping ') exit 0;;
  'engine remove') rm -rf "$T/hd/mods/$3";;
  'engine install')
    # A differing signing identity cannot be installed over the old mod.
    [ ! -d "$T/hd/mods/wireless-carplay-aa" ] || exit 3
    mkdir -p "$T/hd/mods/wireless-carplay-aa"
    unzip -q "$3" -d "$T/hd/mods/wireless-carplay-aa";;
  'engine plan')
    if [ -d "$T/hd/mods/wireless-carplay-aa" ]; then
      echo 'change   /system/lib/libleafiaaac.so [wireless-carplay-aa] -> 1'
    else
      echo 'restore  /system/lib/libleafiaaac.so (stock)'
    fi;;
  'engine apply'|'engine verify-map') exit 0;;
  *) echo "Unexpected platform request: $*" >&2; exit 9;;
esac
TOOL
cat > "$T/bin/getprop" <<'TOOL'
#!/bin/sh
case "$1" in
  ro.build.product) echo BDPE.KOR.0000.V039.001.260902;;
  persist.sys.iap2.wifi) echo t;;
  *) echo 1;;
esac
TOOL
printf '#!/bin/sh\necho feature:android.hardware.wifi\n' > "$T/bin/pm"
chmod +x "$T/bin/"*
# Rewrite only test paths in a temporary copy; the production uninstall script is unchanged.
python3 - "$P/scripts/preun.sh" "$T/preun.sh" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
s=s.replace('/data/nemesis/apps/korea.projection', '$P')
s=s.replace('BK=/data/nemesis/backup/korea.projection','BK=$T/bk')
s=s.replace('/data/local/tmp/', '$T/local/')
needle='HOTSPOT_LIB=1 . $P/svc/hotspot.sh'
assert needle in s
s=s.replace(needle,needle+'''
export PATH=$T/bin:/usr/bin:/bin
CONF=$T/hostapd.conf
stop_all() { :; }
stock_ap_on() { return 1; }
remove_app() { :; }
perms_revert() { return 0; }
wifi_unlock() { return 1; }
apon_restore() { return 0; }
''')
Path(sys.argv[2]).write_text(s)
PY
export APP=$P BB_SYS=$T/bin/bb HMGDATA=$T/hd W=$T/work NOTICE=$T/notice PROG=$T/prog BOOT_ID=$T/boot PSTART=1
export PERMS_OURS=$T/bk/perms.ours
bash "$T/preun.sh" > "$T/uninstall.log" 2>&1
[ ! -d "$T/hd/mods/wireless-carplay-aa" ]
[ ! -d "$T/bk" ]
grep -qx 'engine remove wireless-carplay-aa' "$T/calls"
grep -qx 'engine apply' "$T/calls"
[ -f "$T/hd/maps/kia/bdpe/kor/260902/car.json" ]
echo 'PASS: NEMESIS uninstall removes the auto-installed old mod and its markers, preserves car map'
mkdir -p "$T/bk" "$T/work"
BB=$T/bin/bb HOTSPOT_LIB=1 BK=$T/bk . "$P/svc/hotspot.sh"
export PATH=$T/bin:/usr/bin:/bin
BK=$T/bk
WPDIR=$T/no-wireless-projection
KP_HMG=$P/hmgapi
P_ON=1
if setup_hmgapi > "$T/install.log" 2>&1; then :; else cat "$T/install.log"; exit 1; fi
[ -f "$T/hd/mods/wireless-carplay-aa/mod.json" ]
grep -q '2.4.1-k3-test.1' "$T/hd/mods/wireless-carplay-aa/mod.json"
[ -f "$T/bk/mod.ours" ] && [ -f "$T/bk/mod.tried" ]
grep -qx 'state=reboot' "$PROG"
[ "$(grep -c '^engine install ' "$T/calls")" = 1 ]
echo 'PASS: real auto-setup installs the bundled test mod, applies it and requests reboot'
if setup_hmgapi > "$T/repeat.log" 2>&1; then :; else cat "$T/repeat.log"; exit 1; fi
[ "$(grep -c '^engine install ' "$T/calls")" = 1 ]
echo 'PASS: repeating setup does not reinstall the test mod'
