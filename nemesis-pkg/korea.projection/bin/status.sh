#!/system/bin/sh
# NEMESIS Manager > Korea Projection > Launch: 상태 토스트와 차량 제보용 리포트
# (USB가 꽂혀 있으면 USB의 KoreaProjection-report 폴더에 1-report.md, 3-log.txt로, 그리고 $W에 저장).
# 리포트에는 이름, 버전, 예/아니요, 개수만 넣는다. SSID, 비밀번호, 휴대폰 이름, MAC, IP는
# 넣지 않는다. 차 주인이 읽어 본 뒤 첨부한다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
BB=${BB:-/system/bin/busybox}
APP=${APP:-/data/nemesis/apps/korea.projection}
HOTSPOT_LIB=1 . $APP/svc/hotspot.sh
ISSUES=https://github.com/StopDragon/korea-projection/issues/new?template=car-report.yml
umask 077
bbx mkdir -p $W 2>/dev/null
# --wait(1.5.5): Launch를 설치 중에 누르면 뒤에서 한 번 더 돈다. 설치가 끝날 때까지(최대 15분) 기다렸다가 아래 보통
# 흐름으로 상태 파일·USB 제보 파일을 다시 만든다(그때 USB가 꽂혀 있으면). 상태 화면 앱은 진행 막대를 보여 주다가
# 상태 파일이 새로 쓰이면 결과 화면으로 바뀐다.
WAITED=0
if [ "$1" = --wait ]; then
  _i=0
  while $BB grep -q '^state=run$' $PROG 2>/dev/null && [ $_i -lt 180 ]; do sleep 5; _i=$((_i+1)); done
  rm -f $W/wait.pid
  WAITED=1
fi

yn() { if "$@" >/dev/null 2>&1; then echo 예; else echo 아니요; fi; }
# USB가 마운트돼 있는가 (마운트 지점 폴더는 USB가 없어도 있을 수 있어 /proc/mounts로 본다)
USBS="/storage/usb0 /storage/usb1"
usb_in() {
  for _u in $USBS; do bbx grep -q " $_u " /proc/mounts 2>/dev/null && return 0; done
  return 1
}
# 순정 파일 위치 (테스트에서 바꿀 수 있게)
SYSAPP=${SYSAPP:-/system/app}
SYSLIB=${SYSLIB:-/system/lib}
SYSONE=${SYSONE:-/system/onebin}
HMGSTOCK=${HMGSTOCK:-/data/hmgapi/stock}
# NEMESIS.data의 값 하나 (이 헤드유닛에는 sed/cut/tr이 없다)
pver() { _v=$($BB grep '^package-version=' "$1" 2>/dev/null); echo "${_v#package-version=}"; }
# USB 제보 폴더 이름. 사용자가 찾기 쉽게 고정한다(안내문과 같아야 한다).
# 안의 파일: 1-report.md(이 스크립트), 2-car-report.json(carreport.sh), 3-log.txt(이 스크립트)
RDIR=${RDIR:-KoreaProjection-report}
APLOG=${APLOG:-/data/nemesis/logs/korea.projection/ap.log}
# busybox가 없는 내비(K3 BDPE·K8 GL3HEV, tcc803x, #15·#19): 보통 리포트는 못 만든다. 셸 기본 명령(grep, mkdir, ls)만으로
# USB에 짧은 리포트를 남긴다(제품, 플랫폼, 이 내비에 있는 명령 목록: busybox 없이 다시 만들 때 참고). 개인정보는 없다.
# 1.5.5: 상태 화면 앱도 쓴다. 앱이 없으면 다시 설치하고(설치 때 실패했을 수 있음), 앱이 읽을 짧은 상태 파일
# (support=nobb)을 쓴다. 앱은 오류 대신 "아직 동작하지 않음(조사 중)" 화면을 보인다. 이 셸에는 printf가 없어 echo만 쓴다.
if ! has_bb; then
  install_app_once
  _nbw=0
  for u in /storage/usb0 /storage/usb1; do
    grep -q " $u " /proc/mounts 2>/dev/null || continue
    mkdir -p "$u/$RDIR" 2>/dev/null || continue
    {
      echo "# Korea Projection 리포트 (busybox 없는 내비)"
      echo "- 펌웨어: $(getprop ro.build.product)"
      echo "- 플랫폼: $(getprop ro.board.platform)"
      echo "- 이 패키지: $(grep '^package-version=' $APP/NEMESIS.data 2>/dev/null)"
      echo "- NEMESIS: $(nemesis version 2>/dev/null)"
      echo; echo "## /system/bin"; ls /system/bin
      echo; echo "## /system/xbin"; ls /system/xbin
    } > "$u/$RDIR/1-report.md" 2>/dev/null
    # 성공은 파일로 판단한다(묶음의 마지막 명령 ls의 종료 코드로 보지 않음)
    [ -s "$u/$RDIR/1-report.md" ] && sync && _nbw=1 && break
  done
  _st=${STATUS:-/data/local/tmp/korea-projection-status.txt}
  _pv=$(grep '^package-version=' $APP/NEMESIS.data 2>/dev/null)
  if [ "$_nbw" = 1 ]; then _us=saved; elif usb_in; then _us=fail; else _us=none; fi
  # .tmp에 쓴 뒤 바꾼다(열려 있는 화면이 반쯤 쓴 파일을 읽지 않게). toolbox mv는 -f 없이 같은 장치에서 덮어쓴다.
  ( umask 022
    { echo "support=nobb"
      echo "product=$(getprop ro.build.product)"
      echo "platform=$(getprop ro.board.platform)"
      echo "pkgver=${_pv#package-version=}"
      echo "usb=$_us"
      echo "made=$(date '+%m-%d %H:%M')"
    } > $_st.tmp 2>/dev/null && chmod 644 $_st.tmp 2>/dev/null && mv $_st.tmp $_st 2>/dev/null )
  # 앱이 있으면 화면이 안내한다. 토스트는 USB에 저장했을 때와, 앱이 없어 화면을 못 띄울 때만.
  if ! app_installed; then
    toast "Korea Projection: 이 내비에서는 아직 동작하지 않습니다(지원 조사 중). 무선 설정은 하지 않았습니다."
  elif [ "$_nbw" = 1 ]; then
    toast "Korea Projection: 제보 파일을 USB의 KoreaProjection-report 폴더에 저장했습니다."
  fi
  exit 0
