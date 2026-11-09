#!/bin/sh
# Run after applying hmgapi-mod/patches/0001-carplay-guidance-resume.patch.
set -eu
HMG=${1:?usage: run.sh /path/to/HMG-API}
B=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
M=$HMG/mods/wireless-carplay-aa
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
javac --release 8 -Xlint:-options -nowarn -d "$W" \
  $(find "$M/tools/cpturns/stubs" "$M/tools/cpturns/test" "$M/tools/aaturns/stubs" -name '*.java') \
  "$M/stubs/com/tcc/iap2/Iap2NotiMsg.java" \
  "$M/src/hmgapi/mods/wireless/dipo/CpTurns.java" \
  "$M/src/hmgapi/mods/wireless/dipo/PhoneBarOut.java" \
  "$M/src/hmgapi/mods/wireless/dipo/GuidanceSession.java" \
  "$M/src/hmgapi/mods/wireless/PhoneBar.java" \
  "$M/src/hmgapi/mods/wireless/GuidanceGate.java" "$M/src/hmgapi/mods/wireless/StockReplay.java" "$B/GuidanceSessionTest.java" "$B/WarmResumeTest.java" "$B/StockReplayResumeTest.java"
java -cp "$W" hmgapi.mods.wireless.dipo.CpTurnsTest
java -cp "$W" hmgapi.mods.wireless.dipo.GuidanceSessionTest
java -cp "$W" hmgapi.mods.wireless.dipo.WarmResumeTest
java -cp "$W" hmgapi.mods.wireless.StockReplayResumeTest
# Existing AA, stock replay, bar and masking regressions share the navigation code.
sh "$M/tools/aaturns/test.sh"
