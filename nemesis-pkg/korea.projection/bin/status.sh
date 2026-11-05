#!/system/bin/sh
# NEMESIS Manager > Korea Projection > Launch: 상태 토스트와 차량 제보용 리포트
# (korea-projection-report.md: USB가 꽂혀 있으면 USB에, 그리고 $W에 저장).
# 리포트에는 이름, 버전, 예/아니요, 개수만 넣는다. SSID, 비밀번호, 휴대폰 이름, MAC, IP는
# 넣지 않는다. 차 주인이 읽어 본 뒤 첨부한다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
BB=${BB:-/system/bin/busybox}
APP=${APP:-/data/nemesis/apps/korea.projection}
HOTSPOT_LIB=1 . $APP/svc/hotspot.sh
ISSUES=https://github.com/StopDragon/korea-projection/issues/new?template=car-report.yml
umask 077
$BB mkdir -p $W

yn() { if "$@" >/dev/null 2>&1; then echo 예; else echo 아니요; fi; }
# NEMESIS.data의 값 하나 (이 헤드유닛에는 sed/cut/tr이 없다)
pver() { _v=$($BB grep '^package-version=' "$1" 2>/dev/null); echo "${_v#package-version=}"; }

report() {
  prod=$(getprop ro.build.product)
  echo "# Korea Projection 리포트"
  echo
  echo "첨부하기 전에 읽어 보세요. 이름, 버전, 예/아니요, 개수만 들어 있습니다"
  echo "(SSID, 비밀번호, 휴대폰 이름, MAC, IP 주소는 없습니다)."
  echo "제보: $ISSUES"
  echo
  echo "## 내비(헤드유닛)"
  echo "- 펌웨어 (NEMESIS os): $prod"
  echo "- targetdir (NEMESIS models): $(getprop ro.mobis.targetdir)"
  echo "- onebin: $(getprop ro.mobis.onebindir)"
  echo "- 이 패키지 버전: $(pver $APP/NEMESIS.data)"
  case "$prod" in $CARS) echo "- 확인된 차: 예" ;; *) echo "- 확인된 차: 아니요 (서비스가 대기만 함, 확인된 차: $CARS)" ;; esac
  echo "- NEMESIS: $(nemesis version 2>/dev/null)"
  # 따옴표 없이: 두 줄이 한 줄로 합쳐진다
  echo "- HMG-API:" $($BB grep -E '^(version|build) ' /data/hmgapi/installed.txt 2>/dev/null)
  echo "- wireless.projection 설치: $(yn [ -d /data/nemesis/apps/wireless.projection ])"
  echo "- HMG-API 무선 모드(hmgapi.wireless-carplay-aa) 목록: $(yn [ -d /data/nemesis/apps/hmgapi.wireless-carplay-aa ])"
  echo
  echo "## 무선 기능 (pm list features)"
  # 이름 뒤에 줄바꿈을 붙여 android.hardware.wifi가 ...wifi.direct와 섞이지 않게 한다
  feats="$(pm list features 2>/dev/null)
"
  for f in com.hkmc.software.connectivity.carplay_wireless com.hkmc.software.connectivity.androidauto_wireless \
           com.hkmc.software.wifihotspot android.hardware.wifi; do
    case "$feats" in *"feature:$f
"*) echo "- $f: 예" ;; *) echo "- $f: 아니요" ;; esac
  done
  for p in persist.ium.support persist.wifi.state persist.sys.iap2.wifi persist.iap2.iden.wireless persist.service.adb.tcp.enable; do
    echo "- $p=$(getprop $p)"
  done
  echo
  echo "## Wi-Fi"
  echo "- Wi-Fi 장치(wlan0): $(yn [ -d /sys/class/net/wlan0 ])"
  echo "- 순정 hostapd: $(yn [ -x /system/bin/hostapd ]), dnsmasq: $(yn [ -x /system/bin/dnsmasq ])"
  echo "- Wi-Fi 설정(wifi_on): $(settings get global wifi_on 2>/dev/null)"
  parse_conf $SRC
  echo "- softap.conf: $(yn [ -s $SRC ]), 찾은 문자열 ${NS:-0}개, 카플레이 SSID 길이 ${#S2}, 비밀번호 길이 ${#S4}"
  echo "- 우리 hostapd: $(yn running "hostapd $CONF"), 우리 DHCP: $(yn running "$DNSMASQ")"
  echo "- 다른 hostapd (순정 핫스폿): $(yn sh -c "$BB ps | $BB grep -v grep | $BB grep -v '$CONF' | $BB grep -q hostapd")"
  echo "- wpa_supplicant: $(yn running wpa_supplicant)"
  echo "- 지금 카플레이 연결 수: $($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000")"
  echo
  echo "## 서비스 로그 (ap.log 마지막 20줄)"
  echo '```'
  L=/data/nemesis/logs/korea.projection/ap.log
  [ -f $L ] && { $BB tail -n 20 $L 2>/dev/null || cat $L; }
  echo '```'
  echo
  echo "_만든 시각 $(date '+%Y-%m-%d %H:%M')_"
}

