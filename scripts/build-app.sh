#!/bin/sh
# Korea Projection 상태 화면 앱(APK)을 만든다 → nemesis-pkg/korea.projection/app/KoreaProjection.apk
# 필요한 것: JDK, Android SDK build-tools(aapt2, d8, zipalign, apksigner)와 android-19 플랫폼.
#   SDK=~/.local/share/android-sdk (기본값), 그 아래 build-tools/<버전>/, platforms/<이름>/android.jar
# 서명 키: ~/.local/share/korea-projection/keys/ (저장소 밖, 공개하지 않는다). 없으면 처음에 만든다.
#   업데이트하려면 같은 키로 서명해야 하므로 이 폴더는 따로 백업한다.
set -e
B=$(cd "$(dirname "$0")/.." && pwd)
SRC=$B/nemesis-pkg/app-src
OUTAPK=$B/nemesis-pkg/korea.projection/app/KoreaProjection.apk
SDK=${SDK:-$HOME/.local/share/android-sdk}
# 가장 높은 버전 (이름순이면 9.0.0이 34.0.0보다 뒤에 온다)
BT=$(ls -d "$SDK"/build-tools/*/ | sort -t/ -k1 -V | tail -n 1)
JAR=$(ls "$SDK"/platforms/*/android.jar | head -n 1)
KEYS=${KEYS:-$HOME/.local/share/korea-projection/keys}
W=$(mktemp -d /tmp/kp-app.XXXXXX)
trap 'rm -rf "$W"' EXIT

if [ ! -f "$KEYS/release.keystore" ]; then
  mkdir -p "$KEYS"; chmod 700 "$KEYS"
  # 비밀번호는 무작위로 만들어 키 폴더에만 둔다 (화면·문서·저장소에 남기지 않는다)
  head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$KEYS/pass"; chmod 600 "$KEYS/pass"
  keytool -genkeypair -keystore "$KEYS/release.keystore" -storepass:file "$KEYS/pass" -keypass:file "$KEYS/pass" \
    -alias kp -keyalg RSA -keysize 3072 -validity 10000 -dname "CN=Korea Projection" >/dev/null 2>&1
  chmod 600 "$KEYS/release.keystore"
  echo "새 서명 키를 만들었습니다: $KEYS (백업하세요)"
fi

"$BT/aapt2" compile --dir "$SRC/res" -o "$W/res.zip"
"$BT/aapt2" link -I "$JAR" --manifest "$SRC/AndroidManifest.xml" --min-sdk-version 19 --target-sdk-version 19 \
  -o "$W/base.apk" "$W/res.zip"
mkdir -p "$W/classes"
javac --release 8 -Xlint:-options -nowarn -encoding UTF-8 -cp "$JAR" -d "$W/classes" $(find "$SRC/java" -name '*.java')
"$BT/d8" --release --min-api 19 --lib "$JAR" --output "$W" $(find "$W/classes" -name '*.class')
(cd "$W" && cp base.apk unsigned.apk && zip -q -X unsigned.apk classes.dex)
"$BT/zipalign" -f -p 4 "$W/unsigned.apk" "$W/aligned.apk"
mkdir -p "$(dirname "$OUTAPK")"
"$BT/apksigner" sign --ks "$KEYS/release.keystore" --ks-pass file:"$KEYS/pass" --ks-key-alias kp \
  --v1-signing-enabled true --v2-signing-enabled true --v4-signing-enabled false --min-sdk-version 19 \
  --out "$OUTAPK" "$W/aligned.apk"
rm -f "$OUTAPK.idsig"
"$BT/apksigner" verify --min-sdk-version 19 "$OUTAPK"
echo "만듦: $OUTAPK ($(wc -c < "$OUTAPK" | tr -d ' ') 바이트)"
