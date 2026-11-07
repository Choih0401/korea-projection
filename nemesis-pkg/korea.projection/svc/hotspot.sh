#!/system/bin/sh
# korea.projection: the wireless CarPlay access point on Korean head units (tested: Niro DEPEHEV.KOR 260902;
# 시험 지원: 쏘나타 DN8 DN822HEV, 그랜저 하이브리드 IGPEHEV, 벨로스터 N JSN .KOR 260902).
# There the stock hotspot call (setWifiApEnabledForConnectivity) does nothing, but the stock
# hostapd on wlan0 (nl80211) works. NEMESIS's svcmgr starts this at boot (mode=restart); it
# waits for Android, starts hostapd + dnsmasq with the CarPlay network from softap.conf, then
# keeps them up. Output goes to /data/nemesis/logs/korea.projection/ap.log; the passphrase
# is never written there.
# Test hooks: HOTSPOT_LIB=1 only defines the functions; BB, SRC, CONF, W, PROP override paths.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
APP=${APP:-/data/nemesis/apps/korea.projection}
# busybox 고르기(1.6.0). 내비에 busybox(1.8.1)가 있으면 지금처럼 그것을 쓴다(니로 등 확인된 차는 바뀌지 않음).
# 1.5.6은 bin/busybox를 함께 넣지 않는다(1.6.x에서 다시 넣는다): 없는 내비는 아래에서 BB_OK=0이 되어 1.5.5처럼 대기한다.
# 없는 내비(K3 BDPE·K8 GL3HEV, tcc803x, #15·#19)는 패키지에 함께 넣은 busybox(1.36.1, bin/busybox)를 쓴다.
# BB를 미리 정해 두면(테스트, 예전 호출) 그대로 쓴다. 쓸 수 있는지는 한 번 실행해 보고 BB_OK에 남긴다.
BB_SYS=${BB_SYS:-/system/bin/busybox}
BB_OWN=${BB_OWN:-$APP/bin/busybox}
if [ -z "$BB" ]; then
  if [ -x $BB_SYS ]; then BB=$BB_SYS
  else
    # zip에서 풀 때 실행 권한이 빠질 수 있다: 우리 파일이므로 한 번 준다(toolbox chmod)
    [ -f $BB_OWN ] && [ ! -x $BB_OWN ] && chmod 755 $BB_OWN 2>/dev/null
    BB=$BB_OWN
  fi
fi
# 내비의 busybox는 예전처럼 실행 파일인지만 본다(1.8.1에 true가 있는지 모른다: 확인된 차가 멈추지 않게).
# 함께 넣은 busybox는 실제로 실행해 본다(/data가 noexec이거나 CPU가 맞지 않으면 쓰지 않는다).
BB_OK=0
if [ "$BB" = "$BB_OWN" ]; then "$BB" true >/dev/null 2>&1 && BB_OK=1
else [ -x "$BB" ] && BB_OK=1; fi
# 프로세스 목록. 1.36.1은 기본 출력에 상태 칸이 없어 좀비([hostapd])를 " Z "로 거르지 못한다: 함께 넣은
# busybox일 때만 상태 칸을 달라고 한다(PID STAT COMMAND, 첫 칸 PID는 1.8.1과 같다). 1.8.1의 -o 지원은 확인 안 함.
# 경로 문자열로 판단한다: 같은 파일을 다른 경로로 BB에 넘기면 기본 ps가 되어 좀비를 거르지 못한다.
if [ "$BB" = "$BB_OWN" ]; then PS="$BB ps -o pid,stat,args"; else PS="$BB ps"; fi
SRC=${SRC:-/data/misc/wifi/softap.conf}
# 짧게 유지: busybox ps가 명령줄을 약 80칸에서 잘라 "hostapd <경로>"가 약 50자를 넘으면 찾지 못한다
CONF=${CONF:-/data/misc/wifi/hostapd-kp.conf}
W=${W:-/data/local/tmp/korea.projection}
AP_IP=192.168.43.1
# busybox ps cuts command lines near 80 columns: match the start of dnsmasq's (netd starts it the
# same way, but the stock hotspot never runs on this car)
DNSMASQ='dnsmasq --keep-in-foreground --no-resolv --no-poll'
# 이 패키지가 동작하는 차. 목록에 없는 차(해외 차)는 로그만 남기고 대기한다.
# - CARS_OK: 차에서 동작을 확인한 차 (니로 하이브리드)
# - CARS_TRY: 제보(Car Report, 순정 체크섬)로 지도를 만들어 패키지에 넣었고, 차에서는 아직 확인하지 않은 차
#   (쏘나타 하이브리드 DN8 HMG-API #91, 그랜저 하이브리드 IG #7, 벨로스터 N #8). 확인되면 CARS_OK로 옮긴다.
# - CARS_AUTO: 그 밖의 모든 한국 차(자동 시험, 1.5.2 소유자 결정). 패키지에 지도가 없으면 HMG-API가 그 차의
#   파일로 지도를 만들고(engine map-car --write) 그 차에서 확인(verify-map)한 뒤에만 무선 모드를 적용한다.
#   무선 모드(한국 차 빌드)도 Wi-Fi 칩이 있는 한국 차만 받는다. 결과는 제보 파일(3-log.txt)로 본다.
CARS_OK='DEPEHEV.KOR.*.260902'
CARS_TRY='DN822HEV.KOR.*.260902 IGPEHEV.KOR.*.260902 JSN.KOR.*.260902 IGPE.KOR.*.260902'
CARS_AUTO='*.KOR.*'
CARS="$CARS_OK $CARS_TRY $CARS_AUTO"
# $1(제품명)이 $2(공백으로 나눈 패턴 목록)의 하나와 맞는가.
# case 패턴에는 변수로 '|'를 넘길 수 없어 하나씩 본다. 목록을 나눌 때 '*'가 파일 이름으로 풀리지 않게
# 잠시 set -f 한다(이미 -f면 그대로 둔다).
car_in() {
  _cr=1; _ci=$IFS; IFS=' '
  case $- in *f*) _cf=0 ;; *) _cf=1; set -f ;; esac
  for _ck in $2; do case "$1" in $_ck) _cr=0; break ;; esac; done
  [ $_cf = 1 ] && set +f
  IFS=$_ci
  return $_cr
}
# 확인된 차가 아니면(시험 지원·자동 시험) HMG-API 무선 모드가 설치·켜짐이고 **적용까지 된** 뒤에만 핫스팟을 켠다
# (wlan0을 가져간다). 모드 없이는 무선 카플레이가 시작되지 않고 순정 Wi-Fi만 끊기기 때문이다(2026-11-06 니로에서 확인).
# 적용됐는지는 모드가 적용할 때 거는 속성 persist.sys.iap2.wifi=t로 본다(차주가 앱에서 적용한 경우도 잡힌다).
# 확인된 차는 예전처럼 바로 켠다. 모드 위치: /data/hmgapi/mods/<id>/mod.json, 꺼짐 표시 .disabled
try_ready() {
  car_in "$1" "$CARS_OK" && return 0
  [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $HMGDATA/mods/$MOD_ID/.disabled ] \
    && [ "$(getprop persist.sys.iap2.wifi 2>/dev/null)" = t ]
}
OLDPKG=${OLDPKG:-/data/nemesis/apps/niro.carplay.hotspot}
WPDIR=${WPDIR:-/data/nemesis/apps/wireless.projection}

log() { echo "$(date '+%m-%d %H:%M:%S') $*"; }

# the head unit's busybox (1.8.1) od only knows -b: bytes come as 3-digit octal
# octal bytes -> string
decode() {
  _s=""
  for _b in "$@"; do _s="$_s$($BB printf "\\$_b")"; done
  # mksh의 echo는 \ 이스케이프를 해석하므로 printf %s로 그대로 낸다
  $BB printf '%s\n' "$_s"
}

