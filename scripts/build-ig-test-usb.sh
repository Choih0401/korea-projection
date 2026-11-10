#!/bin/bash
# Assemble an IG-specific package over the verified official release assets.
set -euo pipefail
B=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: build-ig-test-usb.sh /outside/repo/output}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
case "$OUT" in "$B"|"$B"/*) echo 'Use output outside the checkout' >&2; exit 1;; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
if [ -n "${KP_RELEASE_USB:-}" ]; then
  cp "$KP_RELEASE_USB" "$W/base.zip"
else
  curl -fsSL --max-time 120 https://github.com/StopDragon/korea-projection/releases/download/v1.7.2/korea-projection-1.7.2-usb.zip -o "$W/base.zip"
fi
printf '%s  %s\n' 628d274f0e7f862e01cf31cc28085d9f2ad6a583c3d8eee60f17b935dedfd666 "$W/base.zip" | sha256sum -c -
unzip -p "$W/base.zip" packages/korea.projection.zip > "$W/base-package.zip"
mkdir "$W/package"
unzip -q "$W/base-package.zip" -d "$W/package"
cp -a "$B/nemesis-pkg/korea.projection/." "$W/package/"
chmod 755 "$W/package/bin/busybox" "$W/package/svc/ig-wifi-recovery.sh"
bash "$B/tests/ig-wifi-recovery-test.sh"
bash "$B/tests/ig-wifi-command-timeout-test.sh"
if command -v mksh >/dev/null 2>&1; then
  IG_TEST_SHELL=$(command -v mksh) bash "$B/tests/ig-wifi-recovery-test.sh"
  for f in svc/ig-wifi-recovery.sh svc/hotspot.sh scripts/post.sh scripts/preun.sh bin/status.sh; do
    mksh -n "$W/package/$f"
  done
fi
(cd "$W/package" && zip -q -X -r "$W/korea.projection.zip" .)
sh "$B/scripts/build-usb.sh" "$W/korea.projection.zip" "$W"
mkdir "$W/usb"
unzip -q "$W/korea-projection-1.7.2.2-usb.zip" -d "$W/usb"
cp "$B/docs/ig-wifi-usb-readme.txt" "$W/usb/README.txt"
cp "$B/docs/ig-wifi-recovery.md" "$W/usb/IG-WIFI-GUIDE.md"
mkdir "$W/usb/recovery-controls"
for control in off on reset; do : > "$W/usb/recovery-controls/kp-ig-wifi-$control"; done
Z="$OUT/korea-projection-1.7.2.2-usb.zip"
rm -f "$Z"
(cd "$W/usb" && zip -q -X -r "$Z" .)
python3 "$B/tests/verify-ig-usb.py" "$Z"
unzip -t "$Z"
cp "$W/base.zip" "$OUT/korea-projection-1.7.2-original-usb.zip"
(cd "$OUT" && sha256sum korea-projection-1.7.2.2-usb.zip korea-projection-1.7.2-original-usb.zip > SHA256SUMS)
echo "Built $Z"