fi
# 표준입력의 마지막 $1줄만 내면서 휴대폰 블루투스 주소(MAC)와 IP 주소를 x로 지운다(busybox tail 대신 awk)
lastmask() {
  # n = n + 0: 오래된 busybox awk에서 -v 값이 문자열로 비교되지 않게 숫자로 만든다
  $BB awk -v n="$1" 'BEGIN { n = n + 0 } { a[NR % n] = $0 }
    END { s = NR > n ? NR - n + 1 : 1
      for (i = s; i <= NR; i++) { l = a[i % n]
        gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/, "xx:xx:xx:xx:xx:xx", l)
        gsub(/[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/, "x.x.x.x", l)
        gsub(/[Ff][Ee]80:[0-9A-Fa-f:]*/, "fe80:x", l)
        print l } }'
}
# 분석용 로그(3-log.txt): 서비스 로그, 자동 설정 기록, HMG-API 로그.
# 휴대폰 이름이 들어가는 디버그 로그(cp.log)는 넣지 않는다. Wi-Fi 이름·비밀번호는 원래 어느 로그에도 없다.
logs() {
  echo "# Korea Projection 로그 ($(date '+%Y-%m-%d %H:%M'))"
  echo "제품: $(getprop ro.build.product), 패키지 $(pver $APP/NEMESIS.data)"
  echo "휴대폰 블루투스 주소와 IP 주소는 x로 지웠습니다. 첨부하기 전에 한 번 읽어 보시고, 내 정보가 보이면 그 줄을 지워 주세요."
  for _f in $APLOG $W/map-car.txt $W/plan.txt $W/verify-map.txt $W/verify-map2.txt $W/mod-install.txt $W/mod-apply.txt $W/carreport.txt $W/app-install.log; do
    echo; echo "== ${_f##*/}"
    if [ -f $_f ]; then lastmask 400 < $_f; else echo "(없음)"; fi
  done
  echo; echo "== HMG-API 로그 (마지막 800줄)"
  $BB cat $HMGLOG/log.log.1 $HMGLOG/log.log 2>/dev/null | lastmask 800
  echo; echo "== Wi-Fi 로그 (logcat, 마지막 300줄)"
  wifilog
}
# Wi-Fi 서비스·드라이버·핫스팟 쪽 logcat(1.5.4: 그랜저 하이브리드 #12에서 핫스팟이 30초마다 끊긴 원인을 보려고).
# 지금 logcat 버퍼에 남은 것만 본다(-d). Wi-Fi 이름·비밀번호·주변 네트워크·기기 이름이 나올 수 있는 줄은
# 통째로 버린다(ssid, psk, pass, name, bssid, extra:가 들어간 줄. NetworkInfo의 extra:에는 SSID가 들어간다).
# key는 버리지 않는다: hostapd의 "pairwise key handshake completed"가 연결 성공을 보여 준다. MAC·IP는 lastmask가 지운다.
# 전역 IPv6 주소는 지우지 못한다(이 차의 핫스팟은 IPv4만 쓴다). 첨부 전에 차주가 읽어 보도록 안내문이 있다.
WIFITAGS=' [VDIWEF]/(WifiStateMachine|WifiService|WifiController|WifiHW|WifiNative[^ (]*|SoftapController|SoftApController|wpa_supplicant|hostapd|Tethering|NetworkManagementService|CommandListener|bcmdhd|dhd) *\('
WIFIDROP='ssid|psk|pass|name|bssid|extra:'
wifilog() {
  logcat -d -v time 2>/dev/null | $BB grep -E "$WIFITAGS" | $BB grep -v -i -E "$WIFIDROP" | lastmask 300
}

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
  echo "- 설치 진행: $($BB awk -F= '$1 == "state" || $1 == "pct" || $1 == "stage" { printf "%s=%s  ", $1, $2 }' $PROG 2>/dev/null)"
  if car_in "$prod" "$CARS_OK"; then echo "- 확인된 차: 예"
  elif car_in "$prod" "$CARS_TRY"; then echo "- 확인된 차: 시험 지원 (차에서 아직 확인되지 않음, 결과를 알려 주세요)"
  elif car_in "$prod" "$CARS_AUTO"; then echo "- 확인된 차: 자동 시험 (이 차용 설정 없이 HMG-API가 차에서 지도를 만들어 시도, 결과를 알려 주세요)"
    for _f in automap.bad automap.checked automap.foreign; do [ -f $BK/$_f ] && echo "  - 기록: $_f"; done
  else echo "- 확인된 차: 아니요 (서비스가 대기만 함, 지원 차: $CARS)"; fi
  echo "- NEMESIS: $(nemesis version 2>/dev/null)"
  # 따옴표 없이: 두 줄이 한 줄로 합쳐진다
  echo "- HMG-API:" $($BB grep -E '^(version|build) ' /data/hmgapi/installed.txt 2>/dev/null)
  echo "- wireless.projection 설치: $(yn [ -d /data/nemesis/apps/wireless.projection ])"
  echo "- HMG-API 무선 모드: 설치 $(mod_state) / 켜짐 $(mod_on_state) / 무선 카플레이 설정(bridge) $(bridge_state)"
  echo "- HMG-API 훅(마지막 부팅 기록): $(hooks_state)"
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
  echo "- 다른 hostapd (순정 핫스팟): $(yn sh -c "$BB ps | $BB grep -v grep | $BB grep -v '$CONF' | $BB grep -q hostapd")"
  echo "- wpa_supplicant: $(yn running wpa_supplicant)"
  echo "- 지금 카플레이 연결 수: $($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000")"
  echo
  echo "## 순정 파일 체크섬 (새 차 추가용)"
  echo "무선 모드의 패치 세트(patches/<차>/stock)를 만드는 데 씁니다. 차종·펌웨어마다 같은 값이라 개인정보가 아닙니다."
  echo '```'
  # 큰 apk의 md5는 몇 초 걸린다: 리포트를 USB에 남길 때만 계산해 화면이 늦게 뜨지 않게 한다
  usb_in || echo "(USB를 꽂은 채 Launch를 누르면 채워집니다)"
  usb_in && for f in $SYSAPP/HKMC_DiPO.apk $SYSAPP/HKMC_DiPO.odex $SYSAPP/HKMC_GPM.apk $SYSAPP/HKMC_GPM.odex \
           $SYSAPP/HKMC_Navi_ExSL.apk $SYSAPP/HKMC_Navi_ExSL.odex $SYSAPP/Iap2ServerApp.apk $SYSAPP/Iap2ServerApp.odex \
           $SYSLIB/libautoreceiver_infobank.so $SYSLIB/libCarPlayCore.so $SYSLIB/libCarPlayAudio.so \
           $SYSLIB/libCarPlayUtils.so $SYSAPP/HKMC_BtSettings.apk; do
    # 모드가 바꾼 파일은 HMG-API가 순정 원본을 /data/hmgapi/stock<경로>에 둔다(CarMap과 같은 방식): 그것을 쓴다
    if [ -f $HMGSTOCK$f ]; then set -- $($BB md5sum < $HMGSTOCK$f); echo "${f##*/} $1 (HMG-API 순정 백업)"
    elif [ -f $f ]; then set -- $($BB md5sum < $f); echo "${f##*/} $1"; else echo "${f##*/} 없음"; fi
  done
  _fx=$SYSONE/$(getprop ro.mobis.onebindir)/featurexml.cfg
  if ! usb_in; then :
  elif [ -f $HMGSTOCK$_fx ]; then set -- $($BB md5sum < $HMGSTOCK$_fx); echo "featurexml.cfg $1 (HMG-API 순정 백업)"
  elif [ -f $_fx ]; then set -- $($BB md5sum < $_fx); echo "featurexml.cfg $1 (모드가 바꿨을 수 있음)"; else echo "featurexml.cfg 없음"; fi
  echo '```'
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
# HMG-API 무선 모드의 상태는 HMG-API 자기 파일로 본다(NEMESIS 목록은 wireless.projection과 충돌하면 등록되지 않고,
# 모드를 꺼도 남는다). /data/hmgapi/mods/<id>/mod.json: 설치, .disabled: 꺼짐,
# /data/hmgapi/settings/<id>.json의 "bridge":false: 무선 카플레이(블루투스 브리지) 설정 꺼짐 (Mods.java, settings.json)
HMGMOD=${HMGMOD:-/data/hmgapi/mods/wireless-carplay-aa}
HMGSET=${HMGSET:-/data/hmgapi/settings/wireless-carplay-aa.json}
mod_state() { yesno [ -f $HMGMOD/mod.json ]; }
# mod_on은 "꺼 두지 않았다"는 뜻일 뿐이다. HMG-API가 충돌·미지원으로 건너뛴 경우는 훅·무선 기능 값으로 드러난다.
# bridge는 저장된 설정 값이라 Apply changes 전에는 실제 동작과 다를 수 있다.
mod_on_state() { if [ -f $HMGMOD/mod.json ] && [ ! -f $HMGMOD/.disabled ]; then echo yes; else echo no; fi; }
bridge_state() { if $BB grep -q '"bridge" *: *false' $HMGSET 2>/dev/null; then echo off; else echo on; fi; }
# HMG-API가 부팅 때마다 남기는 "hook map: <상태> for …, hooks on|off" 줄 중 마지막 것 (log.log.1이 더 오래됨).
# 출력: "on|off <상태>" (상태: none, mismatch, mapped, verified 등). 줄이 없으면 빈 값.
# 이번 부팅의 줄을 놓치면 지난 부팅 기록일 수 있다(HMG-API 로그는 logcat에서 옮겨 적는다).
# map-check.json은 HMG-API 업데이트로 지도가 바뀌어도 ok로 남을 수 있어 로그를 본다.
HMGLOG=${HMGLOG:-/data/hmgapi/logs/hmgapi}
hooks_state() {
  $BB cat $HMGLOG/log.log.1 $HMGLOG/log.log 2>/dev/null | $BB awk '
    /hook map: .*, hooks on/ { s = "on"; i = index($0, "hook map: "); w = substr($0, i + 10); sub(/[ ,].*/, "", w) }
    /hook map: .*, hooks off/ { s = "off"; i = index($0, "hook map: "); w = substr($0, i + 10); sub(/[ ,].*/, "", w) }
    END { if (s != "") print s " " w }'
}
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
  # tested: 서비스가 동작하는 차인가 (앱은 no면 "대기 중"으로 보인다). 시험 지원 차도 yes다.
  car_in "$_prod" "$CARS" && echo "tested=yes" || echo "tested=no"
  echo "hmgapi="$($BB grep -E '^(version|build) ' /data/hmgapi/installed.txt 2>/dev/null)
  echo "nemesis=$(nemesis version 2>/dev/null)"
  echo "wp=$(yesno [ -d /data/nemesis/apps/wireless.projection ])"
  echo "mod=$(mod_state)"
  echo "mod_on=$(mod_on_state)"
  echo "bridge=$(bridge_state)"
  _hk=$(hooks_state)
  echo "hooks=${_hk%% *}"
  echo "hookmap=${_hk#* }"
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
install_app_once