# one 3-digit octal byte -> decimal (digit by digit: no leading-zero ambiguity)
o2d() {
  _r=${1#?}
  echo $(( ${1%??}*64 + ${_r%?}*8 + ${_r#?} ))
}

# softap.conf on this unit (version 3) isn't stock WifiApConfigStore: Java writeUTF strings
# (2-byte length + bytes): S1 hotspot SSID, S2 CarPlay SSID, S3, S4 CarPlay passphrase.
# Lengths are checked before any arithmetic: a bad $(( )) kills the whole script.
parse_conf() {
  NS=0
  [ -s "$1" ] || return 1
  # od -b lines: 7-digit offset, then 3-digit bytes; keep the bytes only
  set -- $(for _t in $($BB od -b -v "$1"); do [ ${#_t} -eq 3 ] && echo $_t; done)
  N=$#
  [ $N -ge 4 ] || return 1
  i=0
  for _t in "$@"; do eval "o$i=$_t; b$i=$(o2d $_t)"; i=$((i+1)); done
  i=0
  while [ $((i+2)) -lt $N ]; do
    eval "_L=\$(( b$i*256 + b$((i+1)) ))"
    if [ $_L -ge 1 ] && [ $_L -le 63 ] && [ $((i+2+_L)) -le $N ]; then
      _ok=1; j=$((i+2))
      while [ $j -lt $((i+2+_L)) ]; do
        eval "_v=\$b$j"
        if [ $_v -lt 32 ] || [ $_v -gt 126 ]; then _ok=0; break; fi
        j=$((j+1))
      done
      if [ $_ok -eq 1 ]; then
        B=""; j=$((i+2))
        while [ $j -lt $((i+2+_L)) ]; do eval "B=\"\$B \$o$j\""; j=$((j+1)); done
        NS=$((NS+1))
        eval "S$NS=\$(decode \$B)"
        i=$((i+2+_L)); continue
      fi
    fi
    i=$((i+1))
  done
}

# 1.5.6: 5GHz 149번으로 띄운다. 순정 핫스팟 기본값(softap.conf)도 5GHz 149번이다.
# 폭은 순정 netd의 149번 설정과 같은 40MHz(HT40+). 20MHz로는 재부팅 뒤 아이폰이 스스로 붙지 않았다(2026-11-07 니로).
# 니로에서 이 설정으로 AP가 뜨고 아이폰 카플레이가 연결됨을 확인했다(2026-11-07 5GHz 시험 USB, 국가 설정 없이).
# 순정처럼 2.4GHz로 되돌아가는 경로는 두지 않는다(소유자 결정). 대신 Wi-Fi 연결·끊김을 ap.log에 남긴다(wifi_events).
write_conf() {
  $BB cat > $CONF <<CONFEOF
interface=wlan0
driver=nl80211
ctrl_interface=/data/misc/wifi/hostapd
ssid=$S2
channel=149
hw_mode=a
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
ieee80211n=1
max_num_sta=5
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=$S4
CONFEOF
  # hostapd drops to the wifi user (1010): readable like the stock hostapd.conf
  $BB chown 1000:1010 $CONF; $BB chmod 660 $CONF
}

# a live process by name; a zombie ([hostapd], state Z) doesn't count
running() { $PS | $BB grep -v grep | $BB grep -v " Z " | $BB grep -q "$1"; }
# 우리 것이 아닌 hostapd(순정 핫스팟)가 살아 있는가: 우리 것은 설정 파일 경로($CONF)로 가린다
stock_ap_on() { $PS | $BB grep -v grep | $BB grep -v " Z " | $BB grep -v "$CONF" | $BB grep -q hostapd; }

up() {
  $BB ifconfig wlan0 $AP_IP netmask 255.255.255.0 up 2>/dev/null
  if ! running "hostapd $CONF"; then
    hostapd $CONF >/dev/null 2>&1 &
    sleep 4
    $BB ifconfig wlan0 $AP_IP netmask 255.255.255.0 up 2>/dev/null
    log "hostapd 시작"
    # 1.5.6: 5GHz를 받지 않는 차라면 hostapd가 바로 끝난다. 2.4GHz로 되돌리지는 않고(소유자 결정) 기록만 남긴다.
    running "hostapd $CONF" || log "hostapd가 4초 안에 꺼짐(5GHz $($BB awk -F= '$1 == "channel" { print $2 }' $CONF 2>/dev/null)번을 못 띄웠을 수 있음)"
  fi
  if ! running "$DNSMASQ"; then
    # same style as netd: bare --pid-file (no /var/run here)
    dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file \
      --interface=wlan0 --bind-interfaces \
      --dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 >/dev/null 2>&1 &
    log "dnsmasq 시작"
  fi
}

# only our own hostapd and dnsmasq (matched by their command lines)
stop_ours() {
  for p in $($PS | $BB grep -v grep | $BB grep -E "hostapd $CONF|$DNSMASQ" | $BB awk '{print $1}'); do
    kill $p 2>/dev/null
  done
}
stop_ap() {
  stop_ours
  killlog
}

# 확인된 차가 아니면, 다른 hostapd(순정 핫스팟 등)가 돌 때 우리 핫스팟을 멈추고 비켜 준다(wlan0을 다투지 않게).
# 0: 비켜 줌(이번 회차는 아무것도 하지 않음), 1: 우리 핫스팟을 돌려도 됨. 로그는 상태가 바뀔 때만 남긴다($W/ap.yield).
# 모드가 적용되면 순정 핫스팟 메뉴가 꺼지므로(featurexml) 보통은 일어나지 않지만, 적용 직후 재부팅 전에는 있을 수 있다.
ap_yield() {
  if ! car_in "$prod" "$CARS_OK" && stock_ap_on; then
    if [ ! -f $W/ap.yield ]; then
      : > $W/ap.yield; stop_ours
      log "다른 hostapd가 돌고 있음(순정 핫스팟 등): 우리 핫스팟을 멈추고 기다림"
    fi
    return 0
  fi
  if [ -f $W/ap.yield ]; then
    rm -f $W/ap.yield; log "다른 hostapd가 멈춤: 우리 핫스팟을 다시 켬"
  fi
  return 1
}

# --- Wi-Fi 잠금 (1.5.5) ---
# 우리가 wpa_supplicant를 멈추면 Android Wi-Fi 서비스가 "Connection lost, restart supplicant"로 드라이버(bcmdhd)를
# 내렸다 올리고 wpa_supplicant를 다시 띄운다. 그때 우리 hostapd가 죽어 30초마다 반복된다(그랜저 #12·#17·#18,
# 쏘렌토 #16, 순정으로 되돌린 니로 2026-11-07에서 같은 로그로 확인).
# 니로가 11-03~11-06 무선 카플레이를 쓸 수 있었던 것은 11-02 실험이 남긴 root 소유 Wi-Fi 설정 파일 때문이었다:
# Wi-Fi HAL이 그 파일 권한을 못 바꿔 "Cannot set RW … Wi-Fi will not be enabled"로 wpa_supplicant를 띄우지 못하고,
# 드라이버만 올린 채 멈춘다. 그래서 우리 hostapd를 방해하지 않는다.
# 1.5.5는 그 상태를 의도적으로 만든다: 설정 파일을 root:root 660으로 두고 crc32 파일을 치운다(니로에서 검증된 그대로).
# 원래 소유자·권한과 crc32 파일은 $BK에 남겨 두고, 패키지를 지울 때(preun) 그대로 되돌린다.
# 영향: 일반 Wi-Fi 접속(클라이언트)을 쓸 수 없다. 한국 내수 펌웨어에는 그 메뉴가 없다.
WCONF=${WCONF:-/data/misc/wifi/wpa_supplicant.conf}
WCRC=${WCRC:-${WCONF%/*}/wpa_supplicant_crc32.conf}
WLAN=${WLAN:-/sys/class/net/wlan0}
WIFI_WAIT=${WIFI_WAIT:-9}
# 연달아 wpa_supplicant가 다시 뜬 회차가 이것을 넘으면 잠금이 듣지 않는 것: 한 번 알린다(핫스팟은 계속 지킨다)
SUPP_MAX=${SUPP_MAX:-3}
ns=0
f_owner() { $BB ls -ln "$1" 2>/dev/null | $BB awk '{ print $3 ":" $4 }'; }
f_perm() { $BB ls -ln "$1" 2>/dev/null | $BB awk '{ p = 0; s = substr($1, 2, 9)
  for (i = 0; i < 3; i++) { d = 0; if (substr(s, i*3+1, 1) == "r") d += 4; if (substr(s, i*3+2, 1) == "w") d += 2; if (substr(s, i*3+3, 1) != "-") d += 1; p = p * 10 + d }
  printf "%03d\n", p }'; }
# 잠금. 0: 잠겨 있음(이번에 잠갔거나 원래 잠김), 1: 설정 파일이 아직 없음(Wi-Fi 서비스가 처음 켤 때 만든다), 2: 실패
# 원래 상태 기록은 한 번만($BK/wpaconf.orig: "<소유자> <권한>"), crc32 파일은 $BK/wpacrc.bak + .orig로.
wifi_lock() {
  [ -f $WCONF ] || return 1
  _o=$(f_owner $WCONF)
  if [ "$_o" = 0:0 ] && [ ! -e $WCRC ]; then return 0; fi
  $BB mkdir -p $BK
  if [ ! -f $BK/wpaconf.orig ]; then
    _p=$(f_perm $WCONF)
    case "$_o $_p" in [0-9]*:[0-9]*" "[0-7][0-7][0-7]) ;; *) lock_fail "설정 파일 소유자·권한을 읽지 못함 ($_o $_p)"; return 2 ;; esac
    echo "$_o $_p" > $BK/wpaconf.orig
  fi
  if [ -e $WCRC ] && [ ! -f $BK/wpacrc.orig ]; then
    $BB cp -f $WCRC $BK/wpacrc.bak && echo "$(f_owner $WCRC) $(f_perm $WCRC)" > $BK/wpacrc.orig || { lock_fail "crc32 파일 백업 실패"; return 2; }
  fi
  # 소유자를 먼저 바꾸고 확인한 뒤에 crc32를 치운다(바꾸지 못했는데 crc32만 없으면 HAL이 파일을 지운다: A/B 시험)
  $BB chown 0:0 $WCONF && $BB chmod 660 $WCONF
  [ "$(f_owner $WCONF)" = 0:0 ] && rm -f $WCRC
  if [ "$(f_owner $WCONF)" = 0:0 ] && [ ! -e $WCRC ]; then log "Wi-Fi 잠금: 설정 파일을 root 소유로(원래 $(cat $BK/wpaconf.orig))"; return 0; fi
  lock_fail "지금 소유자 $(f_owner $WCONF)"; return 2
}
# 잠금 실패는 부팅마다 한 번만 기록한다(30초마다 ap.log가 쌓이지 않게)
lock_fail() {
  [ -f $W/wifilock.fail ] && [ "$(cat $W/wifilock.fail 2>/dev/null)" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ] && return 0
  cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} > $W/wifilock.fail 2>/dev/null
  log "Wi-Fi 잠금 실패: $1"
}
# 잠금 되돌리기(preun): 원래 소유자·권한, crc32 파일. 설정 파일 내용은 바꾸지 않았다.
wifi_unlock() {
  if [ -f $BK/wpaconf.orig ] && [ -f $WCONF ]; then
    read _o _p < $BK/wpaconf.orig
    $BB chown $_o $WCONF; $BB chmod $_p $WCONF
  fi
  if [ -f $BK/wpacrc.orig ] && [ -f $BK/wpacrc.bak ]; then
    read _o _p < $BK/wpacrc.orig
    $BB cp -f $BK/wpacrc.bak $WCRC && $BB chown $_o $WCRC && $BB chmod $_p $WCRC
  fi
}
# 대기만 한다. sleep을 뒤에서 돌리고 wait로 기다려야 TERM이 오면 바로 trap이 돈다(앞에서 돌리면 최대 1시간 늦음).
# mode=restart: 끝내지 않는다(svcmgr가 죽은 횟수를 세지 않게)
idle_forever() { while true; do sleep 3600 & wait $!; done; }
# 시작할 때 wlan0을 hostapd에 넘긴다: 드라이버는 Wi-Fi를 켜야 올라온다. 설정 파일이 없던 차는 켜는 동안 Wi-Fi
# 서비스가 만들므로 그 뒤에 잠근다. 잠근 뒤 wpa_supplicant를 멈추면 Wi-Fi 서비스가 한 번 다시 시작하려다 실패하고
# 드라이버만 남는다(약 6초). 그래서 wlan0이 다시 생길 때까지 최대 20초 기다린다.
take_wlan0() {
  wifi_lock; _lk=$?
  svc wifi enable; sleep $WIFI_WAIT
  [ $_lk = 1 ] && { wifi_lock; _lk=$?; }
  if running wpa_supplicant; then
    $BB killall wpa_supplicant 2>/dev/null
    _i=0
    while [ $_i -lt 10 ]; do sleep 2; _i=$((_i+1)); [ -d $WLAN ] && ! running wpa_supplicant && [ $_i -ge 4 ] && break; done
  fi
  return 0
}
# 자동 설정(fix_perms → setup_hmgapi, 부팅 120초 뒤)이 아직 할 일이 있는가: 무선 모드가 없고, 다시 하지 않기로 한
# 기록(mod.tried, automap.bad, wifi.nochip)도 없고, wireless.projection도 없을 때. 1.5.3 그랜저IG 2.5(#2)는 서비스가
# 2분 간격으로 다시 시작돼 자동 설정이 한 번도 돌지 못했다(재부팅 반복 추정). 그래서 설정 중임을 알린다.
# 안내는 설치마다 한 번만($BK/setup.told): 설정이 조용히 끝나는 경로(지도 실패 기록, 순정 핫스팟 켜짐 등)에서
# 부팅마다 뜨지 않게.
setup_pending() {
  [ ! -f $BK/setup.told ] && [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $BK/mod.tried ] \
    && [ ! -f $BK/automap.bad ] && [ ! -f $BK/wifi.nochip ] && [ ! -s $BK/map.bad ] && [ ! -d $WPDIR ] \
    && [ -d $HMGDATA/maps ] && command -v hmgapid >/dev/null 2>&1
}
# --- Wi-Fi 연결 기록 (1.5.6) ---
# 5GHz로 바꾼 뒤 연결이 얼마나 자주·언제 끊기는지 보려고, 30초마다 커널 로그에서 새로 생긴 일만 ap.log에 남긴다.
# 남기는 것: AP 채널, AP 올라옴, 기기 연결(Wi-Fi 인증 끝)·끊김, 칩 응답 없음. 기기 주소(MAC)는 남기지 않는다.
# 어디까지 남겼는지는 $W/ktime("<부팅 id> <커널 초>")에 둔다: 재부팅하면 커널 시각이 0부터라 부팅 id가 다르면 처음부터.
KT=${KT:-$W/ktime}
CPN=${CPN:-$W/cpn}
wifi_events() {
  _bid=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null); _bid=${_bid:-none}
  _last=0
  if [ -f $KT ]; then read _kb _kl < $KT; [ "$_kb" = "$_bid" ] && _last=${_kl:-0}; fi
  # 먼저 관심 있는 줄만 거른다(버퍼 약 130KB를 30초마다 awk로 다 보지 않게). 시각은 정규식 없이 [ ] 사이를 꺼낸다.
  # HANG: 대문자 HANG이 든 줄 중 "NETDEV_CHANGE"(유선 카플레이 ncm0 등)는 뺀다.
  dmesg 2>/dev/null | $BB grep -E 'target channel\(|AP/GO Link up|M4 of 4way|Disconnect STA|HANG' | $BB awk -v last="$_last" '
    { i = index($0, "["); j = index($0, "]"); if (i == 0 || j <= i) next
      s = substr($0, i + 1, j - i - 1); while (substr(s, 1, 1) == " ") s = substr(s, 2); tm = s + 0
      if (tm <= last + 0) next
      e = ""
      if (index($0, "target channel(") > 0) { c = $0; sub(/.*target channel\(/, "", c); sub(/\).*/, "", c); e = "AP 채널 " c }
      else if (index($0, "AP/GO Link up") > 0) e = "AP 올라옴"
      else if (index($0, "M4 of 4way") > 0 && index($0, "[RX]") > 0) e = "기기 연결(Wi-Fi 인증 끝)"
      # hostapd가 시작할 때 모든 기기를 비우는 줄(브로드캐스트 주소)은 끊김으로 세지 않는다
      else if (index($0, "Disconnect STA") > 0) { if (index(tolower($0), "ff:ff:ff:ff:ff:ff") == 0) e = "기기 연결 끊김" }
      else if (index($0, "HANG") > 0 && index($0, "CHANGE") == 0) e = "Wi-Fi 칩 응답 없음(HANG)"
      if (e != "") print "E Wi-Fi: " e " (커널 " int(tm) "초)"
      # 기억할 시각은 숫자로 바꾸지 않고 글자 그대로(awk가 773.805023을 773.805로 줄여 같은 줄을 다시 남기지 않게)
      if (tm > mxn) { mxn = tm; mx = s } }
    END { if (mxn > 0) print "T " mx }' > $W/kev 2>/dev/null
  [ -f $W/kev ] || return 0
  while IFS= read -r _l; do
    case "$_l" in
      "E "*) log "${_l#E }" ;;
      "T "*) echo "$_bid ${_l#T }" > $KT ;;
    esac
  done < $W/kev
  rm -f $W/kev
  return 0
}
# 카플레이 연결 수(ESTABLISHED)가 바뀌면 남긴다
cp_watch() {
  _n=$($BB netstat -tn 2>/dev/null | $BB grep "$AP_IP:7000 " | $BB grep -c ESTABLISHED)
  _o=$(cat $CPN 2>/dev/null)
  if [ "${_n:-0}" != "${_o:-0}" ]; then log "카플레이 연결 ${_o:-0} → ${_n:-0}"; echo "${_n:-0}" > $CPN; fi
  return 0
}

# 30초마다 한 번: 잠금을 지키고(Wi-Fi 서비스가 설정 파일을 새로 만들었으면 다시 잠금), wpa_supplicant가 다시 떴으면
# 멈춘다. 연달아 SUPP_MAX번을 넘으면 잠금이 듣지 않는 것이라 한 번 알린다($BK/wifilock.told).
ap_tick() {
  # 바꿀 때만 로그를 남긴다(Wi-Fi 서비스가 파일을 다시 만들어 다시 잠근 일을 기록으로 남기려고)
  wifi_lock
  if running wpa_supplicant; then
    log "wpa_supplicant가 다시 켜져서 멈춤"
    $BB killall wpa_supplicant 2>/dev/null
    ns=$((ns+1))
    if [ $ns -gt $SUPP_MAX ] && [ ! -f $BK/wifilock.told ]; then
      $BB mkdir -p $BK; : > $BK/wifilock.told
      log "Wi-Fi 잠금이 듣지 않음: wpa_supplicant가 ${SUPP_MAX}번 넘게 이어서 다시 뜸"
      toast "Korea Projection: 무선 카플레이 핫스팟이 자꾸 끊깁니다. USB를 꽂고 Launch로 제보 파일을 만들어 보내 주세요."
    fi
  else
    ns=0
  fi
  return 0
}

# --- 설치 진행 기록 (1.5.5): 상태 화면 앱이 1초마다 읽어 진행 막대로 보여 준다 ---
# key=value 줄, 누구나 읽을 수 있게(644). 비밀값 없음. printf는 busybox로만 있다(셸·toolbox에 없음).
#   pct: 0~100, state: run(진행 중)|done(준비됨)|reboot(재부팅 필요)|fail(실패), stage: 지금 단계(한국어),
#   start: 이번 진행을 시작한 시각(초), t: 마지막으로 쓴 시각(초), boot: 이번 부팅 id(앱이 지난 부팅 기록을 가려낸다)
PROG=${PROG:-/data/local/tmp/korea-projection-progress.txt}
PSTART=${PSTART:-$(date +%s 2>/dev/null)}
prog() {
  ( umask 022
    $BB printf 'pct=%s\nstate=%s\nstage=%s\nstart=%s\nt=%s\nboot=%s\n' "$1" "$2" "$3" "$PSTART" "$(date +%s)" \
      "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" > $PROG.tmp \
      && $BB chmod 644 $PROG.tmp && $BB mv -f $PROG.tmp $PROG ) 2>/dev/null
  return 0
}
# 이번 부팅에 "재부팅 필요"나 "실패"를 이미 썼는가
prog_final_this_boot() {
  $BB grep -q -E '^state=(reboot|fail)$' $PROG 2>/dev/null \
    && [ "$($BB awk -F= '$1 == "boot" { print $2 }' $PROG 2>/dev/null)" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]
}
# 진행 기록이 지금 "진행 중"인가(설정 중인 fix_perms가 쓰는 중)
fix_busy() { $BB grep -q '^state=run$' $PROG 2>/dev/null; }
# 무선 설정이 이미 끝난 상태인가: 무선 모드가 있고 켜져 있고 적용됐다(persist.sys.iap2.wifi=t)
setup_done() {
  [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $HMGDATA/mods/$MOD_ID/.disabled ] \
    && [ "$(getprop persist.sys.iap2.wifi 2>/dev/null)" = t ]
}

# 서비스가 끝날 때(TERM)와 패키지를 지울 때만: 핫스팟에 더해 뒤에서 도는 권한 파일 확인(fix_perms)도 멈춘다.
# 시작할 때 부르는 stop_ap는 이것을 건드리지 않는다 (방금 띄운 확인 작업을 죽이지 않게)
stop_all() {
  stop_ap
  if fix_running; then set -- $(cat $W/fix.pid); kill $1 2>/dev/null; fi
  rm -f $W/fix.pid
  # 설치 중에 서비스가 멈추면 진행 기록이 "진행 중"으로 남지 않게(설치 작업을 멈춘 뒤에 쓴다)
  fix_busy && prog 100 fail "설치가 중간에 멈췄습니다. 내비를 재부팅하면 다시 진행합니다."
  return 0
}

# log.pid의 프로세스가 우리 로그 파이프(마지막 단계 uniq)일 때만 죽인다 (/data/local/tmp는 재부팅 뒤에도
# 남아 예전 pid가 다른 프로세스를 가리킬 수 있다). 마지막 단계가 죽으면 앞의 grep과 logcat은 SIGPIPE로 끝난다.
killlog() {
  _p=$(cat $W/log.pid 2>/dev/null)
  [ -n "$_p" ] && $BB grep -q -E 'logcat|grep|uniq' /proc/$_p/cmdline 2>/dev/null && kill $_p 2>/dev/null
  rm -f $W/log.pid
}

# $W/debug가 있을 때만: 카플레이 관련 logcat을 $W/cp.log에 남긴다(폰 이름이 들어가므로 기본은 꺼짐).
# 이 헤드유닛의 logcat은 -f와 함께 태그 필터를 무시하므로 grep으로 거른다.
# 길안내 중에는 분당 약 500KB가 쌓여(2026-11-06 run3) 쓸모없는 줄을 버린다:
#  - iAPSendMessage의 "done with"와 "Command Received": 보낸 줄마다 따라붙는 확인 줄
#  - getCANSTatus = true(ClusterService)와 getCANStatus(NavigationCluster): 몇 초마다 같은 줄
#  - updateTPCrossroadName(ClusterService): 교차로 이름. 지나간 경로가 드러나고, 이름이 번갈아 나와 uniq로
#    줄지도 않는다(2026-11-06 운행 46분에 1만 줄, 로그 크기의 약 15%).
# 보낸 줄 "iAPSendMessage() : data(…) size(N)"은 남긴다: 정상 세션에서는 차 위치(크기 57/84/100)가
# 1초마다 나가므로, 위치가 아이폰에 가는지 이것으로 본다(2026-11-06, 1.4.2는 이 줄까지 버렸다).
# iAP2(순정 iAP2 라이브러리)는 아이폰의 위치 요청(LocationInformationStart)을 남긴다. 분당 수십 줄 이하.
# 같은 줄이 연달아 나오면(pcm_write failed가 1초에 수천 줄) uniq -c가 한 줄과 횟수로 줄인다
# (앞의 날짜·시간 두 칸은 비교하지 않는다). 그래서 각 줄 앞에 반복 횟수가 붙는다.
# 1.5.6: 안드로이드 오토 쪽(GPM·GalReceiver로 시작하는 태그)도 남긴다(로드맵 1.5.6 2번, 1.5.7의 근거 자료)
TAGS=' [VDIWEF]/(hostapd|dnsmasq|HMG-API|iAP2|Iap2Service|CarPlay_|TccCarPlay|WifiService|BTCMService|NavigationCluster|ClusterService|GPM[A-Za-z_]*|GalReceiver[A-Za-z_]*) *\('
DROP='iAPSendMessage\(\) : done with \(0x00\)|iAPSendMessage Command Received|getCANSTatus = true|\): getCANStatus$|updateTPCrossroadName'
# 보관: cp.log가 LOGMAX를 넘으면 cp.log.1~3으로 밀어 최대 4개(기본 3MB씩, 12MB)
LOGMAX=${LOGMAX:-3145728}
logstart() {
  [ -f $W/debug ] || return 0
  # busybox에 uniq가 없거나 -f를 모르면 줄이지 않고 그대로 남긴다 (로그가 아예 끊기지 않게)
  if echo x | $BB uniq -c -f 2 >/dev/null 2>&1; then _u="$BB uniq -c -f 2"; else _u="$BB grep ."; fi
  # grep이 DROP 정규식을 못 받으면(종료 코드 2) 파이프가 조용히 끝나 로그가 비므로, 그때는 아무 줄도 버리지 않는다
  _d=$DROP; echo x | $BB grep -E "$_d" >/dev/null 2>&1; [ $? -le 1 ] || _d='^$'
  # 1.5.6: 안드로이드 오토는 폰에 Wi-Fi 이름·비밀번호를 보낸다. 그런 값이 나올 수 있는 줄은 태그와 상관없이 버린다.
  # "psk"는 값이 붙는 꼴(psk=, psk:)만 버린다: 보안 방식 줄("Auth Type : WPA2_PSK")은 원인을 찾는 데 필요하다(2026-11-07).
  logcat -v time 2>/dev/null | $BB grep -E "$TAGS" | $BB grep -v -E "$_d" | $BB grep -v -i -E 'ssid|psk *[=:]|passphrase|password|bssid|key=' | $_u >> $W/cp.log &
  echo $! > $W/log.pid
}
# 파이프를 다시 시작하지 않고 파일만 밀어낸다: 다시 시작하면 logcat이 버퍼 전체를 다시 써서
# 몇 분 치가 겹쳐 쌓였다(run3). uniq는 >>(O_APPEND)로 열었으므로 cp.log를 비우면 처음부터 다시 쓴다.
# 복사와 비우기 사이에 들어온 몇 줄은 잃을 수 있다(디버그용이라 감수).
logrotate() {
  [ -f $W/log.pid ] || return 0
  _sz=$( { $BB wc -c < $W/cp.log; } 2>/dev/null)
  [ ${_sz:-0} -lt $LOGMAX ] && return 0
  $BB mv -f $W/cp.log.2 $W/cp.log.3 2>/dev/null
  $BB mv -f $W/cp.log.1 $W/cp.log.2 2>/dev/null
  # 복사가 실패해도(공간 부족 등) cp.log는 비운다: 그러지 않으면 cp.log가 끝없이 커져 /data를 채운다
  $BB cp -f $W/cp.log $W/cp.log.1 2>/dev/null || $BB rm -f $W/cp.log.1
  : > $W/cp.log
}

# HMG-API가 자기 것으로 기록한 기능 권한 파일이 사라졌을 때 되돌린다 (2026-11-06 니로에서 확인한 문제:
# wireless.projection을 지우면 무선 기능 파일 2개가 함께 지워지고, HMG-API 1.0.2의 apply는
# "changed outside HMG-API"로 멈추며 --force로도 다시 쓰지 않는다).
# `hmgapid engine status`에서 "CHANGED <권한 파일> … expected <md5>, found absent" 줄만 골라,
# HMG-API(Engine.features)가 쓰는 것과 같은 텍스트의 md5가 기록과 같을 때만 쓴다. 그 뒤 일반 apply.
# 되돌린 파일은 HMG-API 것이므로 이 패키지를 지워도 남겨 둔다.
PERMS=${PERMS:-/system/etc/permissions}
perm_text() { $BB printf '<permissions>\n    <feature name="%s" />\n</permissions>\n' "$1"; }
# HMG-API에 남아 있는 다른 변경(앱에서 바꾸고 아직 적용 안 한 모드 등)까지 몰래 적용하지 않도록,
# 계획에 바뀌는 것이 featurexml.cfg와 방금 되돌린 권한 파일뿐일 때만 apply한다.
plan_only_ours() {
  _bad=0
  hmgapid engine plan > $W/plan.txt 2>&1 || _bad=1
  while IFS= read -r _l; do
    case "$_l" in
      "change   "*|"update   "*)
        set -- $_l
        _p=$2; _mods=$3
        case "$_p" in
          # featurexml.cfg는 되돌린 권한 파일을 가진 모드의 변경일 때만 (다른 모드가 앱에서 쌓아 둔 변경은 안 됨)
          /system/onebin/*/featurexml.cfg) has_line "$_mods" $W/perms.mods || _bad=1 ;;
          *) has_line "${_p##*/}" $W/perms.done || _bad=1 ;;
        esac ;;
      # 다른 곳에서 바뀐 파일을 새 기준으로 삼는 rebase는 featurexml.cfg만 (wireless.projection 삭제가 되돌린 파일)
      "rebase   /system/onebin/"*"/featurexml.cfg:"*) ;;
      "rebase   "*|"problem  "*|"restore  "*|"setting  "*|"bind     "*|"unbind   "*) _bad=1 ;;
      # WARNING 줄(예: ADB TCP 스위치 경고)은 정보일 뿐이라 막지 않는다
    esac
  done < $W/plan.txt
  return $_bad
}

