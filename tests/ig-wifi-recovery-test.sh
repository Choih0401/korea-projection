#!/bin/bash
# Isolated fake platform: no host kernel/module/Wi-Fi operations are performed.
set -e
B=$(cd "$(dirname "$0")/.." && pwd)
if [ "$1" != --case ]; then
  for c in success third-attempt permanent-failure unsupported-car unsupported-firmware healthy no-evidence unreadable-kernel busy-module two-modules module-loading foreign-package connected supplicant unknown-setting setting-not-off state-corrupt interrupted same-boot exhausted-budget second-failed-boot transient-interface late-interface unload-failed unload-timeout enable-timeout settings-timeout no-module opt-out locked setup-busy boot-window snapshot-timeout abort-after-disable hal-unloaded original-off becomes-busy pending-reboot other-interface missing-module-file missing-boot state-write-failed; do
    "${IG_TEST_SHELL:-bash}" "$0" --case "$c"
  done
  echo 'All IG recovery scenarios passed'
  exit 0
fi
CASE=$2
T=$(mktemp -d)
trap '/bin/rm -rf "$T"' EXIT
BB=$T/bb
printf '#!/bin/sh\nexec "$@"\n' > "$BB"; chmod +x "$BB"
W=$T/work; BK=$T/backup; WLAN=$T/net/wlan0; UPTIME=$T/uptime; BOOT_ID=$T/boot
WPDIR=$T/no-wp; OLDPKG=$T/no-old; IGR_OTHER=$T/no-other; IGR_USB=$T/usb; IGR_MODULES=$T/modules; IGR_NET=$T/net; IGR_SDIO=$T/sdio
mkdir -p "$W" "$BK" "$IGR_NET" "$IGR_SDIO" "$IGR_USB"
printf '300.0 1.0\n' > "$UPTIME"; echo boot-current > "$BOOT_ID"
printf 'bcmdhd 100 0 - Live 0x0\n' > "$IGR_MODULES"
echo 'dhd: failed to download firmware' > "$T/kernel"
echo 1 > "$T/wifi"
PRODUCT=IGPEHEV.KOR.0000.V039.001.260902
ENABLED=0; UNLOADED=0; STABLE_TICKS=0; OFF=0
log() { echo "$*" >> "$T/log"; }
notice() { echo "$*" >> "$T/notice"; }
prog() { printf "%s\n" "$*" > "$T/progress"; }
getprop() { echo "$PRODUCT"; }
stock_ap_on() { return 1; }
running() { [ "$CASE:$1" = supplicant:wpa_supplicant ]; }
cp_count() { if [ "$CASE" = connected ]; then echo 1; else echo 0; fi; }
fix_running() { [ "$CASE" = setup-busy ]; }
prog_final_this_boot() { [ "$CASE" = pending-reboot ]; }
wifi_record() { echo "sanitized diagnostic $1" > "$2"; }
dmesg() { [ "$CASE" != unreadable-kernel ] || return 1; cat "$T/kernel"; }
settings() { cat "$T/wifi"; }
svc() {
  echo "svc $*" >> "$T/commands"
  if [ "$2" = disable ]; then
    OFF=1
    [ "$CASE" = setting-not-off ] || echo 0 > "$T/wifi"
    [ "$CASE" != late-interface ] || mkdir -p "$WLAN"
    [ "$CASE" != hal-unloaded ] || : > "$IGR_MODULES"
    [ "$CASE" != becomes-busy ] || echo "bcmdhd 100 1 x Live 0x0" > "$IGR_MODULES"
    [ "$CASE" != abort-after-disable ] || touch "$BK/ig-wifi-off"
  else
    ENABLED=$((ENABLED + 1)); OFF=0
    echo 1 > "$T/wifi"
    printf 'bcmdhd 100 0 - Live 0x0\n' > "$IGR_MODULES"
    case "$CASE" in permanent-failure|second-failed-boot|transient-interface|original-off) ;;
      third-attempt) [ "$ENABLED" -lt 3 ] || mkdir -p "$WLAN" ;;
      *) mkdir -p "$WLAN" ;;
    esac
  fi
  return 0
}
rmmod() {
  echo "rmmod $*" >> "$T/commands"
  UNLOADED=$((UNLOADED + 1))
  [ "$CASE" != unload-failed ] || return 1
  : > "$IGR_MODULES"
}
. "$B/nemesis-pkg/korea.projection/svc/ig-wifi-recovery.sh"
# Keep a copy of the real timeout helper for dedicated tests; mock command latency here.
igr_run() {
  if [ "$CASE:$1:$3" = unload-timeout:rmmod: ] || [ "$CASE:$1:$3" = enable-timeout:svc:enable ] || [ "$CASE:$1" = snapshot-timeout:wifi_record ]; then return 124; fi
  if [ "$CASE:$1:$OFF" = settings-timeout:settings:1 ]; then return 124; fi
  "$@" > "$W/ig-wifi-command.private" 2>&1
}
igr_pause() {
  if [ "$1" = 2 ] && [ "$CASE" = transient-interface ]; then
    STABLE_TICKS=$((STABLE_TICKS + 1))
    if [ $((STABLE_TICKS % 15)) = 1 ]; then mkdir -p "$WLAN"; else rm -rf "$WLAN"; fi
  fi
}
case "$CASE" in
  unsupported-car) PRODUCT=BDPE.KOR.0000.V039.001.260902 ;;
  unsupported-firmware) PRODUCT=IGPEHEV.KOR.0000.V039.001.260101 ;;
  healthy) mkdir -p "$WLAN" ;;
  no-evidence) echo 'unrelated TX FAILED' > "$T/kernel" ;;
  busy-module) echo 'bcmdhd 100 1 x Live 0x0' > "$IGR_MODULES" ;;
  two-modules) printf 'bcmdhd 100 1 - Live 0\ndhd 100 0 - Live 0\n' > "$IGR_MODULES" ;;
  module-loading) echo 'bcmdhd 100 0 - Loading 0' > "$IGR_MODULES" ;;
  foreign-package) mkdir -p "$IGR_OTHER" ;;
  unknown-setting) echo null > "$T/wifi" ;;
  state-corrupt) echo 'bad state -999 garbage' > "$IGR_STATE" ;;
  interrupted) echo 'previous running 0 1' > "$IGR_STATE" ;;
  same-boot) echo 'boot-current failed 1 3' > "$IGR_STATE" ;;
  exhausted-budget) echo 'previous failed 2 3' > "$IGR_STATE" ;;
  second-failed-boot) echo 'previous failed 1 3' > "$IGR_STATE" ;;
  no-module) : > "$IGR_MODULES" ;;
  original-off) echo 0 > "$T/wifi" ;;
  becomes-busy) : ;;
  pending-reboot) PROG=$T/prog; echo state=reboot > "$PROG" ;;
  other-interface) mkdir -p "$IGR_NET/p2p0" ;;
  missing-module-file) rm "$IGR_MODULES" ;;
  missing-boot) : > "$BOOT_ID" ;;
  state-write-failed) igr_write_state() { return 1; } ;;
  opt-out) touch "$BK/ig-wifi-off" ;;
  locked) mkdir -p "$IGR_LOCK" ;;
  boot-window) echo '10.0 1.0' > "$UPTIME" ;;
