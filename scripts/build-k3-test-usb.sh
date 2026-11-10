#!/bin/bash
# Build a complete NEMESIS USB bundle, retaining the release APK/signature and ARM BusyBox.
set -euo pipefail
B=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: build-k3-test-usb.sh /outside/repo/output}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
case "$OUT" in "$B"|"$B"/*) echo 'Use an output directory outside the checkout' >&2; exit 1;; esac
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
chmod 755 "$W/package/bin/busybox"
printf '%s  %s\n' 3d31efecd4d09625a5d04597ad857f3475d35e6d63a3365912a7edd4c60770a5 "$W/package/bin/busybox" | sha256sum -c -
printf '%s  %s\n' 661ffcf49889f45e7f84dc8c667b45e7af9858634d4b33232c651e77528989cd "$W/package/app/KoreaProjection.apk" | sha256sum -c -
# The release app is retained byte for byte; no development APK/key replaces it.
bash "$B/tests/tbt-resume/auto-install.sh" "$W/package"
(cd "$W/package" && zip -X -q -r "$W/korea.projection.zip" .)
sh "$B/scripts/build-usb.sh" "$W/korea.projection.zip" "$W"
mkdir "$W/usb"
unzip -q "$W/korea-projection-1.7.2.1-usb.zip" -d "$W/usb"
cp "$B/docs/k3-test-usb-readme.txt" "$W/usb/README.txt"
cp "$B/docs/k3-bdpe-tbt-resume-test.md" "$W/usb/TEST-GUIDE.md"
Z="$OUT/korea-projection-1.7.2.1-usb.zip"
rm -f "$Z"
(cd "$W/usb" && zip -q -X -r "$Z" .)
python3 "$B/tests/tbt-resume/verify-usb.py" "$Z"
unzip -t "$Z"
sha256sum "$Z" > "$OUT/korea-projection-1.7.2.1-usb.sha256"
# Preserve the complete original USB bundle for rollback using the same NEMESIS workflow.
cp "$W/base.zip" "$OUT/korea-projection-1.7.2-original-usb.zip"
echo "Built $Z"