# /system이 원래 ro였을 때만 ro로 되돌린다 (NEMESIS·HMG-API가 rw로 쓰는 중일 수 있다)
# /proc/mounts를 못 읽으면 ro였던 것으로 본다 (rw로 남기지 않는 쪽으로)
system_ro() {
  _ml=$($BB grep " /system " ${MOUNTS:-/proc/mounts} 2>/dev/null) || return 0
  case "$_ml" in *" ro,"*|*" ro "*) return 0 ;; *) return 1 ;; esac
}

# 한 번에 하나만: 서비스가 다시 시작돼도 앞의 작업(뒤에서 도는 하위 셸)과 겹치지 않게.
# main이 $!로 하위 셸의 pid를 적는다 (하위 셸 안의 $$는 부모 pid라 쓸 수 없다)
BOOT_ID=${BOOT_ID:-/proc/sys/kernel/random/boot_id}
# fix.pid: "<pid> <boot_id>". /data/local/tmp는 재부팅 뒤에도 남으므로 이번 부팅의 것만 믿는다.
fix_running() {
  _l=$(cat $W/fix.pid 2>/dev/null) || return 1
  set -- $_l
  [ -n "$1" ] && [ "$1" != $$ ] && [ "$2" = "$(cat $BOOT_ID 2>/dev/null)" ] && [ -d /proc/$1 ] \
    && $BB grep -q hotspot.sh /proc/$1/cmdline 2>/dev/null
}
# 파일에 그 줄이 그대로 있는가 (busybox 1.8.1 grep의 -x/-F는 확실하지 않아 셸로 비교)
has_line() {
  [ -f "$2" ] || return 1
  while IFS= read -r _x; do [ "$_x" = "$1" ] && return 0; done < "$2"
  return 1
}
# --- 1.5 자동 설정: HMG-API 무선 모드와 이 차의 지도 (확인된 차에서만) ---
# HMG-API 공식판에 한국 차 지원(지도, 모드의 지원 차·패치 세트)이 아직 없어(니로: PR VysseCodes/HMG-API#22),
# 패키지에 든 한국 차 빌드 모드(hmgapi/wireless-carplay-aa.zip)와 차에서 확인한 지도(hmgapi/maps/<제조사>/<차종>/
# <지역>/<펌웨어>/)를 HMG-API 명령으로 넣는다. 파일을 직접 고치지 않는다.
# - 지도: 패키지에 든 차별 지도 가운데 HMG-API에 없는 것(car.json 없음)만 넣고, 넣었으면 HMG-API의 지도 확인
#   (verify-map, 이 차의 지도를 확인)을 돌린다.
#   HMG-API를 업데이트하면 지도 폴더가 릴리스 것으로 바뀌므로 부팅마다 본다. 공식판에 지도가 생기면 그것을 쓴다.
# - 모드: 설치돼 있지 않을 때 한 번만 설치한다($BK/mod.tried). 차주가 일부러 지우거나 꺼 둔 것은 다시 하지 않는다.
#   설치한 것은 $BK/mod.ours로 남겨 이 패키지를 지울 때 그것만 정리한다(preun.sh).
# - 적용(apply)은 계획이 이 모드의 변경뿐이고 훅이 켜질 때만 한다. 아니면 HMG-API 앱에서 적용하라고 안내한다.
# - 알려진 위험: HMG-API 엔진에는 잠금이 없어, 같은 때 차주가 앱에서 적용하면 서로 겹칠 수 있다(기존
#   권한 파일 복구와 같음). 부팅 뒤 FIX_DELAY(120초)를 기다리고, 앞 적용이 안 끝났으면 엔진이 거부한다.
# - 이 모드 zip은 우리 개발 키로 서명했다. HMG-API는 같은 키의 업데이트만 받으므로, 공식 모드로 바꾸려면
#   이것을 먼저 지워야 한다(hmgapi/README.txt).
KP_HMG=${KP_HMG:-$APP/hmgapi}
HMGDATA=${HMGDATA:-/data/hmgapi}
# HMG-API가 Wi-Fi 칩을 찾는 곳(SystemCheck.java): SDIO 장치, 한 번 본 기록
SDIO=${SDIO:-/sys/bus/sdio/devices}
WIFI_SEEN=${WIFI_SEEN:-$HMGDATA/public/wifi-chip}
BK=${BK:-/data/nemesis/backup/korea.projection}
MOD_ID=wireless-carplay-aa
# 패키지에 든 모드 zip의 md5 (busybox 1.8.1에 sha256sum이 없다). zip을 바꾸면 함께 바꾼다.
MOD_MD5=42d4e34e2e61f94bb004ae40317642ff
# 마지막 안내 문구를 기억한다(설치 진행 기록의 실패 사유로 쓴다)
toast() {
  LAST_TOAST=${1#Korea Projection: }
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
}
# 계획(engine plan)이 이 모드의 새 변경뿐인가: 다른 모드의 변경, 되돌리기, 문제가 있으면 아니다
plan_only_mod() {
  _bad=0
  hmgapid engine plan > $W/plan.txt 2>&1 || _bad=1
  # "[wireless-carplay-aa]"가 단어 나누기 때 파일 이름 패턴으로 풀리지 않게
  set -f
  while IFS= read -r _l; do
    case "$_l" in
      # 훅이 꺼져 있으면 적용해도 무선 카플레이가 안 된다(기능 파일·속성만 바뀜)
      "hooks are off"*|"hooks "*"won't load"*) _bad=1 ;;
      "change   "*|"update   "*) set -- $_l; [ "$3" = "[$MOD_ID]" ] || _bad=1 ;;
      "setting  "*" back to stock"*) _bad=1 ;;
      "setting  "*"[$MOD_ID]"*) ;;
      "setting  "*|"problem  "*|"restore  "*|"rebase   "*|"bind     "*|"unbind   "*|"nothing changed"*) _bad=1 ;;
    esac
  done < $W/plan.txt
  set +f
  return $_bad
}
# Wi-Fi 칩 깨우기: 한국 내수 펌웨어에는 일반 Wi-Fi를 켜는 메뉴가 없다. 그래서 Wi-Fi를 한 번도 켜지 않은 차는
# 칩이 SDIO에 나타나지 않는다(MAC 00:00:00…, 그랜저 IGPEHEV 제보 #7).
# HMG-API는 칩을 SDIO에서 한 번 봐야(그 기록 $WIFI_SEEN이 있어도 됨) 칩이 있다고 본다(hmgapi.wifi).
# 무선 모드는 칩이 있어야 설치된다. 우리 핫스팟은 모드가 있어야 Wi-Fi를 켜므로, 모드를 넣기 전에 Wi-Fi를 한 번 켠다.
# - 시스템 파일과 속성은 바꾸지 않는다(svc wifi enable만 한다).
#   커뮤니티 "Wi-Fi 모듈 활성화 패치"는 build.prop·featurexml·권한 XML을 고친다. 우리는 그중 Wi-Fi를 켜는 것만 한다.
# - 기능 목록(android.hardware.wifi)으로 거르지 않는다: 니로는 이 기능이 없는데도 svc wifi enable로 Wi-Fi가 켜진다
#   (2026-11-06 차에서 확인). Wi-Fi 서비스가 없는 차는 칩이 안 나타나 wifi.nochip으로 끝난다.
# - Wi-Fi를 켜면 USB·블루투스가 다시 시작된다(유선 카플레이가 끊길 수 있다). 그래서 평생 한 번만 한다.
#   켜기 전에 $BK/wifi.woke를 남긴다. 칩이 잠깐 보였다 사라져(드라이버가 내려감) 설치가 실패해도
#   부팅마다 다시 켜지 않는다. 기록은 패키지를 지우면 같이 지워진다.
#   칩이 안 나타나면 $BK/wifi.nochip을 남기고, 설치 전에 Wi-Fi가 켜져 있지 않았으면 다시 끈다
#   (wifi_on이 1이 아니면 꺼져 있던 것으로 본다: 한 번도 안 켠 차는 값이 null일 수 있다).
# - 차주가 다른 방법으로 Wi-Fi를 켜 칩이 보이면 기록과 상관없이 다음 부팅에 설치를 다시 시도한다.
# 돌려주는 값: 0 칩이 보임(원래 보였거나 이번에 깨움), 1 이번에 못 깨움, 2 예전에 깨우기를 해 봄(다시 안 함)
wifi_chip_seen() {
  [ -f $WIFI_SEEN ] || [ -n "$(ls $SDIO 2>/dev/null)" ]
}
wifi_was_off() {
  [ -f $BK/wifi_on ] && [ "$(cat $BK/wifi_on 2>/dev/null)" != 1 ]
}
# 뒤에서 돌린 svc wifi enable 정리: 아직 돌면 멈추고, 끝났으면 실패한 종료 코드만 기록한다(제보 분석용)
svc_done() {
  if kill -0 $1 2>/dev/null; then
    kill $1 2>/dev/null; log "svc wifi enable이 끝나지 않아 멈춤"
  else
    wait $1; _rc=$?
    [ $_rc = 0 ] || log "svc wifi enable 실패 (종료 코드 $_rc)"
  fi
}
wake_wifi() {
  wifi_chip_seen && return 0
  [ -f $BK/wifi.nochip ] || [ -f $BK/wifi.woke ] && return 2
  log "Wi-Fi 칩이 아직 안 보임: Wi-Fi를 한 번 켜서 칩을 깨움"
  ptrack 62 run "Wi-Fi 칩을 깨우는 중입니다"
  toast "Korea Projection: 무선 카플레이 준비로 Wi-Fi를 한 번 켭니다. 카플레이·블루투스가 잠시 끊길 수 있습니다."
  : > $BK/wifi.woke
  # svc는 뒤에서 돌린다: 시스템 서버가 멈춰 있으면 바인더 호출이 끝나지 않을 수 있어, 아래 대기 시간이 상한이 된다
  svc wifi enable > /dev/null 2>&1 &
  _sp=$!
  _i=0
  while [ $_i -lt ${WAKE_MAX:-30} ]; do
    sleep 2
    wifi_chip_seen && { svc_done $_sp; log "Wi-Fi 칩이 나타남"; return 0; }
    _i=$((_i+1))
  done
  svc_done $_sp
  log "Wi-Fi를 켜도 칩이 나타나지 않음 (다음 부팅부터 다시 하지 않음)"
  : > $BK/wifi.nochip
  wifi_was_off && svc wifi disable
  return 1
}

