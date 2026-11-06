#!/system/bin/sh
# Launch(bin/status.sh)가 뒤에서 띄운다: HMG-API Car Report를 USB에 저장한다(`hmgapid engine report --usb`).
# 새 차를 추가하려면 이 파일(그 차에서 직접 찾은 훅 지점 이름)이 필요하다. 만드는 데 1분쯤 걸려서,
# 화면을 기다리게 하지 않으려고 따로 돈다. 끝나면 토스트로 USB를 빼도 된다고 알린다.
# - 한 번에 하나만: carreport.lock 폴더(mkdir는 한 번에 하나만 성공). 남은 잠금은 이번 부팅의 살아 있는
#   carreport.sh가 아니면 지우고 다시 잡는다.
# - 최대 CR_MAX*CR_WAIT초(기본 5분)만 기다린다. HMG-API 데몬은 우리가 그만 기다려도 보고서를 끝까지 쓰므로,
#   시간이 넘으면 1분 더 기다린 뒤 알린다(쓰는 중에 USB를 빼지 않게).
# - 성공은 HMG-API가 "usb: /storage/usbN/HMG-API reports/…" 줄을 냈고, 그 usbN이 정말 마운트돼 있을 때만이다
#   (USB를 뺀 빈 마운트 폴더에 써도 그 줄이 나온다: Report.java).
# Car Report에는 HMG-API가 차종 수준 정보만 넣는다(VIN·전화번호·계정 없음, 휴대폰 주소는 지움: Report.java).
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
BB=${BB:-/system/bin/busybox}
W=${W:-/data/local/tmp/korea.projection}
BOOT_ID=${BOOT_ID:-/proc/sys/kernel/random/boot_id}
MOUNTS=${MOUNTS:-/proc/mounts}
CR_WAIT=${CR_WAIT:-5}
CR_MAX=${CR_MAX:-60}
CR_GRACE=${CR_GRACE:-60}
umask 077
$BB mkdir -p $W

toast() {
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
}

L=$W/carreport.lock
lock_alive() {
  _l=$(cat $L/pid 2>/dev/null)
  set -- $_l
  [ -n "$1" ] && [ "$2" = "$(cat $BOOT_ID 2>/dev/null)" ] && [ -d /proc/$1 ] \
    && $BB grep -q carreport.sh /proc/$1/cmdline 2>/dev/null
}
if ! $BB mkdir $L 2>/dev/null; then
  lock_alive && exit 0
  rm -rf $L
  $BB mkdir $L 2>/dev/null || exit 0
fi
echo "$$ $(cat $BOOT_ID 2>/dev/null)" > $L/pid

hmgapid engine report --usb > $W/carreport.txt 2>&1 &
p=$!
i=0; late=0
while kill -0 $p 2>/dev/null; do
  i=$((i+1))
  if [ $i -gt $CR_MAX ]; then kill $p 2>/dev/null; late=1; echo "시간 초과" >> $W/carreport.txt; break; fi
  sleep $CR_WAIT
done
wait $p 2>/dev/null
rc=$?
sync
ok=0
if [ $rc = 0 ]; then
  while IFS= read -r _x; do
    case "$_x" in
      "usb: /storage/usb"*"/HMG-API reports/"*)
        _m=${_x#usb: }; _m=${_m%%/HMG-API reports/*}
        $BB grep -q " $_m " $MOUNTS 2>/dev/null && ok=1 ;;
    esac
  done < $W/carreport.txt
fi
if [ $ok = 1 ]; then
  toast "Korea Projection: 제보 자료를 모두 저장했습니다. 이제 USB를 빼셔도 됩니다."
else
  # 시간이 넘었으면 HMG-API가 아직 쓰는 중일 수 있다: 조금 더 기다린 뒤 알린다
  [ $late = 1 ] && { sleep $CR_GRACE; sync; }
  toast "Korea Projection: 제보 자료(Car Report)를 저장하지 못했습니다. USB를 다시 꽂고 Launch를 눌러 주세요."
fi
rm -rf $L
exit 0