esac
# Firmware helpers intentionally return nonzero for failure; assert outcomes, not just exit 0.
if ig_wifi_recover; then RC=0; else RC=$?; fi
case "$CASE" in
  success|third-attempt|late-interface|hal-unloaded)
    [ -d "$WLAN" ]; grep -q ' recovered 0 ' "$IGR_STATE"; [ ! -d "$IGR_LOCK" ]
    [ "$RC" = 0 ]
    if [ "$CASE" = third-attempt ]; then [ "$UNLOADED" = 3 ]; else [ "$UNLOADED" -le 1 ]; fi
    BEFORE=$UNLOADED
    if ig_wifi_recover; then :; fi
    [ "$BEFORE" = "$UNLOADED" ] ;;
  permanent-failure|second-failed-boot|transient-interface|original-off)
    [ "$RC" = 1 ]; [ "$UNLOADED" = 3 ]; [ ! -d "$WLAN" ]
    [ "$CASE" != original-off ] || [ "$(cat "$T/wifi")" = 0 ]
    if [ "$CASE" = second-failed-boot ]; then grep -q ' failed 2 3' "$IGR_STATE"; else grep -q ' failed 1 3' "$IGR_STATE"; fi ;;
  unload-timeout|enable-timeout|settings-timeout|snapshot-timeout)
    [ "$RC" = 124 ]; grep -q ' running ' "$IGR_STATE"; [ ! -d "$IGR_LOCK" ]
    [ "$(cat "$T/wifi")" = 0 ] || [ "$CASE" = snapshot-timeout ] ;;
  unload-failed|setting-not-off|abort-after-disable|becomes-busy)
    [ "$RC" = 1 ]; grep -q ' failed 1 ' "$IGR_STATE"
    [ "$(cat "$T/wifi")" = 1 ] ;;
  *) [ "$UNLOADED" = 0 ]; [ ! -f "$T/commands" ] ;;
esac
[ "$UNLOADED" -le 3 ]
echo "PASS $CASE"
