#!/bin/bash
set -e
B=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap '/bin/rm -rf "$T"' EXIT
BK=$T; W=$T; BB=/bin/true
. "$B/nemesis-pkg/korea.projection/svc/ig-wifi-recovery.sh"
igr_pause() { /bin/sleep 0.01; }
if igr_run /bin/true; then :; else exit 1; fi
[ -z "$IGR_JOB" ]
if igr_run /bin/false; then exit 1; else [ "$?" = 1 ]; fi
if igr_run /bin/sleep 5; then exit 1; else [ "$?" = 124 ]; fi
[ -z "$IGR_JOB" ]
echo 'PASS command success, failure status, bounded timeout and PID cleanup'
