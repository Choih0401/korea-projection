#!/bin/sh
# PC(맥)에서 가짜 헤드유닛 환경으로 korea.projection 패키지와 USB 테스트 스크립트를 돌린다.
# 차에 올리기 전에 실행한다: sh tests/stub-test.sh   (실패하면 FAIL 줄과 종료 코드 1)
# 가짜 도구: getprop, pm, nemesis, hmgapid, am, settings, svc, ps, netstat, sleep, busybox
B=$(cd "$(dirname "$0")/.." && pwd)
PKG=$B/nemesis-pkg/korea.projection
T=$(mktemp -d /tmp/kp-stub.XXXXXX)
trap 'rm -rf $T' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

mkdir -p $T/bin $T/app $T/w $T/apps $T/d $T/usb0/packages $T/logs
printf '#!/bin/sh\nexec "$@"\n' > $T/bin/bb
cat > $T/bin/getprop <<E
#!/bin/sh
case "\$1" in
  ro.build.product) cat $T/product 2>/dev/null || echo DEPEHEV.KOR.0000.V039.001.260902 ;;
  ro.mobis.targetdir) echo /system/onebin/depehev_kr/ ;;
  ro.mobis.onebindir) echo depehev_kr ;;
  sys.boot_completed) echo 1 ;;
  *) echo 0 ;;
esac
E
cat > $T/bin/pm <<E
#!/bin/sh
[ -f $T/feat ] && echo feature:com.hkmc.software.connectivity.carplay_wireless
echo feature:android.hardware.wifi.direct
E
cat > $T/bin/nemesis <<E
#!/bin/sh
echo "nemesis \$*" >> $T/calls
case "\$1" in
  install) case "\$2" in
      *korea.projection.zip) [ -f $T/install_ok ] && mkdir -p $T/apps/korea.projection ;;
      *wireless.projection.zip) [ -f $T/wp_reinstall_fails ] || mkdir -p $T/apps/wireless.projection ;;
    esac ;;
  uninstall) [ "\$2" = wireless.projection ] && [ ! -f $T/wp_stuck ] && rmdir $T/apps/wireless.projection 2>/dev/null ;;
  version) echo 1.16.6 ;;