# 상태 화면 앱(StatusActivity)이 읽는 key=value 파일. 앱은 root가 아니므로 누구나 읽을 수 있게(644)
# /data/local/tmp 바로 아래에 둔다. 값은 예/아니요·버전·개수·길이뿐이다 (SSID, 비밀번호, 휴대폰 이름, MAC, IP 없음).
STATUS=${STATUS:-/data/local/tmp/korea-projection-status.txt}
yesno() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
status_kv() {
  _prod=$(getprop ro.build.product)
  _feats="$(pm list features 2>/dev/null)
"
  _has() { case "$_feats" in *"feature:$1
"*) echo yes ;; *) echo no ;; esac; }
  parse_conf $SRC
  echo "product=$_prod"
  echo "targetdir=$(getprop ro.mobis.targetdir)"
  echo "pkgver=$(pver $APP/NEMESIS.data)"
  case "$_prod" in $CARS) echo "tested=yes" ;; *) echo "tested=no" ;; esac
  echo "hmgapi="$($BB grep -E '^(version|build) ' /data/hmgapi/installed.txt 2>/dev/null)
  echo "nemesis=$(nemesis version 2>/dev/null)"
  echo "wp=$(yesno [ -d /data/nemesis/apps/wireless.projection ])"
  echo "mod=$(yesno [ -d /data/nemesis/apps/hmgapi.wireless-carplay-aa ])"
  echo "feat_carplay=$(_has com.hkmc.software.connectivity.carplay_wireless)"
  echo "feat_aa=$(_has com.hkmc.software.connectivity.androidauto_wireless)"
  echo "feat_wifi=$(_has android.hardware.wifi)"
  echo "wlan0=$(yesno [ -d /sys/class/net/wlan0 ])"
  echo "softap_strings=${NS:-0}"
  echo "ssid_len=${#S2}"
  echo "pass_len=${#S4}"
  echo "our_ap=$(yesno running "hostapd $CONF")"
  echo "our_dhcp=$(yesno running "$DNSMASQ")"
  echo "other_ap=$(yesno sh -c "$BB ps | $BB grep -v grep | $BB grep -v '$CONF' | $BB grep -q hostapd")"
  echo "wpa=$(yesno running wpa_supplicant)"
  echo "cp_conn=$($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000")"
  echo "made=$(date '+%Y-%m-%d %H:%M')"
}
( umask 022; status_kv > $STATUS.tmp 2>/dev/null && $BB chmod 644 $STATUS.tmp && $BB mv -f $STATUS.tmp $STATUS )

# 상태 화면 앱이 없으면(설치 때 실패) 여기서 다시 설치해 본다. 이어서 NEMESIS가 화면을 연다.
# 한 부팅에 한 번만 (sys.boot_completed를 바꿀 때마다 init의 부팅 완료 트리거가 다시 돌기 때문)
if ! app_installed; then
  _bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  if [ "$(cat $W/app-try 2>/dev/null)" != "$_bid" ]; then
    echo "$_bid" > $W/app-try
    install_app >/dev/null 2>&1
  fi
fi

R=$W/korea-projection-report.md
report > $R 2>/dev/null
$BB chmod 600 $R
where=""
for u in /storage/usb0 /storage/usb1; do
  # 마운트 지점 폴더는 USB가 없어도 있을 수 있다: /proc/mounts로 확인
  $BB grep -q " $u " /proc/mounts 2>/dev/null && $BB cp $R $u/korea-projection-report.md 2>/dev/null && sync && where=$u && break
done

# 상태는 이어서 열리는 화면(StatusActivity)이 보여 준다. 토스트는 USB에 리포트를 저장했을 때만.
[ -n "$where" ] || exit 0
a=off; running "hostapd $CONF" && a=on
d=off; running "$DNSMASQ" && d=on
c=$($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000")
# 켜짐/꺼짐
[ $a = on ] && a=켜짐 || a=꺼짐; [ $d = on ] && d=켜짐 || d=꺼짐
m="Korea Projection: 핫스폿 $a, DHCP $d, 카플레이 연결 $c개"
m="$m. 리포트를 USB에 저장했습니다(korea-projection-report.md)."
echo "$m"
am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$m" \
  --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
exit 0