# 차에 있는 무선 모드가 우리 것이 아니고(mod.ours 없음) 한국 차를 지원하지 않는가(mod.json에 "region": "KOR" 항목이 없음).
# 우리 한국 차 빌드는 KOR 항목이 있다. 0: 그렇다(다른 판), 1: 모드가 없거나 우리 것이거나 한국 차를 지원함.
mod_foreign() {
  [ -s $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $BK/mod.ours ] && ! mod_kor
}
# 무선 모드 mod.json에 한국 차 항목이 있는가: "region": "KOR" 또는 "region": [..., "KOR", ...](공백·탭 무관).
# busybox가 없으면 toolbox grep(-E 됨, K3 탐사)으로 본다. 파일을 못 읽으면 1(한국 차 항목 없음으로 봄).
mod_kor() { bbx grep -q -E '"region"[[:space:]]*:[[:space:]]*(\[[^]]*)?"KOR"' $HMGDATA/mods/$MOD_ID/mod.json 2>/dev/null; }
setup_hmgapi() {
  if ! car_in "$(getprop ro.build.product 2>/dev/null)" "$CARS"; then
    ptrack 100 fail "지원하지 않는 차(한국 내수 펌웨어가 아님)입니다. 아무것도 바꾸지 않았습니다."
    return 0
  fi
  if [ ! -d $HMGDATA/maps ]; then
    log "자동 설정 건너뜀: HMG-API가 없음"
    ptrack 100 fail "HMG-API가 없습니다. HMG-API 1.0.2 이상을 먼저 설치해 주세요."
    return 0
  fi
  ptrack 30 run "지도와 무선 모드를 확인하는 중입니다"
  $BB mkdir -p $BK
  # 1.6.1: 무선 모드가 없으면 "우리가 넣음"(mod.ours) 기록을 지운다. 남겨 두면 차주가 나중에 넣은 다른 판을
  # 우리 것으로 보고 안내하지 않거나, 패키지를 지울 때 그 모드를 지운다.
  # mod.tried는 남긴다(차주가 일부러 지운 우리 모드는 다시 넣지 않는다).
  [ -f $HMGDATA/mods/$MOD_ID/mod.json ] || rm -f $BK/mod.ours
  # _fail: 안내를 이미 남김(토스트 또는 LAST_TOAST → 마지막 진행 기록 문구) → "설정을 마쳤습니다"로 덮지 않는다
  _restart=0; _fail=0
  # 지도: 차마다 임시 폴더에 다 복사한 뒤 한 번에 옮긴다(도중에 전원이 꺼져 반쪽 지도가 남지 않게).
  # 임시 폴더는 maps/.kp-tmp: HMG-API는 maps/<제조사>/<차종>/<지역>/<펌웨어>/만 읽으므로 반쪽 car.json을 보지 않는다.
  # 이 차의 지도만 넣는다: 폴더의 펌웨어가 같고 car.json의 products에 "<모델>.<지역>."이 있는 것.
  #   다른 차 지도는 HMG-API 공유 폴더에 남기지 않는다(복사 실패로 이 차 설정이 막히지도 않게).
  # 지도 확인(verify-map)은 지도를 넣었을 때만 한다. 실패하면 넣은 지도를 다시 빼고(차에 있던 다른 지도를
  #   가리지 않게) $BK/map.bad에 "<폴더> <car.json md5>"를 남긴다. 같은 지도는 다시 넣지 않고 모드도 설치하지
  #   않는다. 지도가 바뀐 새 버전이면(md5 다름) 다시 시도한다.
  # map.ours는 기록용이다: 지도는 HMG-API의 다른 모드도 쓰므로 패키지를 지워도 남긴다.
  _mapbad=0; _mine=0; _myrel=
  _prod=$(getprop ro.build.product 2>/dev/null)
  _pm=${_prod%%.*}; _pr=${_prod#*.}; _pr=${_pr%%.*}
  _tmp=$HMGDATA/maps/.kp-tmp
  # 우리가 무선을 맡지 않는 차(확인된 차가 아니고 무선 모드를 아직 넣지 않았을 때만 본다. 모드가 기능 파일을
  # 바꾸면 결과가 달라지므로). 시험 지원 차(CARS_TRY)와 자동 시험 차 모두 본다. 지도도 넣지 않는다.
  # - wireless.projection이 설치된 차: 같은 파일·속성을 다른 패키지가 관리한다(먼저 지워야 한다)
  # - 순정 핫스팟이 지금 켜져 있는 차(우리 것이 아닌 hostapd가 돎): 순정이 wlan0을 쓰고 있으므로 이번 부팅은
  #   건너뛰고 다음 부팅에 다시 본다. 순정 핫스팟 기능이 있어도 꺼져 있으면 우리 방식으로 한다
  #   (2026-11-06 소유자 결정. 벨로스터 N JSN은 기능이 있지만 순정 무선 카플레이는 없다).
  _skip=0
  if ! car_in "$_prod" "$CARS_OK" && [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ]; then
    if [ -d $WPDIR ]; then
      log "무선 설정 안 함: wireless.projection이 설치되어 있음 (먼저 삭제해 주세요)"; _skip=1
      LAST_TOAST="wireless.projection이 설치되어 있어 무선 카플레이를 설정하지 않았습니다. wireless.projection을 삭제한 뒤 내비를 재부팅해 주세요."
      if [ ! -f $BK/wp.told ]; then
        : > $BK/wp.told
        toast "Korea Projection: wireless.projection이 설치되어 있어 무선 카플레이를 설정하지 않았습니다. wireless.projection을 삭제한 뒤 내비를 재부팅해 주세요."
      fi
    elif stock_ap_on; then
      log "무선 설정 안 함: 다른 hostapd가 돌고 있음(순정 핫스팟 등) (다음 부팅에 다시 봄)"; _skip=1
      LAST_TOAST="순정 핫스팟이 켜져 있어 이번에는 설정하지 않았습니다. 순정 핫스팟을 끄고 내비를 재부팅해 주세요."
    elif pm list features 2>/dev/null | $BB grep -q '^feature:com\.hkmc\.software\.wifihotspot$'; then
      log "순정 핫스팟 기능이 있지만 꺼져 있음: 우리 방식으로 진행"
    fi
  fi
  [ $_skip = 1 ] && _mapbad=1
  for _c in $KP_HMG/maps/*/*/*/*/car.json; do
    [ $_skip = 1 ] && break
    [ -f "$_c" ] || continue
    _d=${_c%/car.json}; _rel=${_d#$KP_HMG/maps/}
    [ "${_rel##*/}" = "${_prod##*.}" ] && $BB grep -q "\"$_pm\.$_pr\.\"" $_c || continue
    # 같은 폴더에 지도가 이미 있으면(공식판 등) 그것을 쓴다: 실패 기록보다 먼저 본다
    [ -f $HMGDATA/maps/$_rel/car.json ] && continue
    set -- $($BB md5sum < $_c); _sum=$1
    if has_line "$_rel $_sum" $BK/map.bad; then
      log "지도 넣지 않음: $_rel (이 차에서 지도 확인에 실패한 지도)"; _mapbad=1; continue
    fi
    $BB rm -rf $_tmp
    if $BB mkdir -p $_tmp ${HMGDATA}/maps/${_rel%/*} && $BB cp $_d/*.json $_tmp/ && $BB chmod -R 700 $_tmp \
        && $BB rm -rf $HMGDATA/maps/$_rel && $BB mv $_tmp $HMGDATA/maps/$_rel; then
      echo "$_rel" >> $BK/map.ours
      log "지도 넣음: $_rel"
      _mine=1; _myrel=$_rel; _mysum=$_sum
    else
      $BB rm -rf $_tmp
      log "지도 넣기 실패: $_rel"; _fail=1; _mapbad=1
    fi
  done
  # 자동 시험(CARS_OK·CARS_TRY가 아닌 한국 차): 패키지에 이 차 지도가 없으므로, HMG-API에 이 차 지도가 없으면
  # HMG-API가 이 차의 파일로 지도를 만든다(engine map-car --write, 상태 probed). 아래 verify-map이 이 차에서
  # 확인해야 훅이 켜진다. 확인에 실패하면 만든 지도를 지우고 $BK/automap.bad를 남긴다(다시 만들지 않고 모드도
  # 넣지 않음, 패키지를 지우면 같이 지워진다). HMG-API 업데이트로 지도 폴더가 바뀌면 다음 부팅에 다시 만든다.
  # 이미 있는 지도(공식판, 차주가 만든 것)는 건드리지 않고, 확인만 한 번 한다(_myrel 없음 → 지우지 않음).
  _auto=0
  car_in "$_prod" "$CARS_OK $CARS_TRY" || _auto=1
  # 위에서 건너뛰기로 한 차는 자동 시험도 하지 않는다
  [ $_skip = 1 ] && _auto=0
  if [ $_auto = 1 ] && [ -f $BK/automap.bad ]; then
    log "자동 시험: 이 차에서 만든 지도가 확인에 실패한 기록이 있어 무선 모드를 넣지 않음"; _mapbad=1
  elif [ $_auto = 1 ] && [ $_mine = 0 ]; then
    _lm=$(echo "$_pm" | $BB awk '{ print tolower($0) }'); _lr=$(echo "$_pr" | $BB awk '{ print tolower($0) }')
    _have=0
    for _e in $HMGDATA/maps/*/$_lm/$_lr/${_prod##*.}/car.json; do [ -f "$_e" ] && _have=1; done
    if [ $_have = 1 ]; then
      [ -f $BK/automap.checked ] || { _mine=1; : > $BK/automap.checked; }
    elif [ -f $BK/automap.foreign ]; then
      # 다른 폴더 이름의 이 차 지도(공식판 등)를 쓰기로 했다: 무거운 map-car를 부팅마다 다시 돌리지 않는다
      :
    elif ptrack 40 run "이 차의 지도를 만드는 중입니다(1~2분)"; hmgapid engine map-car --write > $W/map-car.txt 2>&1; then
      _nw=0
      while IFS= read -r _l; do
        case "$_l" in
          "written: "*) _r=${_l#written: }; _myrel=${_r%%" ("*} ;;
          "not written: HMG-API has a map"*) _nw=1 ;;
        esac
      done < $W/map-car.txt
      case "$_myrel" in
        */*/*/*) _mine=1; echo "$_myrel" >> $BK/map.ours; log "자동 시험: 이 차의 파일로 지도를 만듦 ($_myrel)" ;;
        *)
          _myrel=
          if [ $_nw = 1 ]; then
            # 다른 폴더 이름으로 이 차 지도(공식판 등)가 이미 있다: 만들지 않고 그 지도를 한 번 확인한다(지우지 않음)
            log "자동 시험: HMG-API에 이 차 지도가 이미 있음 (그 지도를 씀)"
            : > $BK/automap.foreign
            [ -f $BK/automap.checked ] || { _mine=1; : > $BK/automap.checked; }
          else
            log "자동 시험: 지도를 만들지 않음 ($W/map-car.txt)"; _mapbad=1
          fi ;;
      esac
    else
      log "자동 시험: 지도 만들기 실패 ($W/map-car.txt)"; _fail=1; _mapbad=1; : > $BK/automap.bad
      toast "Korea Projection: 이 차의 HMG-API 지도를 만들지 못했습니다. Launch로 제보 파일을 만들어 보내 주세요."
    fi
  fi
  if [ $_mine = 1 ] && [ $_mapbad = 0 ]; then
    if ptrack 55 run "지도를 확인하는 중입니다"; hmgapid engine verify-map > $W/verify-map.txt 2>&1; then
      log "지도 확인 통과 (다음 시작부터 훅 켜짐)"; _restart=1
      [ $_auto = 1 ] && : > $BK/automap.checked
    else
      log "지도 확인 실패 ($W/verify-map.txt)"; _fail=1; _mapbad=1
      [ $_auto = 1 ] && : > $BK/automap.bad
      case "$_myrel" in *..*|/*) _myrel= ;; esac
      if [ -n "$_myrel" ]; then
        $BB rm -rf $HMGDATA/maps/$_myrel
        [ $_auto = 1 ] || echo "$_myrel $_mysum" >> $BK/map.bad
        log "지도 뺌: $_myrel (다음 부팅에도 넣지 않음)"
        # 확인 기록(HMG-API state)은 방금 실패로 덮였다. 차에 이 차용 다른 지도(차주가 만든 것 등)가 있으면
        # 그 지도로 다시 확인해 예전처럼 훅이 켜지게 한다. 다른 지도가 없으면 실패하고 끝난다.
        if hmgapid engine verify-map > $W/verify-map2.txt 2>&1; then
          log "차에 있던 다른 지도로 다시 확인 통과"
        else
          log "다른 지도로 다시 확인 안 됨 ($W/verify-map2.txt)"
        fi
      fi
      toast "Korea Projection: HMG-API 지도 확인에 실패했습니다. Launch에서 상태를 확인해 주세요."
    fi
  fi
  # 무선 모드: 지도가 잘못됐으면 하지 않는다(훅 없이 기능 파일·속성만 바뀌므로).
  # mod.tried는 설치에 성공했거나 다시 해도 같은 결과일 때(zip md5 다름)만 남긴다. 일시적인 실패
  # (앞의 apply가 안 끝남, 데몬이 바쁨)는 다음 부팅에 다시 한다.
  if [ $_mapbad = 0 ] && [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $BK/mod.tried ]; then
    set -- $($BB md5sum < $KP_HMG/$MOD_ID.zip 2>/dev/null)
    if [ "$1" != $MOD_MD5 ]; then
      : > $BK/mod.tried
      log "무선 모드 설치 안 함: 패키지의 zip md5가 다름 (${1:-없음})"
    elif wake_wifi; _wk=$?; [ $_wk != 0 ]; then
      # 칩이 없으면 HMG-API가 모드를 받지 않는다: 설치를 시도하지 않는다. 안내는 처음 한 번만 한다.
      log "무선 모드 설치 안 함: Wi-Fi 칩을 찾지 못함"
      if [ $_wk = 1 ]; then
        _fail=1
        toast "Korea Projection: 이 차에서 Wi-Fi 칩을 찾지 못해 무선 카플레이를 켤 수 없습니다. 내비를 재부팅한 뒤 Launch로 제보 파일을 만들어 보내 주세요."
      fi
    elif ptrack 70 run "무선 모드를 설치하는 중입니다"; ! hmgapid engine install $KP_HMG/$MOD_ID.zip > $W/mod-install.txt 2>&1; then
      log "무선 모드 설치 실패, 다음 부팅에 다시 함 ($W/mod-install.txt, HMG-API 칩 기록 $([ -f $WIFI_SEEN ] && echo 있음 || echo 없음))"; _fail=1
      toast "Korea Projection: HMG-API 무선 모드를 설치하지 못했습니다. Launch에서 상태를 확인해 주세요."
    else
      : > $BK/mod.tried; : > $BK/mod.ours
      log "무선 모드 설치함"
      if ! plan_only_mod; then
        log "무선 모드 적용 안 함: 계획에 다른 변경이 있거나 훅이 꺼짐 ($W/plan.txt)"; _fail=1
        toast "Korea Projection: 무선 모드를 설치했습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
      elif ptrack 85 run "무선 모드를 적용하는 중입니다"; hmgapid engine apply > $W/mod-apply.txt 2>&1; then
        log "무선 모드 적용함"; _restart=1
      else
        log "무선 모드 적용 실패 ($W/mod-apply.txt)"; _fail=1
        toast "Korea Projection: 무선 모드 적용에 실패했습니다. HMG-API 앱을 확인해 주세요."
      fi
    fi
  fi
  # 1.6.1: 차에 이미 있는 무선 모드가 우리가 넣은 것이 아니고 한국 차를 지원하지 않는 판이면(예: HMG-API 기본 2.1.0,
  # 북미 EV6·아이오닉5용, #25 팰리세이드) 덮어쓰지 않는다(차주 것). 대신 무엇을 하면 되는지 알린다.
  # 토스트는 띄우지 않는다(금방 사라짐, 소유자 결정). 안내는 Launch 화면에 남긴다: 진행 기록의 실패 문구(이번 부팅)와,
  # 부팅이 지나도 상태 파일의 mod_foreign=yes를 앱이 보고 맨 위 판정 줄에 같은 안내를 보인다(Report.verdict).
  # 차주가 지우면 다음 부팅에 위에서 우리 모드를 넣는다(Wi-Fi 칩·지도 기록 등 다른 이유로 멈출 수 있어 "시도"로 쓴다).
  # 지도가 잘못됐으면 그 사유를 먼저 보인다.
  if [ $_fail = 0 ] && [ $_mapbad = 0 ] && mod_foreign; then
    log "무선 모드 설치 안 함: 한국 차를 지원하지 않는 다른 무선 모드가 이미 있음(덮어쓰지 않음)"
    LAST_TOAST="차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다. HMG-API 앱에서 그 모드를 지우고 적용한 뒤 재부팅해 주세요."
    _fail=1
  fi
  # 진행 기록의 마지막 결과(상태 화면 앱이 보여 줌)
  if [ $_restart = 1 ] && [ $_fail = 0 ]; then
    ptrack 100 reboot "무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  elif [ $_fail = 1 ]; then
    ptrack 100 fail "${LAST_TOAST:-무선 카플레이 설정에 실패했습니다. USB를 꽂고 Launch로 제보 파일을 만들어 보내 주세요.}"
  elif setup_done; then
    ptrack 100 done "무선 카플레이 설정이 끝나 있습니다."
  elif [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ -z "$LAST_TOAST" ]; then
    ptrack 100 fail "HMG-API 무선 모드가 있지만 꺼져 있거나 적용되지 않았습니다. HMG-API 앱에서 켜고 변경 사항을 적용한 뒤 내비를 재부팅해 주세요."
  else
    ptrack 100 fail "${LAST_TOAST:-무선 모드를 넣지 못했습니다. USB를 꽂고 Launch로 제보 파일을 만들어 보내 주세요.}"
  fi
  if [ $_restart = 1 ] && [ $_fail = 0 ]; then
    if car_in "$_prod" "$CARS_OK"; then
      toast "Korea Projection: 무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
    else
      toast "Korea Projection: 무선 카플레이 설정을 마쳤습니다(시험 중인 차). 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅). 되는지 제보해 주시고, 유선 카플레이까지 안 되면 Korea Projection을 삭제하세요."
    fi
  fi
  return 0
}

# 진행 기록은 설정이 아직 끝나지 않았을 때만 남긴다(P_ON=1). 이미 끝난 차는 부팅마다 조용히 확인만 한다.
ptrack() { [ "$P_ON" = 1 ] && prog "$@"; return 0; }
fix_perms() {
  # 지원하지 않는 차는 진행 기록을 쓰지 않는다(main이 "지원하지 않는 차"를 쓴다). 권한 파일 확인은 그대로 한다.
  P_ON=0; setup_done || P_ON=1
  car_in "$(getprop ro.build.product 2>/dev/null)" "$CARS" || P_ON=0
  if ! command -v hmgapid >/dev/null 2>&1; then
    ptrack 100 fail "HMG-API가 없습니다. HMG-API 1.0.2 이상을 먼저 설치해 주세요."
    rm -f $W/fix.pid; return 0
  fi
  _fix_perms
  rm -f $W/fix.pid
}
_fix_perms() {
  # 부팅 직후 HMG-API의 부팅 단계(hook-check: remount rw → 쓰기 → ro)와 겹치지 않게 잠시 기다린다.
  # 10초씩 나눠 기다리며 진행 기록을 5→25%로 올린다(사용자가 멈춘 줄 알고 삭제하지 않게)
  _wt=0; _fd=${FIX_DELAY:-120}
  while [ $_wt -lt $_fd ]; do
    ptrack $((5 + 20 * _wt / (_fd > 0 ? _fd : 1))) run "HMG-API가 준비되기를 기다리는 중입니다(약 2분)"
    _s=$((_fd - _wt)); [ $_s -gt 10 ] && _s=10
    sleep $_s; _wt=$((_wt + _s))
  done
  # 그사이 패키지가 지워졌으면 그만둔다
  [ -d $W ] || return 0
  # HMG-API 데몬이 뜰 때까지 기다린다 (최대 5분). 이 함수는 뒤에서 돌므로 핫스팟을 늦추지 않는다.
  _i=0
  until hmgapid ping >/dev/null 2>&1; do
    ptrack 27 run "HMG-API 응답을 기다리는 중입니다"
    _i=$((_i+1)); [ $_i -ge 30 ] && { log "권한 파일 확인 건너뜀: HMG-API 데몬 응답 없음"; ptrack 100 fail "HMG-API가 응답하지 않습니다. 내비를 재부팅한 뒤 다시 확인해 주세요."; return 0; }
    sleep 10
  done
  setup_hmgapi
  # 줄에 "[wireless-carplay-aa]"가 있어 단어 나누기 때 파일 이름 패턴으로 풀리지 않게
  set -f
  _todo=$W/perms.todo
  : > $_todo
  : > $W/perms.mods
  hmgapid engine status 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in
      "CHANGED "*"$PERMS/"*".xml "*", found absent"*) ;;
      *) continue ;;
    esac
    set -- $_l
    _p=$2; _m=$3; _n=${_p##*/}; _n=${_n%.xml}
    case "$_n" in com.hkmc.*|android.hardware.*|android.software.*) ;; *) continue ;; esac
    [ "$_p" = "$PERMS/$_n.xml" ] || continue
    _e=${_l#*expected }; _e=${_e%%,*}
    set -- $(perm_text "$_n" | $BB md5sum)
    if [ "$1" = "$_e" ]; then echo "$_n" >> $_todo; echo "$_m" >> $W/perms.mods
    else log "권한 파일 되돌리기 건너뜀: $_n (기록 md5가 HMG-API 형식과 다름)"; fi
  done
  [ -s $_todo ] || { set +f; rm -f $_todo; return 0; }
  _was_ro=0; system_ro && _was_ro=1
  hmgapid remount rw >/dev/null 2>&1
  : > $W/perms.done
  while IFS= read -r _n; do
    [ -f $PERMS/$_n.xml ] && continue
    if perm_text "$_n" > $PERMS/$_n.xml && $BB chmod 644 $PERMS/$_n.xml; then
      echo "$_n.xml" >> $W/perms.done; log "권한 파일 되돌림: $_n"
    else
      rm -f $PERMS/$_n.xml; log "권한 파일 쓰기 실패: $_n"
    fi
  done < $_todo
  [ $_was_ro = 1 ] && hmgapid remount ro >/dev/null 2>&1
  rm -f $_todo
  if [ ! -s $W/perms.done ]; then set +f; rm -f $W/perms.done; return 0; fi
  if ! plan_only_ours; then
    log "HMG-API apply 안 함: 계획에 다른 변경이 있음 ($W/plan.txt). HMG-API 앱에서 적용해 주세요"
    _m="Korea Projection: 무선 카플레이 기능 파일을 복구했습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  elif hmgapid engine apply >/dev/null 2>&1; then
    log "HMG-API apply 완료"
    _m="Korea Projection: 무선 카플레이 기능 파일을 복구했습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  else
    log "HMG-API apply 실패"
    _m="Korea Projection: 무선 카플레이 기능 파일을 복구했지만 HMG-API 적용이 실패했습니다. HMG-API 앱을 확인해 주세요."
  fi
  set +f
  rm -f $W/perms.done
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$_m" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
}

