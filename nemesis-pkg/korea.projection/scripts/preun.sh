#!/system/bin/sh
# preuninstall (NEMESIS가 서비스를 멈춘 뒤): 우리 hostapd·dnsmasq를 멈추고 우리 파일을 지운다.
# Wi-Fi는 껐다 켜지 않는다: 2026-11-06 니로에서 Wi-Fi를 껐다 켜면 USB가 다시 붙고(Wi-Fi/블루투스 모듈이
# 같은 USB 버스에 있는 것으로 보임) 블루투스 카플레이가 재부팅 전까지 되지 않았다. 일반 Wi-Fi는 차를 껐다
# 켜면 돌아온다(wifi_on이 켜져 있으므로). 설치 전에 Wi-Fi가 꺼져 있던 차만 다시 끈다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
BB=/system/bin/busybox
BK=/data/nemesis/backup/korea.projection
HOTSPOT_LIB=1 . /data/nemesis/apps/korea.projection/svc/hotspot.sh
stop_all
rm -f $CONF
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
    if $BB grep -q '^id=korea\.projection$' $STAGE/NEMESIS.data 2>/dev/null; then
      echo "korea.projection 업데이트: 이전 버전 정리"
      exit 0
    fi ;;
esac
remove_app
[ "$(cat $BK/wifi_on 2>/dev/null)" = 0 ] && svc wifi disable
rm -rf $BK
am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE \
  "Korea Projection을 삭제했습니다. 차를 껐다 켜면(문 열고 닫기) 일반 Wi-Fi가 원래대로 돌아옵니다." \
  --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
echo "korea.projection 삭제 완료"
exit 0
