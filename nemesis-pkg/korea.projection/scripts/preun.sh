#!/system/bin/sh
# preuninstall (NEMESIS가 서비스를 멈춘 뒤): 우리 hostapd·dnsmasq를 멈추고 우리 파일을 지운다.
# Wi-Fi는 껐다 켜지 않는다: 2026-11-06 니로에서 Wi-Fi를 껐다 켜면 USB가 다시 붙고(Wi-Fi/블루투스 모듈이
# 같은 USB 버스에 있는 것으로 보임) 블루투스 카플레이가 재부팅 전까지 되지 않았다. 일반 Wi-Fi는 차를 껐다
# 켜면 돌아온다(wifi_on이 켜져 있으므로). 설치 전에 Wi-Fi가 꺼져 있던 차만 다시 끈다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
BB=/system/bin/busybox
BK=/data/nemesis/backup/korea.projection
HOTSPOT_LIB=1 . /data/nemesis/apps/korea.projection/svc/hotspot.sh
# busybox가 없는 내비(K3·K8)는 우리 hostapd를 켠 적이 없다: 오류 줄만 나오므로 건너뛴다
has_bb && stop_all
rm -f $CONF
# Launch가 남긴 "설치 끝나면 다시 저장" 대기(status.sh --wait)도 멈추고, 진행 기록을 지운다
_wp=$(cat $W/wait.pid 2>/dev/null)
[ -n "$_wp" ] && $BB grep -q status.sh /proc/$_wp/cmdline 2>/dev/null && kill $_wp 2>/dev/null
rm -f $PROG $PROG.tmp
rm -rf $W
# 상태 화면용 파일 (bin/status.sh가 $W 밖에 쓴다)
rm -f /data/local/tmp/korea-projection-status.txt /data/local/tmp/korea-projection-status.txt.tmp
$BB ifconfig wlan0 0.0.0.0 2>/dev/null
# 업데이트 중이면(NEMESIS가 새 버전을 staging에 풀어 두고 예전 것의 preuninstall을 부름) Wi-Fi 설정과
# 백업은 그대로 두고 조용히 끝낸다. HMG-API의 preuninstall과 같은 판단: 부른 명령이 uninstall이 아니고,
# staging에 우리 패키지가 있을 때만 (중단된 설치가 남긴 staging 때문에 삭제가 무시되지 않게)
STAGE=/data/local/tmp/nemesis/stage/korea.projection
case "$(cat /proc/$PPID/cmdline 2>/dev/null)" in
  *uninstall*) ;;
  *)
    # busybox가 없는 내비도 있어(K3 #15) 셸 기본 grep을 쓴다
    if grep -q '^id=korea\.projection$' $STAGE/NEMESIS.data 2>/dev/null; then
      echo "korea.projection 업데이트: 이전 버전 정리"
      exit 0
    fi ;;
esac
remove_app
# 1.5: 우리가 설치한 HMG-API 무선 모드만 정리한다(mod.ours). 원래 있던 모드와 지도는 그대로 둔다
# (지도는 HMG-API의 다른 모드도 쓴다). 계획이 그 모드의 되돌리기뿐일 때만 적용하고, 아니면 앱에서 적용하라고 안내한다.
modmsg=""
if [ -f $BK/mod.ours ] && [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && hmgapid ping >/dev/null 2>&1; then
  if hmgapid engine remove $MOD_ID > $BK/mod-remove.txt 2>&1; then
    bad=0
    hmgapid engine plan > $BK/plan.txt 2>&1 || bad=1
    while IFS= read -r l; do
      case "$l" in
        "restore  "*|"setting  "*" back to stock"*|"unbind   "*|"same     "*) ;;
        "change   "*|"update   "*|"setting  "*|"bind     "*|"problem  "*|"rebase   "*|"nothing changed"*) bad=1 ;;
      esac
    done < $BK/plan.txt
    if [ $bad = 0 ] && hmgapid engine apply >/dev/null 2>&1; then
      echo "설치했던 HMG-API 무선 모드를 지움"
      modmsg=" 함께 설치했던 HMG-API 무선 모드도 지웠습니다."
    else
      echo "무선 모드를 지웠지만 적용하지 않음 (HMG-API 앱에서 적용 필요)"
      modmsg=" HMG-API 앱에서 변경 사항을 적용해 주세요(무선 모드 삭제)."
    fi
  else
    echo "무선 모드 지우기 실패"
    modmsg=" HMG-API 앱에서 무선 모드(Wireless CarPlay + Android Auto)를 지우고 적용해 주세요."
  fi
elif [ -f $BK/mod.ours ] && [ -f $HMGDATA/mods/$MOD_ID/mod.json ]; then
  # HMG-API 데몬이 응답하지 않으면 지울 수 없다. NEMESIS가 이 패키지의 백업 폴더($BK)를 지우므로 기록도 사라진다:
  # 차주에게 직접 지우라고 알린다.
  echo "HMG-API 데몬 응답 없음: 무선 모드를 지우지 못함"
  modmsg=" HMG-API 앱에서 무선 모드(Wireless CarPlay + Android Auto)를 지우고 적용해 주세요."
fi
# Wi-Fi 잠금(1.5.5)을 되돌린다: 설정 파일의 원래 소유자·권한, 치웠던 crc32 파일. 다음 부팅부터 Wi-Fi 서비스가
# 원래대로 wpa_supplicant를 띄운다(무선 카플레이 핫스팟은 이 패키지와 함께 없어진다).
wifi_unlock && echo "Wi-Fi 잠금 되돌림"
# 1이 아니면 꺼져 있던 것으로 본다(한 번도 안 켠 차는 null일 수 있다). 기록이 없으면 건드리지 않는다.
[ -f $BK/wifi_on ] && [ "$(cat $BK/wifi_on 2>/dev/null)" != 1 ] && svc wifi disable
# Wi-Fi 서비스가 있는 차(1.5.4)는 서비스가 Wi-Fi를 꺼 wifi_on이 0으로 바뀌었을 수 있다. 설치 전에 켜져 있었으면
# 값만 1로 되돌린다(지금 켜지는 않는다: 껐다 켜면 USB·블루투스가 다시 시작됨). 재부팅하면 원래대로 켜진다.
if [ -f $BK/wifi_on ] && [ "$(cat $BK/wifi_on 2>/dev/null)" = 1 ] && [ "$(settings get global wifi_on 2>/dev/null)" != 1 ]; then
  settings put global wifi_on 1
fi
rm -rf $BK
am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE \
  "Korea Projection을 삭제했습니다. 내비를 재부팅하면(RESET 버튼 또는 NEMESIS 재부팅) 일반 Wi-Fi가 원래대로 돌아옵니다.$modmsg" \
  --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
echo "korea.projection 삭제 완료"
exit 0