# 상태 화면 앱(korea.projection.app). NEMESIS의 kind=apk 설치를 쓰지 않는다: 2026-11-06 니로에서
# /data/nemesis/apps/... 의 apk를 pm이 못 읽어 설치가 실패했고(시스템 사용자가 그 폴더를 못 연다),
# 그 실패가 패키지 설치 전체를 막아 핫스팟까지 없어졌다. 그래서 읽을 수 있는 곳(/data/local/tmp, 644)에
# 복사해 직접 설치하고, 실패해도 패키지는 그대로 둔다 (HMG-API 앱 설치와 같은 방식). APP는 위에서 정한다.
APK_SRC=${APK_SRC:-$APP/app/KoreaProjection.apk}
APK_COPY=${APK_COPY:-/data/local/tmp/korea-projection.apk}
APP_ID=korea.projection.app
# 앱 설치·확인에 쓰는 명령: busybox가 있으면 busybox로, 없는 내비(K3·K8, tcc803x)는 toolbox의 같은 이름으로.
# 1.5.5: busybox 없는 내비에도 상태 화면 앱을 설치한다. 앱이 없으면 Launch 때 NEMESIS가 "Error type 3 …
# StatusActivity does not exist"를 띄워 우리 안내를 가렸다(#15 사진). toolbox에 cp·chmod·mkdir·grep이 있다(K3 탐사).
bbx() { if has_bb; then $BB "$@"; else "$@"; fi; }
# KitKat pm은 실패해도 종료 코드 0일 수 있어 출력으로 본다
app_installed() { pm path $APP_ID 2>/dev/null | bbx grep -q "^package:"; }
# 결과(Success/Failure 전체 출력)를 $W/app-install.log에 남긴다. 성공 0, 실패 1.
install_app() {
  [ -f $APK_SRC ] || { log "상태 화면 앱 파일 없음: $APK_SRC"; return 1; }
  bbx cp -f $APK_SRC $APK_COPY && bbx chmod 644 $APK_COPY || { log "상태 화면 앱 복사 실패"; return 1; }
  # 이 헤드유닛은 sys.boot_completed=1일 때 제조사 서명만 받는다: pm 호출 동안만 0으로 둔다
  _b=$(getprop sys.boot_completed)
  if [ "$_b" = 1 ]; then
    # 도중에 이 스크립트가 끝나도 1로 되돌린다 (0으로 남으면 서비스가 부팅 완료를 영원히 기다린다)
    trap 'setprop sys.boot_completed 1' EXIT TERM INT HUP
    setprop sys.boot_completed 0
  fi
  _r=$(pm install -r $APK_COPY 2>&1)
  if [ "$_b" = 1 ]; then
    setprop sys.boot_completed 1
    trap - EXIT TERM INT HUP
  fi
  bbx mkdir -p $W 2>/dev/null
  echo "$(date '+%m-%d %H:%M:%S') pm install: $_r" >> $W/app-install.log
  case "$_r" in
    *Success*) rm -f $APK_COPY; log "상태 화면 앱 설치됨"; return 0 ;;
    *) log "상태 화면 앱 설치 실패 (핫스팟과는 상관없음): $(bbx echo $_r)"; return 1 ;;
  esac
}
# Launch(status.sh)에서 앱이 없을 때 다시 설치하기: 한 부팅에 한 번만. sys.boot_completed를 0→1로 바꿀 때마다
# init의 부팅 완료 트리거가 다시 돌기 때문이다(Launch를 여러 번 눌러도 한 번). busybox 없는 내비도 같이 쓴다.
install_app_once() {
  app_installed && return 0
  _bid=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)
  [ "$(cat $W/app-try 2>/dev/null)" = "$_bid" ] && return 1
  echo "$_bid" > $W/app-try
  install_app >/dev/null 2>&1
}
remove_app() {
  pm uninstall $APP_ID >/dev/null 2>&1
  rm -f $APK_COPY
}

