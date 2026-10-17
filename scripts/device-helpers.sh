#!/usr/bin/env bash
# device-helpers.sh - Stage E: the adb + scrcpy screenshot/act loop, as reusable subcommands.
#
# Drives or reads a live device. On your OWN device and account (RE, modding) this is fine, no
# authorization record needed (see references/00-authorization.md, category "local"). It only
# becomes gated "assessment" work if you use it to reach past your own instance (probing a backend
# or another account). Never touch accounts or data that are not yours or not in authorized scope.
#
# Usage:
#   device-helpers.sh shot [out.png]                 # screenshot to a local file
#   device-helpers.sh uidump [ui.xml]                # dump the current UI tree to a local file
#   device-helpers.sh tap-text "<text>" [ui.xml]     # find a node by text/content-desc and tap its center
#   device-helpers.sh logcat-pkg <pkg>               # stream logcat filtered to the app's pid(s)
#   device-helpers.sh applog <pkg> <relpath>         # cat an app-private file (needs root/run-as)
#   device-helpers.sh mirror                          # launch scrcpy (mirror + control)
#
# WINDOWS / GIT-BASH: export MSYS_NO_PATHCONV=1 before using any subcommand that passes a device
# path like /sdcard/..., or Git-Bash rewrites it into a Windows path and the command fails.
#   export MSYS_NO_PATHCONV=1
#
# adb recovery: if 'adb devices' shows "unauthorized" or "offline", re-accept the prompt on the
# phone, then:  adb kill-server && adb start-server && adb devices
#
# App-private files (/data/data/<pkg>/...) need either root (su) or a debuggable app (run-as).
# This script tries su first, then run-as, and says so if neither works.
#
# Manual equivalents are given inline per subcommand.
#
# Requires: adb. 'mirror' needs scrcpy. 'tap-text' needs python3 for bounds math.

set -u
ADB="${ADB:-adb}"
cmd="${1:-}"; shift || true

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need_device() {
  command -v "$ADB" >/dev/null 2>&1 || die "adb not found"
  local state
  state=$("$ADB" get-state 2>/dev/null | tr -d '\r')
  [ "$state" = "device" ] || die "no authorized device (adb devices says '${state:-none}'). If 'unauthorized'/'offline': re-accept on phone, then adb kill-server && adb start-server"
}

case "$cmd" in
  shot)
    # manual: adb exec-out screencap -p > out.png
    need_device
    out="${1:-shot-$(date +%H%M%S).png}"
    "$ADB" exec-out screencap -p > "$out" 2>/dev/null && echo "$out" || die "screencap failed"
    ;;

  uidump)
    # manual: adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml ui.xml
    need_device
    out="${1:-ui.xml}"
    export MSYS_NO_PATHCONV=1
    "$ADB" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 \
      || die "uiautomator dump failed (a fullscreen video or secure screen can block it)"
    "$ADB" pull /sdcard/ui.xml "$out" >/dev/null 2>&1 && echo "$out" || die "pull ui.xml failed"
    ;;

  tap-text)
    # manual: read ui.xml, find text="..."/content-desc="..." bounds="[x1,y1][x2,y2]", tap center:
    #   adb shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 ))
    need_device
    want="${1:-}"; ui="${2:-ui.xml}"
    [ -n "$want" ] || die "usage: tap-text \"<text>\" [ui.xml]"
    export MSYS_NO_PATHCONV=1
    if [ ! -f "$ui" ]; then
      "$ADB" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
      "$ADB" pull /sdcard/ui.xml "$ui" >/dev/null 2>&1 || die "could not get ui.xml"
    fi
    command -v python3 >/dev/null 2>&1 || die "python3 needed for bounds math"
    coords=$(python3 - "$ui" "$want" <<'PY'
import re, sys
ui, want = sys.argv[1], sys.argv[2]
data = open(ui, encoding='utf-8', errors='replace').read()
# match a node whose text or content-desc equals or contains `want`, grab its bounds
best = None
for m in re.finditer(r'<node[^>]*>', data):
    tag = m.group(0)
    t = re.search(r'text="([^"]*)"', tag)
    d = re.search(r'content-desc="([^"]*)"', tag)
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
    if not b:
        continue
    label = (t.group(1) if t else '') + '\x00' + (d.group(1) if d else '')
    if want == (t.group(1) if t else '') or want == (d.group(1) if d else ''):
        best = b; break
    if best is None and want in label:
        best = b
if not best:
    sys.exit(1)
x1, y1, x2, y2 = map(int, best.groups())
print((x1 + x2) // 2, (y1 + y2) // 2)
PY
) || die "no node matching '$want' in $ui (dump again; the screen may have changed)"
    set -- $coords
    "$ADB" shell input tap "$1" "$2" && echo "tapped '$want' at $1 $2"
    ;;

  logcat-pkg)
    # manual: pid=$(adb shell pidof <pkg>); adb logcat --pid=$pid
    need_device
    pkg="${1:-}"; [ -n "$pkg" ] || die "usage: logcat-pkg <pkg>"
    pid=$("$ADB" shell pidof "$pkg" 2>/dev/null | tr -d '\r' | awk '{print $1}')
    [ -n "$pid" ] || die "'$pkg' not running (launch it first: adb shell monkey -p $pkg 1)"
    echo "streaming logcat for $pkg (pid $pid); Ctrl-C to stop" >&2
    "$ADB" logcat --pid="$pid"
    ;;

  applog)
    # manual (root):   adb shell su -c 'cat /data/data/<pkg>/<relpath>'
    #        (debug):  adb shell run-as <pkg> cat <relpath>
    need_device
    pkg="${1:-}"; rel="${2:-}"
    [ -n "$pkg" ] && [ -n "$rel" ] || die "usage: applog <pkg> <relpath under /data/data/<pkg>/>"
    export MSYS_NO_PATHCONV=1
    full="/data/data/$pkg/$rel"
    if "$ADB" shell su -c "cat $full" 2>/dev/null; then
      :
    elif "$ADB" shell run-as "$pkg" cat "$rel" 2>/dev/null; then
      :
    else
      die "could not read $full (need root 'su' or a debuggable app for 'run-as $pkg')"
    fi
    ;;

  mirror)
    # manual: scrcpy --stay-awake
    command -v scrcpy >/dev/null 2>&1 || die "scrcpy not found (install it to mirror + control the screen)"
    need_device
    exec scrcpy --stay-awake "$@"
    ;;

  *)
    sed -n '2,40p' "$0"   # print the header/usage
    exit 2
    ;;
esac