R=$W/korea-projection-report.md
report > $R 2>/dev/null
$BB chmod 600 $R
G=$W/korea-projection-log.txt
# 로그 모으기는 몇 초 걸릴 수 있어 USB가 있을 때만 한다
if usb_in; then logs > $G 2>/dev/null; $BB chmod 600 $G; fi
where=""
for u in $USBS; do
  # 마운트 지점 폴더는 USB가 없어도 있을 수 있다: /proc/mounts로 확인
  # 제보 자료는 USB의 한 폴더($RDIR)에 정해진 이름으로 둔다: 1-report.md, 2-car-report.json(carreport.sh), 3-log.txt
  # 예전 Launch의 2-car-report.json은 지운다(새 1·3번과 섞이지 않게. 필요하면 carreport.sh가 새로 만든다)
  $BB grep -q " $u " /proc/mounts 2>/dev/null && $BB mkdir -p "$u/$RDIR" && $BB rm -f "$u/$RDIR/2-car-report.json" \
    && $BB cp $R "$u/$RDIR/1-report.md" 2>/dev/null && $BB cp $G "$u/$RDIR/3-log.txt" 2>/dev/null && sync && where=$u && break
done

# 설치가 아직 진행 중이면 끝난 뒤에 한 번 더 돌도록 뒤에 남긴다(한 번에 하나만, 이번 부팅의 것만)
if [ $WAITED = 0 ] && $BB grep -q '^state=run$' $PROG 2>/dev/null; then
  _wp=$(cat $W/wait.pid 2>/dev/null)
  if [ -z "$_wp" ] || [ ! -d /proc/$_wp ] || ! $BB grep -q status.sh /proc/$_wp/cmdline 2>/dev/null; then
    $BB setsid sh $APP/bin/status.sh --wait </dev/null >/dev/null 2>&1 &
    echo $! > $W/wait.pid
  fi
