#!/system/bin/sh
# IG-only recovery of a loaded, unused Broadcom module whose firmware init failed.
# Uses the stock HAL to reload it. Never insmod a foreign driver, force rmmod, or reboot.
# Called by hotspot.sh (same shell); only IGR_* names are used for shared state.
IGR_STATE=${IGR_STATE:-$BK/ig-wifi-recovery.state}
IGR_LOG=${IGR_LOG:-$W/ig-wifi-recovery.txt}
IGR_LOCK=${IGR_LOCK:-$W/ig-wifi-recovery.lock}
IGR_MODULES=${IGR_MODULES:-/proc/modules}
IGR_NET=${IGR_NET:-/sys/class/net}
IGR_SDIO=${IGR_SDIO:-/sys/bus/sdio/devices}
IGR_USB=${IGR_USB:-/storage}
IGR_OTHER=${IGR_OTHER:-/data/nemesis/apps/usbwifi.hotspot}

ig_wifi_target() {
  case "$(getprop ro.build.product 2>/dev/null)" in
    IGPEHEV.KOR.*.260902|IGPE21.KOR.*.260902) return 0 ;;
  esac
  return 1
}
igr_log() {
  log "IG Wi-Fi: $*"
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$IGR_LOG" 2>/dev/null
}
igr_pause() { sleep "$1"; }
igr_off() {
  [ -f "$BK/ig-wifi-off" ] || [ -f "$IGR_USB/usb0/kp-ig-wifi-off" ] || [ -f "$IGR_USB/usb1/kp-ig-wifi-off" ]
}
igr_net_here() {
  [ -d "$WLAN" ] || [ -d "$IGR_NET/wlan1" ] || [ -d "$IGR_NET/p2p0" ]
}
igr_busy() {
  igr_net_here || stock_ap_on || running hostapd || running wpa_supplicant || running dnsmasq \
    || [ "$(cp_count)" != 0 ] || [ -d "$WPDIR" ] || [ -d "$OLDPKG" ] || [ -d "$IGR_OTHER" ]
}
igr_module() {
  # Exactly one supported module. Do not pick an idle row while another is busy.
  $BB awk '$1 == "bcmdhd" || $1 == "dhd" { n++; name=$1; refs=$3; state=$5 }
    END { if (n == 1 && refs == 0 && state == "Live") print name }' "$IGR_MODULES" 2>/dev/null
}
igr_write_state() {
  # boot phase consecutive_failed_boots attempts. Persist before any destructive operation.
  ( umask 077
    printf '%s %s %s %s\n' "$IGR_BOOT" "$1" "$IGR_FAILURES" "$IGR_TRIES" > "$IGR_STATE.tmp.$$" \
      && $BB mv -f "$IGR_STATE.tmp.$$" "$IGR_STATE" )
}
ig_wifi_cancel() {
  # Do not wait for an uninterruptible kernel unload. The running marker remains a breaker.
  if [ -n "$IGR_JOB" ]; then
    kill "$IGR_JOB" 2>/dev/null
    kill -9 "$IGR_JOB" 2>/dev/null
  fi
}
igr_run() {
  IGR_JOB=
  "$@" > "$W/ig-wifi-command.private" 2>&1 &
  IGR_JOB=$!; IGR_T=0
  while kill -0 "$IGR_JOB" 2>/dev/null; do
    if [ "$IGR_T" -ge 15 ]; then
      ig_wifi_cancel
      IGR_JOB=
      return 124
    fi
    igr_pause 1
    IGR_T=$((IGR_T + 1))
  done
  wait "$IGR_JOB"; IGR_RC=$?
  IGR_JOB=
  return "$IGR_RC"
}
igr_read_wifi() {
  igr_run settings get global wifi_on || return $?
  IGR_WIFI_VALUE=$(cat "$W/ig-wifi-command.private" 2>/dev/null)
  case "$IGR_WIFI_VALUE" in 0|1) return 0 ;; esac
  return 1
}
igr_snapshot() {
  igr_run wifi_record "$1" "$W/ig-wifi-$2.txt" || return 1
  # Public hardware identifiers only, never uevent serial/MAC or firmware file contents.
  for IGR_D in "$IGR_SDIO"/*; do
    [ -d "$IGR_D" ] || continue
    for IGR_F in vendor device class; do
      IGR_V=$(cat "$IGR_D/$IGR_F" 2>/dev/null)
      case "$IGR_V" in ''|*[!0-9a-fA-FxX]*) continue ;; esac
      printf 'SDIO %s=%s\n' "$IGR_F" "$IGR_V" >> "$IGR_LOG"
    done
  done
}
igr_finish() {
  if [ "$1" = recovered ]; then
    IGR_FAILURES=0
    rm -f "$BK/wifi.nochip"
    : > "$W/ig-wifi-recovered"
  else
    IGR_FAILURES=$((IGR_FAILURES + 1))
    # Restore only a known original setting. Never guess that null/unknown means off.
    case "$IGR_WIFI_BEFORE" in
      0) igr_run svc wifi disable; IGR_BACK=$? ;;
      1) igr_run svc wifi enable; IGR_BACK=$? ;;
    esac
    if [ "${IGR_BACK:-0}" = 124 ]; then
      igr_log "순정 설정 복구도 시간 초과: 다음 자동 시도 차단"
      # Keep 'running': a hung kernel operation must not be retried after reboot.
      $BB rmdir "$IGR_LOCK" 2>/dev/null
      return 1
    fi
  fi
  igr_write_state "$1" || igr_log "복구 결과 기록 실패: 남은 running 상태로 재시도 차단"
  igr_snapshot "IG Wi-Fi 복구 $1" after
  rm -f "$W/ig-wifi-command.private"
  $BB rmdir "$IGR_LOCK" 2>/dev/null
  return 0
}

ig_wifi_recover() {
  ig_wifi_target || return 0
  igr_off && return 0
  igr_busy && return 0
  # A modem/USB package or normal setup can still own the device: do not overlap.
  [ "${IGR_SETUP:-0}" = 1 ] || { fix_running && return 0; }
  if prog_final_this_boot && $BB grep -q '^state=reboot$' "$PROG" 2>/dev/null; then return 0; fi
  IGR_MOD=$(igr_module)
  [ -n "$IGR_MOD" ] || return 0
  IGR_BOOT=$(cat "$BOOT_ID" 2>/dev/null)
  [ -n "$IGR_BOOT" ] || return 0
  $BB mkdir -p "$BK" "$W"
  IGR_FAILURES=0; IGR_TRIES=0; IGR_OLD_BOOT=; IGR_PHASE=; IGR_OLD_TRIES=
  if [ -f "$IGR_STATE" ]; then
    read IGR_OLD_BOOT IGR_PHASE IGR_FAILURES IGR_OLD_TRIES < "$IGR_STATE"
    case "$IGR_FAILURES:$IGR_OLD_TRIES:$IGR_PHASE" in
      [0-2]:[0-3]:running|[0-2]:[0-3]:failed|[0-2]:[0-3]:recovered) ;;
      *) return 0 ;; # corrupt state is not authorization to unload
    esac
    # One recovery session per boot; interrupted runs and two failed boots need manual reset.
    [ "$IGR_OLD_BOOT" = "$IGR_BOOT" ] && return 0
    [ "$IGR_PHASE" = running ] && { igr_log "지난 복구가 완료되지 않아 자동 복구 차단 (수동 초기화 필요)"; return 0; }
    [ "$IGR_FAILURES" -ge 2 ] && { igr_log "두 부팅 연속 실패: 자동 복구 차단 (수동 초기화 필요)"; return 0; }
  fi
  # Current kernel ring only. Missing/truncated evidence must not trigger a module unload.
  dmesg > "$W/ig-kernel.private" 2>/dev/null || { rm -f "$W/ig-kernel.private"; return 0; }
  $BB grep -i -E 'dhd|bcmdhd|sdio|firmware' "$W/ig-kernel.private" \
    | $BB grep -q -E 'failed to download firmware|si_attach failed|dhd.*(TX|RX) FAILED' || { rm -f "$W/ig-kernel.private"; return 0; }
  rm -f "$W/ig-kernel.private"
  # Wait for the same >=4 minute boot window used by the public diagnostic USB.
  IGR_WAIT=0
  while [ "$IGR_WAIT" -lt 48 ]; do
    IGR_UP=$($BB awk '{ print int($1) }' "$UPTIME" 2>/dev/null)
    case "$IGR_UP" in ''|*[!0-9]*) return 0 ;; esac
    [ "$IGR_UP" -ge 240 ] && break
    igr_busy && return 0
    igr_off && return 0
    igr_pause 5; IGR_WAIT=$((IGR_WAIT + 1))
  done
  [ "$IGR_UP" -ge 240 ] || return 0
  igr_read_wifi || return 0
  IGR_WIFI_BEFORE=$IGR_WIFI_VALUE
  # A failed mkdir cannot steal a live or stale lock from another session.
  $BB mkdir "$IGR_LOCK" 2>/dev/null || return 0
  igr_write_state running || { $BB rmdir "$IGR_LOCK"; return 0; }
  if ! igr_snapshot 'IG Wi-Fi 복구 전' before; then
    igr_log '최초 진단 수집 실패/시간 초과: running 상태로 중단'
    $BB rmdir "$IGR_LOCK" 2>/dev/null
    return 124
  fi
  igr_log "펌웨어 초기화 실패 확인: 순정 서비스로 최대 3회 복구 (모듈 $IGR_MOD)"
  notice 'Korea Projection: 그랜저 Wi-Fi 초기화 복구를 시도합니다. 블루투스가 잠시 끊길 수 있습니다.'
  while [ "$IGR_TRIES" -lt 3 ]; do
    igr_off && break
    igr_busy && break
    IGR_TRIES=$((IGR_TRIES + 1)); igr_write_state running || break
    prog 28 run "그랜저 Wi-Fi 초기화를 복구하는 중입니다 ($IGR_TRIES/3). 잠시 기다려 주세요."
    igr_run svc wifi disable; IGR_STEP_RC=$?
    if [ "$IGR_STEP_RC" != 0 ]; then igr_log "Wi-Fi 끄기 실패 rc=$IGR_STEP_RC"; break; fi
    igr_pause 8
    igr_off && break
    # Do not unload unless the stock service really switched off and the exact module is idle.
    igr_read_wifi; IGR_STEP_RC=$?
    [ "$IGR_STEP_RC" = 0 ] && [ "$IGR_WIFI_VALUE" = 0 ] || break
    if ! igr_net_here; then
      igr_busy && break
      # The HAL may already have removed it during disable; that is not an error.
      if $BB grep -q -E '^(bcmdhd|dhd) ' "$IGR_MODULES"; then
        [ "$(igr_module)" = "$IGR_MOD" ] || break
        if command -v rmmod >/dev/null 2>&1; then
          igr_run rmmod "$IGR_MOD"
        else
          igr_run "$BB" rmmod "$IGR_MOD"
        fi
        IGR_STEP_RC=$?
        if [ "$IGR_STEP_RC" != 0 ] || $BB grep -q "^$IGR_MOD " "$IGR_MODULES"; then
          igr_log "모듈 내리기 실패 rc=$IGR_STEP_RC: 중단"
          break
        fi
      fi
    fi
    igr_run svc wifi enable; IGR_STEP_RC=$?
    if [ "$IGR_STEP_RC" != 0 ]; then igr_log "Wi-Fi 켜기 실패 rc=$IGR_STEP_RC"; break; fi
    # Stable at the end, not merely a momentary wlan0 appearance.
    IGR_POLL=0; IGR_STABLE=0
    while [ "$IGR_POLL" -lt 15 ]; do
      igr_pause 2; IGR_POLL=$((IGR_POLL + 1))
      if [ -d "$WLAN" ]; then IGR_STABLE=$((IGR_STABLE + 1)); else IGR_STABLE=0; fi
    done
    if [ "$IGR_STABLE" -ge 3 ]; then
      igr_log "복구 $IGR_TRIES/3: wlan0 3회 연속 확인 (핫스팟은 별도 확인)"
      igr_finish recovered
      return 0
    fi
    igr_log "복구 $IGR_TRIES/3: wlan0 안정화 실패"
  done
  # A timed-out rmmod may still be uninterruptible. Do not launch another HAL operation.
  if [ "${IGR_STEP_RC:-0}" = 124 ]; then
    igr_log '명령 시간 초과: running 상태 유지, 이후 자동 복구 차단'
    notice 'Korea Projection: Wi-Fi 복구 명령이 끝나지 않아 자동 시도를 차단했습니다. Launch로 기록을 저장해 주세요.'
    $BB rmdir "$IGR_LOCK" 2>/dev/null
    return 124
  fi
  igr_log '복구 중단: 드라이버/부품 원인은 미확정 (실패 자료 보존)'
  igr_finish failed || return 124
  notice 'Korea Projection: 그랜저 Wi-Fi 복구에 실패했습니다. Launch로 진단 파일을 저장해 주세요. 하드웨어 고장으로 확정한 것은 아닙니다.'
  return 1
}