esac
exit 0
E
cat > $T/bin/hmgapid <<E
#!/bin/sh
echo "hmgapid \$*" >> $T/calls
exit 0
E
for c in svc settings; do printf '#!/bin/sh\necho "%s $*" >> %s/calls\necho 1\n' $c $T > $T/bin/$c; done
printf '#!/bin/sh\necho "$*" > %s/toast\n' $T > $T/bin/am
printf '#!/bin/sh\ncat %s/ps 2>/dev/null\n' $T > $T/bin/ps
printf '#!/bin/sh\necho "tcp 0 0 192.168.43.1:7000 192.168.43.23:50000 ESTABLISHED"\n' > $T/bin/netstat
printf '#!/bin/sh\n/bin/sleep 0.01\n' > $T/bin/sleep
chmod +x $T/bin/*
# /sbin: 맥의 md5sum 위치
fixpath() { sed "s#^export PATH=.*#export PATH=$T/bin:/usr/bin:/bin:/sbin#" "$1"; }

# --- 1. hotspot.sh: softap.conf 해석, 설정 파일 이름 길이, printf ---
python3 - $T/softap.conf <<'E'
import struct,sys
u=lambda s:struct.pack('>H',len(s))+s.encode()
open(sys.argv[1],'wb').write(struct.pack('>i',3)+u('HotspotName1')+u('SSID\\cX')+u('x')+u('PASS\\word99'))
E
cp -R $PKG/* $T/app/
fixpath $PKG/svc/hotspot.sh > $T/app/svc/hotspot.sh
out=$(HOTSPOT_LIB=1 BB=$T/bin/bb SRC=$T/softap.conf W=$T/w sh -c '. '$T'/app/svc/hotspot.sh; parse_conf $SRC; printf "%s|%s|%s|%s\n" "$NS" "$S2" "$S4" "hostapd $CONF"')
# (맥의 sh echo는 \c를 해석하므로 테스트 쪽도 printf로 출력한다)
check "softap.conf 문자열 4개" '[ "${out%%|*}" = 4 ]'
check "백슬래시가 든 SSID/비밀번호 그대로" 'case "$out" in *"|SSID\\cX|PASS\\word99|"*) true;; *) false;; esac'
cmd=${out##*|}
check "hostapd 명령줄 ${#cmd}자 <= 45 (ps 잘림 대비)" '[ ${#cmd} -le 45 ]'

# --- 1b. hotspot.sh fix_perms: HMG-API 기록과 같은 권한 파일 되돌리기 (11-06 차의 engine status 줄 그대로) ---
mkdir -p $T/fp/bin $T/fp/perms $T/fp/w
cat > $T/fp/status <<E
CHANGED  $T/fp/perms/com.hkmc.software.connectivity.androidauto_wireless.xml [wireless-carplay-aa] stock fa91812d3eeee415768018ab6ee6804a, expected fa91812d3eeee415768018ab6ee6804a, found absent
CHANGED  $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml [wireless-carplay-aa] stock 95ff801a064526de56059dba10960b05, expected 95ff801a064526de56059dba10960b05, found absent
ok       /system/lib/libleafiaaac.so [wireless-carplay-aa] stock absent, expected a63e6492f38d541518b9606a978f5da3
CHANGED  $T/fp/perms/com.hkmc.software.other.xml [x] stock 00000000000000000000000000000000, expected 00000000000000000000000000000000, found absent
CHANGED  /system/lib/libfoo.so [x] stock 1, expected 2, found absent
CHANGED  /system/onebin/depehev_kr/featurexml.cfg [wireless-carplay-aa] stock c3fa5e8597b0a3e437ee81a6efc0e63a, expected 2a7ca4d59cb0bc3e6165042c1b8c62bc, found c3fa5e8597b0a3e437ee81a6efc0e63a
E
cat > $T/fp/bin/hmgapid <<E
#!/bin/sh
echo "hmgapid \$*" >> $T/fp/calls
case "\$*" in
  ping) [ -f $T/fp/down ] && exit 1; exit 0 ;;
  "engine status") cat $T/fp/status ;;
  "engine plan") cat $T/fp/plan ;;
esac
exit 0
E
printf '#!/bin/sh\necho "$*" > %s/fp/toast\n' $T > $T/fp/bin/am
printf '#!/bin/sh\n/bin/sleep 0.01\n' > $T/fp/bin/sleep
chmod +x $T/fp/bin/*
cat > $T/fp/plan <<E
rebase   /system/onebin/depehev_kr/featurexml.cfg: changed outside HMG-API (now c3fa), the mods' changes go on it
same     $T/fp/perms/com.hkmc.software.connectivity.androidauto_wireless.xml [wireless-carplay-aa]
same     $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml [wireless-carplay-aa]
change   /system/onebin/depehev_kr/featurexml.cfg [wireless-carplay-aa] -> 2a7ca4d59cb0bc3e6165042c1b8c62bc   [restart the head unit]
same     setting prop/persist.ium.support = carplay [wireless-carplay-aa]
E
echo "/dev/block/system /system ext4 ro,relatime 0 0" > $T/fp/mounts
fp() { (cd $T/fp && PATH=$T/fp/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 FIX_DELAY=0 BB=$T/bin/bb W=$T/fp/w PERMS=$T/fp/perms MOUNTS=$T/fp/mounts sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$T'/fp/bin:/usr/bin:/bin:/sbin; fix_perms'); }
fpreset() { rm -rf $T/fp/perms $T/fp/calls $T/fp/toast $T/fp/down; mkdir -p $T/fp/perms; }
# cwd($T/fp)에 한 글자 이름 "w" 폴더가 있다: "[wireless-carplay-aa]"가 파일 이름 패턴으로 풀리면 "w"로 바뀌어 잡힌다
fpreset; fp > $T/fp/out
check "fix_perms: 기록과 md5가 같은 권한 파일 2개만 씀" '[ "$(ls $T/fp/perms | wc -l | tr -d " ")" = 2 ] && [ "$(md5sum < $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml | cut -c1-32)" = 95ff801a064526de56059dba10960b05 ]'
check "  md5가 다른 권한 파일·라이브러리·설정 파일은 건드리지 않음" '[ ! -f $T/fp/perms/com.hkmc.software.other.xml ] && grep -q "건너뜀: com.hkmc.software.other" $T/fp/out'
check "  계획이 우리 것뿐 → 일반 apply, --force 안 씀, 재시작 안내" 'grep -qx "hmgapid engine apply" $T/fp/calls && ! grep -q -- --force $T/fp/calls && grep -q "껐다 켜" $T/fp/toast'
check "  /system이 ro였으면 rw → ro로 되돌림" 'grep -q "remount rw" $T/fp/calls && grep -q "remount ro" $T/fp/calls'
rm -f $T/fp/calls $T/fp/toast; fp > $T/fp/out
check "  파일이 이미 있으면 다시 쓰지도 apply하지도 않음" '! grep -q "engine apply" $T/fp/calls && [ ! -f $T/fp/toast ]'
fpreset; echo "/dev/block/system /system ext4 rw,relatime 0 0" > $T/fp/mounts; fp > $T/fp/out
check "  /system이 원래 rw였으면 ro로 바꾸지 않음" '! grep -q "remount ro" $T/fp/calls'
echo "/dev/block/system /system ext4 ro,relatime 0 0" > $T/fp/mounts
fpreset; cp $T/fp/plan $T/fp/plan.ok; echo "change   /system/app/HKMC_DiPO.apk [other-mod] -> 1234   [restart the app]" >> $T/fp/plan; fp > $T/fp/out
check "  계획에 다른 변경이 있으면 apply하지 않고 앱에서 적용하라고 안내" '! grep -qx "hmgapid engine apply" $T/fp/calls && grep -q "HMG-API 앱에서" $T/fp/toast'
cp $T/fp/plan.ok $T/fp/plan
fpreset; sed 's/change   \/system\/onebin\/depehev_kr\/featurexml.cfg \[wireless-carplay-aa\]/change   \/system\/onebin\/depehev_kr\/featurexml.cfg [other-mod]/' $T/fp/plan.ok > $T/fp/plan; fp > $T/fp/out
check "  featurexml.cfg 변경이 다른 모드 것이면 apply 안 함" '! grep -qx "hmgapid engine apply" $T/fp/calls'
fpreset; cp $T/fp/plan.ok $T/fp/plan; echo "rebase   /system/app/X.apk: changed outside HMG-API (now 1), the mods' changes go on it" >> $T/fp/plan; fp > $T/fp/out
check "  featurexml.cfg 아닌 rebase가 있으면 apply 안 함" '! grep -qx "hmgapid engine apply" $T/fp/calls'
fpreset; cp $T/fp/plan.ok $T/fp/plan; echo "WARNING: the car's ADB TCP switch is on" >> $T/fp/plan; fp > $T/fp/out
check "  ADB 경고 같은 WARNING 줄은 막지 않음" 'grep -qx "hmgapid engine apply" $T/fp/calls'
fpreset; cp $T/fp/plan.ok $T/fp/plan; mv $T/fp/mounts $T/fp/mounts.x; fp > $T/fp/out; mv $T/fp/mounts.x $T/fp/mounts
check "  /proc/mounts를 못 읽으면 ro로 보고 ro로 되돌림" 'grep -q "remount ro" $T/fp/calls'
cp $T/fp/plan.ok $T/fp/plan
fpreset; touch $T/fp/down; fp > $T/fp/out
check "  HMG-API 데몬이 안 뜨면 아무것도 안 하고 기록만" '[ -z "$(ls $T/fp/perms)" ] && grep -q "데몬 응답 없음" $T/fp/out'

# 시작할 때의 stop_ap는 뒤에서 도는 확인 작업(fix.pid)을 건드리지 않고, 끝낼 때의 stop_all만 정리한다
mkdir -p $T/sa; echo "12345 boot" > $T/sa/fix.pid
(PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/sa sh -c '. '$T'/app/svc/hotspot.sh; stop_ap') >/dev/null 2>&1
check "stop_ap(시작 때)는 fix.pid를 남김" '[ -f $T/sa/fix.pid ]'
(PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/sa sh -c '. '$T'/app/svc/hotspot.sh; stop_all') >/dev/null 2>&1
check "stop_all(끝낼 때)는 fix.pid를 정리" '[ ! -f $T/sa/fix.pid ]'

# --- 1c. 상태 화면 앱: Report(판단·제보 링크)와 QR 크기, QrCode가 HMG-API 원본과 같은지 ---
if command -v javac >/dev/null 2>&1; then
  J=$T/java; mkdir -p $J
  if javac -nowarn -encoding UTF-8 -d $J $B/nemesis-pkg/app-src/java/korea/projection/app/Report.java \
       $B/nemesis-pkg/app-src/java/korea/projection/app/QrCode.java $B/tests/ReportTest.java 2>$T/javac.err; then
    java -cp $J korea.projection.app.ReportTest > $T/java.out 2>&1
    jr=$?
    grep -E "^(ok|FAIL)" $T/java.out | sed 's/^/  [Java] /'
    check "Java 테스트 전부" '[ $jr -eq 0 ]'
  else
    cat $T/javac.err; check "Java 컴파일" 'false'
  fi
  UP=$B/pr22-rebase/core/app/java/hmgapi/app/QrCode.java
  if [ -f $UP ]; then
    check "QrCode.java는 HMG-API 원본과 package 줄만 다름" '[ "$(sed 1,4d $B/nemesis-pkg/app-src/java/korea/projection/app/QrCode.java | sed 1d | md5sum)" = "$(sed 1d $UP | md5sum)" ]'
  fi
fi

# --- 1d. 상태 화면 앱 설치: 읽을 수 있는 곳에 복사해 직접 설치, 실패해도 패키지는 그대로 ---
IA=$T/ia; mkdir -p $IA/bin $IA/w $IA/tmp; echo apk > $IA/src.apk
cat > $IA/bin/pm <<E
#!/bin/sh
echo "pm \$*" >> $IA/calls
case "\$1" in
  install) echo "	pkg: \$3"; if [ -f $IA/ok ]; then echo Success; else echo "Failure [INSTALL_FAILED_INVALID_URI]"; fi ;;
  path) [ -f $IA/ok ] && echo package:/data/app/korea.projection.app-1.apk ;;
esac
exit 0
E
printf '#!/bin/sh\ncat %s/boot 2>/dev/null || echo 1\n' $IA > $IA/bin/getprop
printf '#!/bin/sh\necho "setprop $*" >> %s/calls; echo "$2" > %s/boot\n' $IA $IA > $IA/bin/setprop
chmod +x $IA/bin/*
ia() { (PATH=$IA/bin:/usr/bin:/bin HOTSPOT_LIB=1 BB=$T/bin/bb W=$IA/w APK_SRC=$IA/src.apk APK_COPY=$IA/tmp/kp.apk sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$IA'/bin:/usr/bin:/bin; install_app; echo "rc=$?"'); }
out=$(ia)
check "앱 설치 실패 → 1 돌려주고 기록, boot_completed는 1로 되돌림" 'echo "$out" | grep -q "rc=1" && grep -q "INVALID_URI" $IA/w/app-install.log && [ "$(cat $IA/boot)" = 1 ] && grep -q "setprop sys.boot_completed 0" $IA/calls'
check "  pm에는 읽을 수 있는 복사본(644)을 줌" 'grep -q "pm install -r $IA/tmp/kp.apk" $IA/calls && [ "$(stat -f %Lp $IA/tmp/kp.apk)" = 644 ]'
touch $IA/ok; rm -f $IA/calls; out=$(ia)
check "앱 설치 성공 → 0, 복사본 지움" 'echo "$out" | grep -q "rc=0" && [ ! -f $IA/tmp/kp.apk ]'
check "  app_installed는 pm path 출력으로 판단" '(PATH=$IA/bin:/usr/bin:/bin HOTSPOT_LIB=1 BB=$T/bin/bb W=$IA/w sh -c ". $T/app/svc/hotspot.sh; export PATH=$IA/bin:/usr/bin:/bin; app_installed")'

# --- 2. status.sh: 리포트, 비밀 미포함, USB 마운트 확인 ---
fixpath $PKG/bin/status.sh | sed -e "s#/storage/usb0 /storage/usb1#$T/usb0#" \
  -e "s#/proc/mounts#$T/mounts#" -e "s#/data/nemesis/logs/korea.projection/ap.log#$T/logs/ap.log#" > $T/st.sh
STF=$T/status.txt
echo "  101 root  hostapd /data/misc/wifi/hostapd-kp.conf" > $T/ps
: > $T/mounts
STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "USB가 마운트 안 됐으면 USB에 쓰지 않고 토스트도 없음 (상태는 화면이 보여 줌)" '[ ! -f $T/usb0/korea-projection-report.md ] && [ ! -f $T/toast ]'
echo "/dev/block/sda1 $T/usb0 vfat rw 0 0" > $T/mounts
STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
R=$T/usb0/korea-projection-report.md
check "상태 화면용 파일: 644, 키 21개" '[ "$(stat -f %Lp $STF)" = 644 ] && [ "$(grep -c "=" $STF)" = 21 ]'
check "  SSID·비밀번호·폰 IP 없음, 길이만" '! grep -q -e "SSID.cX" -e PASS -e HotspotName -e 192.168.43.23 $STF && grep -qx "ssid_len=7" $STF'
check "  화면 키와 같은 이름 (our_ap, feat_carplay, cp_conn)" 'grep -qx "our_ap=yes" $STF && grep -q "^feat_carplay=" $STF && grep -qx "cp_conn=1" $STF' 
check "USB에 리포트 저장" '[ -s $R ]'
check "리포트에 SSID·비밀번호·폰 IP 없음" '! grep -q -e "SSID.cX" -e "PASS" -e HotspotName -e 192.168.43.23 $R'
check "우리 hostapd 인식" 'grep -q "우리 hostapd: 예" $R'
check "wifi.direct를 wifi로 착각하지 않음" 'grep -q "android.hardware.wifi: 아니요" $R'
check "토스트 한국어" 'grep -q "핫스폿 켜짐" $T/toast'

# --- 3. kp-test.sh: 단계별 경로 ---
fixpath $B/scripts/kp-test.sh > $T/kp.sh
run() { U=$T/usb0 D=$T/d APPS=$T/apps PERMS=$T/perms BB=$T/bin/bb sh $T/kp.sh >/dev/null 2>&1; cat $T/d/step 2>/dev/null || echo none; }
reset() { rm -rf $T/d/* $T/usb0/kp $T/calls $T/feat $T/install_ok $T/wp_stuck $T/force_ok $T/wp_reinstall_fails $T/perms $T/apps/*; mkdir -p $T/apps/wireless.projection $T/perms; }
reset
check "되돌리기 zip이 없으면 시작 안 함" '[ "$(run)" = none ] && ! grep -q uninstall $T/calls 2>/dev/null'
for z in wireless.projection.zip packages/korea.projection.zip packages/niro.carplay.hotspot.zip; do echo x > $T/usb0/$z; done
reset
check "새 패키지 설치 실패 → 중단" '[ "$(run)" = none ]'
check "  예전 패키지 재설치, wireless.projection 유지" 'grep -q "install $T/usb0/packages/niro.carplay.hotspot.zip" $T/calls && ! grep -q "uninstall wireless.projection" $T/calls'
reset; touch $T/install_ok $T/wp_stuck
check "wireless.projection 삭제 실패 → C로 중단" '[ "$(run)" = C ]'
reset; touch $T/install_ok
check "정상: A" '[ "$(run)" = A ]'
check "  기능 없음 → 권한 파일 2개를 md5 맞춰 쓰고 apply, B2" '[ "$(run)" = B2 ] && [ "$(md5sum < $T/perms/com.hkmc.software.connectivity.carplay_wireless.xml | cut -c1-32)" = 95ff801a064526de56059dba10960b05 ] && [ "$(md5sum < $T/perms/com.hkmc.software.connectivity.androidauto_wireless.xml | cut -c1-32)" = fa91812d3eeee415768018ab6ee6804a ] && ! grep -q -- --force $T/calls'
check "  재시작 뒤에도 없음 → 되돌리기 (파일 쓰기 다시 안 함)" '[ "$(run)" = B-rollback ] && grep -q "install $T/usb0/wireless.projection.zip" $T/calls'
reset; mkdir -p $T/perms; touch $T/install_ok
run >/dev/null; run >/dev/null; touch $T/feat
check "  재시작 뒤 기능 생김 → C" '[ "$(run)" = C ]'
reset; mkdir -p $T/perms; touch $T/install_ok; echo B1 > $T/d/step
check "지금 차 상태(B1)에서 다음 꽂기 → 파일 되돌리기(B2)" '[ "$(run)" = B2 ]'
reset; mkdir -p $T/perms; touch $T/install_ok $T/wp_reinstall_fails; echo B2 > $T/d/step; : > $T/d/fixed; rmdir $T/apps/wireless.projection
check "되돌리기 재설치 실패 → rollback-retry" '[ "$(run)" = rollback-retry ] && grep -q "재설치에 실패" $T/toast'
rm -f $T/wp_reinstall_fails
check "  다음 꽂기에 다시 설치 → B-rollback" '[ "$(run)" = B-rollback ]'
reset; mkdir -p $T/perms; touch $T/install_ok; : > $T/d/fixed
check "새로 시작하면 예전 표시 파일 지움" '[ "$(run)" = A ] && [ ! -f $T/d/fixed ]'
touch $T/feat
check "정상: 기능 있음 → C" '[ "$(run)" = C ]'
reset; touch $T/install_ok; echo B-rollback > $T/d/step; rmdir $T/apps/wireless.projection
check "되돌리기 중 재시작돼 둘 다 없음 → 다시 설치" '[ "$(run)" = B-rollback ] && grep -q "install $T/usb0/wireless.projection.zip" $T/calls'
reset; touch $T/install_ok; echo B-rollback > $T/d/step
check "되돌리기 끝난 뒤 꽂기 → 로그 수집(C)" '[ "$(run)" = C ] && ls $T/usb0/kp/C-*.txt >/dev/null 2>&1'
touch $T/usb0/kp-rollback
check "kp-rollback 파일 → 되돌리기" '[ "$(run)" = B-rollback ]'

# --- 4. kp-update-test.sh: 업데이트 → 삭제 확인 → 다시 설치 ---
X=$T/up; mkdir -p $X/bin $X/usb/packages $X/d $X/apps $X/perms $X/wd $X/bk
echo zip > $X/usb/packages/korea.projection.zip; echo prev > $X/usb/packages/korea.projection-prev.zip
touch $X/perms/com.hkmc.software.connectivity.carplay_wireless.xml $X/perms/com.hkmc.software.connectivity.androidauto_wireless.xml
echo 1.1 > $X/ver; echo 1 > $X/wifi
cat > $X/bin/nemesis <<E
#!/bin/sh
echo "nemesis \$*" >> $X/calls
case "\$1" in
  pkg-list) echo "usb-handler|USB Handler|1|service|1.16.7|x"; [ -f $X/ver ] && echo "korea.projection|Korea Projection|0|service,application|\$(cat $X/ver)|x" ;;
  install) case "\$*" in *prev.zip) echo 1.3 > $X/ver; mkdir -p $X/apps/korea.projection $X/wd $X/bk; touch $X/conf; echo up > $X/ap; exit 0 ;; esac
    # 실제 NEMESIS처럼: 업데이트는 예전 것을 먼저 지우므로, 실패하면 아무것도 남지 않는다
    [ -f $X/inst_fail ] && { [ "\$2" = --update ] && rm -f $X/ver $X/ap; exit 1; }; [ "\$2" = --update ] && [ ! -f $X/ver ] && exit 1; echo 1.4.1 > $X/ver; mkdir -p $X/bk; [ -f $X/bk/wifi_on ] || cat $X/wifi > $X/bk/wifi_on; mkdir -p $X/apps/korea.projection $X/wd $X/bk; touch $X/conf; echo up > $X/ap ;;
  uninstall) rm -f $X/ver; rm -rf $X/apps/korea.projection $X/bk; [ -f $X/leave_wd ] || rm -rf $X/wd; rm -f $X/conf $X/ap ;;
esac
exit 0
E
cat > $X/bin/ps <<E
#!/bin/sh
[ -f $X/ap ] && { echo "  1 1010 hostapd $X/conf"; echo "  2 9999 dnsmasq --keep-in-foreground --no-resolv"; }
echo "  3 1010 wpa_supplicant"
E
printf '#!/bin/sh\ncat %s/wifi\n' $X > $X/bin/settings
for c in hmgapid getprop; do printf '#!/bin/sh\nexit 0\n' > $X/bin/$c; done
cat > $X/bin/pm <<E
#!/bin/sh
case "\$1" in
  list) echo feature:com.hkmc.software.connectivity.carplay_wireless ;;
  path) [ -f $X/ver ] && echo package:/data/app/korea.projection.app-1.apk || exit 1 ;;
esac
E
printf '#!/bin/sh\necho "wlan0 Link encap:Ethernet HWaddr 00:11:22:33:44:55"\necho "  inet addr:192.168.43.1"\n' > $X/bin/ifconfig
printf '#!/bin/sh\necho "$*" > %s/toast\n' $X > $X/bin/am
printf '#!/bin/sh\n/bin/sleep 0.01\n' > $X/bin/sleep
chmod +x $X/bin/*
sed "s#^export PATH=.*#export PATH=$X/bin:/usr/bin:/bin:/sbin#" $B/scripts/kp-update-test.sh > $X/kp2.sh
echo "/dev/block/sda1 $X/usb vfat rw 0 0" > $X/mounts
urun() { (cd $X && MOUNTS=$X/mounts U=$X/usb D=$X/d APPS=$X/apps PERMS=$X/perms CONF=$X/conf WD=$X/wd BK=$X/bk BB=$T/bin/bb timeout 60 sh $X/kp2.sh >/dev/null 2>&1); cat $X/d/step 2>/dev/null || echo none; }
check "업데이트: 1.4.1 설치되고 핫스폿 켜짐 → R" '[ "$(urun)" = R ] && grep -q "install --update" $X/calls'
check "  삭제 직후 확인 7개 통과 → R2 (재시작 안내)" '[ "$(urun)" = R2 ] && [ "$(grep -c "^통과" $X/usb/kp5/R.txt)" = 7 ] && grep -q "껐다 켠 뒤" $X/toast'
check "  재시작 뒤 확인 + 다시 설치 모두 통과 → DONE" '[ "$(urun)" = DONE ] && ! grep -q "^실패" $X/usb/kp5/R.txt && [ "$(grep -c "^통과" $X/usb/kp5/R.txt)" = 15 ] && grep -q "모두 통과" $X/toast'
check "  다시 설치는 헤드유닛에 복사한 zip으로" 'grep -q "^nemesis install $X/d/pkg.zip" $X/calls'
check "  그다음 꽂기: 로그 수집, MAC 안 남김" '[ "$(urun)" = DONE ] && ls $X/usb/kp5/C-*.txt >/dev/null 2>&1 && ! grep -q HWaddr $X/usb/kp5/C-*.txt'
echo R > $X/d/step; touch $X/leave_wd
check "삭제 뒤 작업 폴더가 남으면 실패로 잡음" '[ "$(urun)" = R2 ] && grep -q "^실패 작업 폴더" $X/usb/kp5/R.txt'
check "  끝에 실패 수를 알림" '[ "$(urun)" = DONE ] && grep -q "실패 1건" $X/toast'
rm -f $X/leave_wd
echo R > $X/d/step; mkdir -p $X/bk; echo 1 > $X/bk/wifi_on; echo 0 > $X/wifi
urun >/dev/null
check "Wi-Fi 비교는 설치 전 값(\$BK/wifi_on)과 한다" '[ "$(urun)" = DONE ] && grep -q "^실패 Wi-Fi 설정이 설치 전과 같음 (1)" $X/usb/kp5/R.txt'
echo 1 > $X/wifi
echo R > $X/d/step; urun >/dev/null; touch $X/inst_fail
check "다시 설치 실패 → DONE이라 하지 않고 REINSTALL" '[ "$(urun)" = REINSTALL ] && grep -q "확인되지 않았습니다" $X/toast'
rm -f $X/inst_fail
check "  다음 꽂기에 다시 설치 → DONE" '[ "$(urun)" = DONE ] && grep -q "다시 설치했습니다" $X/toast'
rm -f $X/d/step $X/ver $X/calls
check "업데이트가 비어 있으면(예전 것만 지워짐) 일반 설치로 메꿈 → R" '[ "$(urun)" = R ] && grep -q "^nemesis install $X/usb/packages/korea.projection.zip" $X/calls'
rm -f $X/d/step $X/calls; echo 1.3 > $X/ver; touch $X/inst_fail
check "새 버전 설치가 모두 실패하면 이전 버전으로 되돌리고 알림" '[ "$(urun)" = none ] && grep -q "install $X/usb/packages/korea.projection-prev.zip" $X/calls && grep -q "이전 버전(1.3)으로 되돌렸습니다" $X/toast && [ -f $X/ap ]'
rm -f $X/inst_fail
rm -f $X/d/step $X/calls; echo 1.4 > $X/ver; touch $X/usb/kp-only-update
check "kp-only-update: 업데이트만 하고 DONE (삭제 안 함)" '[ "$(urun)" = DONE ] && ! grep -q "uninstall" $X/calls && grep -q "Launch를 눌러" $X/toast'
rm -f $X/usb/kp-only-update
rm -f $X/d/step; echo 1.1 > $X/ver; rm -f $X/usb/packages/korea.projection.zip
check "USB에 zip이 없으면 시작 안 함" '[ "$(urun)" = none ] && grep -q "시작하지 않았습니다" $X/toast'

echo "---"
[ $fails -eq 0 ] && echo "모두 통과" || { echo "실패 $fails개"; exit 1; }