fi
# 상태는 이어서 열리는 화면(StatusActivity)이 보여 준다. 토스트는 USB에 리포트를 저장했을 때만.
[ -n "$where" ] || exit 0
a=off; running "hostapd $CONF" && a=on
d=off; running "$DNSMASQ" && d=on
c=$($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000")
# 켜짐/꺼짐
[ $a = on ] && a=켜짐 || a=꺼짐; [ $d = on ] && d=켜짐 || d=꺼짐
m="Korea Projection: 핫스팟 $a, DHCP $d, 카플레이 연결 $c개"
m="$m. 제보 자료를 USB의 $RDIR 폴더에 저장했습니다."
# 확인된 차가 아니거나(시험 지원 차 포함) HMG-API 훅이 켜져 있지 않으면, 새 차 추가·결과 분석에 필요한
# HMG-API Car Report도 뒤에서 만들어 같은 폴더에 저장한다(1분쯤, 화면은 기다리지 않음). 끝나면 carreport.sh가 토스트로 알린다.
_need=0
car_in "$(getprop ro.build.product)" "$CARS_OK" || _need=1
_hk=$(hooks_state); [ "${_hk%% *}" = on ] || _need=1
if [ $_need = 1 ] && command -v hmgapid >/dev/null 2>&1 && [ -f $APP/bin/carreport.sh ]; then
  W=$W RDIR=$RDIR $BB setsid sh $APP/bin/carreport.sh </dev/null >/dev/null 2>&1 &
  m="Korea Projection: 제보 자료를 USB의 $RDIR 폴더에 저장하는 중입니다(약 1분). '이제 USB를 빼셔도 됩니다'가 뜰 때까지 꽂아 두세요."
fi
echo "$m"
am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$m" \
  --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
exit 0