# 쓸 수 있는 busybox가 없을 때(내비에 없고, 함께 넣은 것도 실행되지 않음: 예 /data가 noexec): 이 패키지의 스크립트는
# busybox로 동작하므로 무선 설정은 하지 않는다(상태 화면 앱만 설치). 안내는 설치 때(post.sh)와 Launch 때(status.sh)
# 한다. 서비스는 로그만 남기고 대기한다. 1.6.0·1.6.1 알파는 함께 넣은 busybox로 보통 경로를 탔고, 1.5.6은 다시 이렇게 대기한다.
has_bb() { [ "$BB_OK" = 1 ]; }

main() {
  umask 077
  if ! has_bb; then
    log "시작 안 함: busybox가 없음 ($BB, 실행 안 됨). 이 내비는 아직 지원하지 않음(조사 중)"
    idle_forever
  fi
  $BB mkdir -p $W
  prod=$(getprop ro.build.product)
  # svc, pm, HMG-API는 Android가 다 켜진 뒤에 쓴다
  while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done
  # 시계가 맞춰진 뒤의 시각으로 다시 잡는다(경과 시간)
  PSTART=$(date +%s)
  # 설치 진행 기록: 설정이 끝난 차는 "확인 중", 아니면 시작(5%). 끝난 차도 핫스팟이 켜지면 "준비됨"으로 바꾼다.
  # 같은 부팅에 서비스가 다시 시작돼도 "재부팅 필요"·"실패"는 덮지 않는다
  if prog_final_this_boot; then :
  elif setup_done; then prog 100 done "무선 카플레이 설정이 끝나 있습니다. 핫스팟을 켜는 중입니다."
  else prog 3 run "설치를 시작했습니다"; fi
  # 확인되지 않은 차에서도 한다: HMG-API가 기록한 그대로만 되돌리므로 (md5 확인)
  # 뒤에서 돌린다: HMG-API가 늦거나 멈춰도 핫스팟은 바로 켠다 (출력은 같은 ap.log로)
  if ! fix_running; then
    fix_perms &
    echo "$! $(cat $BOOT_ID 2>/dev/null)" > $W/fix.pid
  fi
  if ! car_in "$prod" "$CARS"; then
    log "시작 안 함: $prod 는 확인된 차가 아님 ($CARS)"
    prog 100 fail "지원하지 않는 차(한국 내수 펌웨어가 아님)입니다. 아무것도 바꾸지 않았습니다."
    # mode=restart: 끝내지 않고 대기한다(svcmgr가 죽은 횟수를 세지 않게)
    while true; do sleep 3600; done
  fi
  car_in "$prod" "$CARS_TRY" && log "시험 지원 차: $prod (차에서 아직 확인되지 않음)"
  trap 'stop_all; log "멈춤"; exit 0' TERM INT HUP
  if ! try_ready "$prod"; then
    log "대기: HMG-API 무선 모드가 설치·켜짐 상태가 아님 (시험 지원 차는 모드가 있어야 핫스팟을 켬)"
    if setup_pending; then
      $BB mkdir -p $BK; : > $BK/setup.told
      toast "Korea Projection: 무선 카플레이를 설정하는 중입니다. 약 5분 동안 내비를 재부팅하거나 끄지 마세요."
    fi
    while ! try_ready "$prod"; do sleep 60 & wait $!; done
    log "무선 모드 확인됨: 시작"
  fi
  # the package's earlier name runs its own hostapd: wait until it's uninstalled, then start
  if [ -d $OLDPKG ]; then
    log "대기: 예전 패키지 niro.carplay.hotspot이 설치되어 있음 (삭제해 주세요)"
    while [ -d $OLDPKG ]; do sleep 60 & wait $!; done
    log "예전 패키지 삭제됨: 시작"
  fi
  parse_conf $SRC
  if [ "${NS:-0}" -lt 4 ] || [ ${#S2} -lt 1 ] || [ ${#S4} -lt 8 ]; then
    log "시작 안 함: $SRC 에서 문자열 4개를 찾지 못함 (${NS:-0}개)"
    setup_done && prog 100 fail "순정 카플레이 Wi-Fi 설정(softap.conf)을 읽지 못했습니다. 제보해 주세요."
    idle_forever
  fi
  write_conf
  # 확인된 차가 아니면 순정 핫스팟(다른 hostapd)이 도는 동안 시작하지 않는다(svc wifi enable이 순정 핫스팟을 끈다)
  if ! car_in "$prod" "$CARS_OK" && stock_ap_on; then
    log "대기: 다른 hostapd가 돌고 있음(순정 핫스팟 등)"
    while stock_ap_on; do sleep 60 & wait $!; done
    log "다른 hostapd가 멈춤: 시작"
  fi
  log "시작 ($prod): softap.conf의 카플레이 SSID 길이 ${#S2}, 비밀번호 길이 ${#S4}"
  stop_ap
  # Wi-Fi 드라이버는 Wi-Fi를 켜야 올라오고, hostapd가 wlan0을 쓰려면 wpa_supplicant가 놓아야 한다(잠금 포함)
  take_wlan0
  logstart
  up
  rm -f $CPN
  wifi_events; cp_watch
  # 설정이 끝난 차(재부팅 뒤 등)는 핫스팟이 켜지면 "준비됨". 설정 중이면 진행 기록은 fix_perms가 맡는다.
  # 이번 부팅에 "재부팅 필요"·"실패"를 이미 썼으면 덮어쓰지 않는다(재부팅해야 훅이 켜진다)
  if setup_done && { [ ! -f $PROG ] || $BB grep -q '^state=done$' $PROG 2>/dev/null; }; then
    prog 100 done "무선 카플레이 준비됨. 아이폰을 연결해 보세요."
  fi
  n=0
  while true; do
    sleep 30 &
    wait $!
    logrotate
    ap_yield && continue
    ap_tick
    up
    wifi_events; cp_watch
    n=$((n+1))
    # once an hour: one line with the CarPlay connections
    [ $((n % 120)) -eq 0 ] && log "동작 중: $($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000") 개 카플레이 연결"
  done
}

[ "$HOTSPOT_LIB" = 1 ] || main
