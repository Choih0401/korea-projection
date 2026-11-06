#!/bin/sh
# 사용자용 "USB에 그대로 복사" 묶음을 만든다.
# 결과 zip을 풀면 NEMESIS.data, packages/korea.projection.zip, README.txt가 나온다.
# 사용자가 NEMESIS.data를 직접 만들다가 틀리는 일(확장자 .txt, 오타, 폴더 위치)을 없애려는 것이다.
# 사용: sh scripts/build-usb.sh [패키지 zip] [출력 폴더]
#   기본값: nemesis-pkg/korea.projection.zip, 현재 폴더
set -e
umask 022
B=$(cd "$(dirname "$0")/.." && pwd)
PKG=${1:-$B/nemesis-pkg/korea.projection.zip}
OUT=${2:-.}

[ -f "$PKG" ] || { echo "패키지 zip이 없습니다: $PKG" >&2; exit 1; }
OUT=$(cd "$OUT" && pwd)

# 패키지 안의 NEMESIS.data에서 버전을 읽는다(숫자와 점만 허용)
VER=$(unzip -p "$PKG" NEMESIS.data | grep '^package-version=' | sed 's/^package-version=//; s/\r$//')
case "$VER" in
  ''|*[!0-9.]*) echo "package-version을 읽지 못했습니다: '$VER'" >&2; exit 1 ;;
esac
# 패키지 zip이 정말 korea.projection인지 확인
unzip -p "$PKG" NEMESIS.data | grep -q '^id=korea.projection$' || { echo "korea.projection 패키지가 아닙니다" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/packages"
cp "$PKG" "$W/packages/korea.projection.zip"

# USB 맨 위에 둘 설치 지시 파일(NEMESIS USB Handler는 이 파일만 읽는다)
printf '[nemesis]\ntype=install\npath=packages/korea.projection.zip\n' > "$W/NEMESIS.data"

# 파일 이름은 영어로 둔다: 한글 파일 이름은 Windows 압축 풀기에서 깨질 수 있다
cat > "$W/README.txt" <<EOF
Korea Projection $VER - USB 설치 파일

1. USB를 FAT32로 포맷합니다(32GB 이하 USB 권장).
2. 이 폴더 "안에 있는 것"을 USB 맨 위에 그대로 복사합니다.
     USB
     ├─ NEMESIS.data
     ├─ README.txt
     └─ packages
         └─ korea.projection.zip   ← 이 파일은 압축을 풀지 마세요
   폴더째로 넣으면 안 됩니다. USB를 열었을 때 NEMESIS.data가 바로 보여야 합니다.
3. 시동을 켜고 내비 화면이 다 뜬 뒤 USB를 꽂습니다.
4. 설치할지 물으면 60초 안에 "예"를 누릅니다.
5. 설치가 끝나면 USB를 빼고 기다립니다. "설정을 마쳤습니다"가 뜨면 내비를 재부팅합니다.
   시동만 끄면 내비가 꺼지지 않을 수 있습니다. 내비 본체의 RESET 버튼(작은 구멍)을 클립으로 누르거나,
   NEMESIS Manager에서 재부팅을 누르세요.

자세한 설명:
https://github.com/StopDragon/korea-projection/blob/main/docs/install-guide.md
EOF

Z="$OUT/korea-projection-$VER-usb.zip"
rm -f "$Z"
# -X: macOS 확장 속성(._ 파일 등)을 넣지 않는다
(cd "$W" && zip -X -q "$Z" NEMESIS.data README.txt packages/korea.projection.zip)

echo "만듦: $Z"
shasum -a 256 "$Z"
