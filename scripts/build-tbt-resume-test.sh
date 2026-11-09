#!/bin/bash
# Rebuild the K3 BD PE warm-resume test mod without modifying the production bundle.
# Usage: bash scripts/build-tbt-resume-test.sh /outside/repo/author.key /outside/repo/output
set -euo pipefail
B=$(cd "$(dirname "$0")/.." && pwd)
KEY=$(realpath "${1:?provide an existing HMG-API author key outside the repository}")
OUT=${2:?provide an output directory outside the repository}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
case "$KEY" in "$B"/*) echo 'Keep signing keys outside the repository' >&2; exit 1;; esac
case "$OUT" in "$B"|"$B"/*) echo 'Keep build outputs outside the repository' >&2; exit 1;; esac
SDK=${ANDROID_HOME:?set ANDROID_HOME to an Android SDK with build-tools and a platform}
BT=$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)
JAR=$(find "$SDK/platforms" -name android.jar | sort -V | head -1)
[ -x "$BT/d8" ] && [ -s "$JAR" ]
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
BASE=b02a1417c485ca8545293dc2b9230f1d3e0c11ec
curl -fsSL --max-time 120 "https://codeload.github.com/StopDragon/HMG-API/tar.gz/$BASE" -o "$W/source.tar.gz"
printf '%s  %s\n' 0ed471801551befafa23fee68e1bf8994ac2093c2cb1f0123e3f4c023996d969 "$W/source.tar.gz" | sha256sum -c -
mkdir "$W/source"
tar -xzf "$W/source.tar.gz" -C "$W/source" --strip-components=1
cd "$W/source"
git apply --check "$B/hmgapi-mod/patches/0001-carplay-guidance-resume.patch"
git apply "$B/hmgapi-mod/patches/0001-carplay-guidance-resume.patch"
# Preserve the selected repository's Korean model/patch declarations.
cp -a "$B/hmgapi-mod/wireless-carplay-aa/." mods/wireless-carplay-aa/
M=$W/source/mods/wireless-carplay-aa
python3 - "$M/mod.json" <<'PY'
import json,sys
p=sys.argv[1]
with open(p) as f: m=json.load(f)
m['version']='2.4.1-k3-test.1'
m['name']='Wireless CarPlay and Android Auto (K3 TBT resume test)'
m['description']='K3 BD PE warm-resume TBT cleanup test; locally signed, not an official release.'
with open(p,'w') as f: json.dump(m,f,ensure_ascii=False,indent=2); f.write('\n')
PY
sh "$B/tests/tbt-resume/run.sh" "$W/source" > "$OUT/tbt-resume-tests.log" 2>&1
mkdir -p out/runtime-stubs out/classes out/mod-stubs/wireless-carplay-aa out/mod-classes/wireless-carplay-aa
javac --release 8 -Xlint:-options -nowarn -cp "$JAR" -d out/runtime-stubs $(find core/runtime/stubs -name '*.java')
javac --release 8 -Xlint:-options -nowarn -cp "$JAR:out/runtime-stubs" -d out/classes $(find core/runtime/java -name '*.java')
javac --release 8 -Xlint:-options -nowarn -cp "$JAR" -d out/mod-stubs/wireless-carplay-aa $(find "$M/stubs" -name '*.java')
javac --release 8 -Xlint:-options -nowarn -cp "$JAR:out/classes:out/mod-stubs/wireless-carplay-aa" \
  -d out/mod-classes/wireless-carplay-aa $(find "$M/src" -name '*.java')
mkdir "$W/package"
# Reuse unchanged deployment assets from the repository's already bundled mod.
unzip -q "$B/nemesis-pkg/korea.projection/hmgapi/wireless-carplay-aa.zip" -d "$W/package"
rm -rf "$W/package/META-HMGAPI"
cp "$M/mod.json" "$W/package/mod.json"
"$BT/d8" --release --min-api 19 --lib "$JAR" --classpath out/classes \
  --classpath out/mod-stubs/wireless-carplay-aa --output "$W/package/hooks.jar" \
  $(find out/mod-classes/wireless-carplay-aa -name '*.class')
java -cp out/classes hmgapi.engine.Signing sign "$W/package" "$KEY"
java -cp out/classes hmgapi.engine.Signing verify "$W/package"
Z="$OUT/wireless-carplay-aa-2.4.1-k3-test.1.zip"
rm -f "$Z"
(cd "$W/package" && find . -type f | sort | TZ=UTC xargs touch -d 2026-01-01T00:00:00 && find . -type f | sort | zip -q -X -D "$Z" -@)
unzip -t "$Z"
sha256sum "$Z" "$W/package/hooks.jar" | sed "s|$W/package/hooks.jar|hooks.jar|" > "$OUT/SHA256SUMS"
cp "$B/nemesis-pkg/korea.projection/hmgapi/wireless-carplay-aa.zip" "$OUT/wireless-carplay-aa-2.4.0-original.zip"
cat "$OUT/SHA256SUMS"
echo "Built $Z (development signature; remove the previous mod before installing)"
