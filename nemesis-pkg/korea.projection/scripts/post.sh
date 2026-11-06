#!/system/bin/sh
# postinstall (cwd /data/nemesis/apps/korea.projection): note Wi-Fi's setting for the
# uninstall, and stop the stick script's access point (cp-drive.sh) if one is running, so only
# this package's hostapd has wlan0. NEMESIS starts the service after this.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
BB=/system/bin/busybox
BK=/data/nemesis/backup/korea.projection
umask 077
mkdir -p $BK
[ -f $BK/wifi_on ] || settings get global wifi_on > $BK/wifi_on 2>/dev/null
# opt-in CarPlay log (svc/hotspot.sh, off by default): a file korea-projection-debug on the stick
W=/data/local/tmp/korea.projection
for u in /storage/usb0 /storage/usb1; do
  [ -f $u/korea-projection-debug ] && mkdir -p $W && : > $W/debug && echo "카플레이 디버그 로그 켬 ($W/cp.log)"
done
OLD=/data/local/tmp/cpdrive
P=$(cat $OLD/watchdog.pid 2>/dev/null)
if [ -n "$P" ] && $BB ps | $BB grep -v grep | $BB grep -q "^ *$P .*cpdrive/watchdog.sh"; then
  kill $P 2>/dev/null
  [ -f $OLD/log.pid ] && kill $(cat $OLD/log.pid) 2>/dev/null
  for p in $($BB ps | $BB grep -v grep | $BB grep "hostapd /data/misc/wifi/hostapd-cp.conf" | $BB awk '{print $1}'); do kill $p; done
  # cp-drive의 dnsmasq도 (우리 것과 명령 앞부분이 같아서 남겨 두면 우리 dnsmasq가 시작되지 않는다)
  for p in $($BB ps | $BB grep -v grep | $BB grep "dnsmasq --keep-in-foreground" | $BB awk '{print $1}'); do kill $p; done
  echo "USB 스크립트(cp-drive.sh)의 핫스팟을 멈춤"
fi
HOTSPOT_LIB=1 . /data/nemesis/apps/korea.projection/svc/hotspot.sh
# busybox가 없는 내비(K3 BDPE·K8 GL3HEV, #15·#19): 무선 설정은 하지 않는다(서비스도 대기만 함). 한 번 알린다.
# 상태 화면 앱만 설치한다(1.5.5): 앱이 없으면 Launch 때 NEMESIS가 "Error type 3 … does not exist"를 띄워 안내를 가린다.
# 앱 설치가 실패해도 패키지 설치는 성공으로 둔다(Launch 때 다시 시도). 결과는 $W/app-install.log에 남는다.
if ! has_bb; then
  install_app >/dev/null 2>&1
  m="Korea Projection: 이 내비에서는 아직 동작하지 않습니다(지원 조사 중). 무선 설정은 하지 않았습니다."
  echo "$m"
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$m" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
  exit 0
fi
# 상태 화면 앱: 실패해도 패키지 설치는 성공으로 둔다 (Launch를 누를 때 다시 시도)
# 문구에 핫스팟 상태를 쓰지 않는다: 여기서는 앱만 본다(1.5.3까지 "핫스팟은 정상"이라 써서 #9·#15가 오해함)
if ! install_app; then
  m="Korea Projection: 상태 화면 앱을 설치하지 못했습니다(Launch를 누르면 다시 시도). 무선 카플레이 설정은 따로 진행됩니다."
  echo "$m"
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$m" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
fi
if [ -d /data/nemesis/apps/niro.carplay.hotspot ]; then
  m="Korea Projection: 이전 패키지 niro.carplay.hotspot을 삭제하면 시작합니다."
  echo "$m"
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$m" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
fi
exit 0
