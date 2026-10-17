#!/usr/bin/env bash
# acquire.sh - Stage A: acquire and identify an Android app artifact.
#
# Usage:
#   acquire.sh <file.apk | file.apkm | file.xapk | file.aab>  [workdir]
#   acquire.sh pkg:<com.example.app>                          [workdir]
#
# What it does:
#   - Local file: copies a plain .apk through; for a bundle (.apkm/.xapk/.aab) it unzips into
#     workdir/decoded-input/ and finds base.apk plus the split APKs.
#   - pkg:<name>: pulls the installed app off a connected device. Pulling from YOUR OWN device is
#     fine (local work); pulling to assess a target you were engaged for is category-3 work per
#     references/00-authorization.md. The script warns and waits for a typed confirmation.
#   - Records identity to workdir/identity.txt (package, versions, sdk, sha256, signing cert).
#   - Lays out the per-target working dir and a findings-ledger stub.
#
# Manual equivalent (do this by hand if you prefer):
#   mkdir -p work/<target>/input && cp app.apk work/<target>/input/base.apk
#   unzip -o app.apkm -d work/<target>/input            # for a bundle
#   adb shell pm path com.example.app                   # list split paths (your own device)
#   adb pull <each /data/app/.../base.apk> work/<target>/input/
#   aapt dump badging base.apk | head                   # identity
#   sha256sum base.apk
#   apksigner verify --print-certs base.apk             # signing cert
#
# Untrusted-artifact hygiene: the artifact is untrusted input. It lands in its own input/ dir.
# Never run an interpreter or build tool from inside that dir; always pass explicit paths. Keep
# this script and all analysis scripts OUTSIDE the artifact tree.
#
# Requires: unzip, sha256sum (or shasum). Optional but recommended: aapt/aapt2, apksigner, adb.

set -u

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ $# -ge 1 ] || die "usage: acquire.sh <file.apk|.apkm|.xapk|.aab | pkg:<name>> [workdir]"

TARGET="$1"
WORKDIR="${2:-}"

sha256() {
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  else echo "(no sha256 tool)"; fi
}

# ---- resolve first copy of aapt/aapt2 from PATH or ANDROID_SDK build-tools ----
find_aapt() {
  if have aapt2; then echo aapt2; return; fi
  if have aapt;  then echo aapt;  return; fi
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [ -n "$sdk" ] && [ -d "$sdk/build-tools" ]; then
    local a
    a=$(ls -1 "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)
    [ -n "$a" ] && { echo "$a"; return; }
    a=$(ls -1 "$sdk"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)
    [ -n "$a" ] && { echo "$a"; return; }
  fi
}
AAPT="$(find_aapt || true)"

record_identity() {
  # $1 = base.apk, writes to $IDENT
  local apk="$1"
  {
    echo "# identity"
    echo "artifact: $apk"
    echo "sha256: $(sha256 "$apk")"
    echo "size_bytes: $(wc -c < "$apk" 2>/dev/null || echo '?')"
    if [ -n "$AAPT" ]; then
      "$AAPT" dump badging "$apk" 2>/dev/null \
        | grep -E "^package:|sdkVersion:|targetSdkVersion:|application-label:" | head -8
    else
      echo "(aapt/aapt2 not found: package/version/sdk unknown - install Android build-tools)"
    fi
    echo "# signing cert"
    if have apksigner; then
      apksigner verify --print-certs "$apk" 2>/dev/null | grep -Ei "Signer|SHA-256|DN:" | head -12 \
        || echo "(apksigner could not verify; is it a split-only apk?)"
    elif have keytool; then
      echo "(apksigner missing; extract META-INF/*.RSA and run: keytool -printcert -file <that>)"
    else
      echo "(no apksigner/keytool; signing cert unknown)"
    fi
  } > "$IDENT"
  say "identity -> $IDENT"
}

# ---------------------------------------------------------------------------
# pkg:<name>  -> DYNAMIC pull from device
# ---------------------------------------------------------------------------
if [ "${TARGET#pkg:}" != "$TARGET" ]; then
  PKG="${TARGET#pkg:}"
  WORKDIR="${WORKDIR:-work/$PKG}"
  mkdir -p "$WORKDIR/input" "$WORKDIR/decoded" "$WORKDIR/evidence"
  IDENT="$WORKDIR/identity.txt"

  say ""
  say "============================================================"
  say " Pulling '$PKG' from the connected device. Fine for your own device; for a target you were engaged to assess, confirm scope first (see 00-authorization.md)."
  say " This touches a running system. It is ONLY allowed if you"
  say " are authorized (see references/00-authorization.md) and"
  say " have recorded target/basis/scope in the engagement log."
  say "============================================================"
  printf "Proceed? type 'yes' to continue: "
  read -r ans
  [ "$ans" = "yes" ] || die "aborted (no authorization confirmation)"

  have adb || die "adb not found (install Android platform-tools)"
  # /sdcard and device paths: on Windows Git-Bash export MSYS_NO_PATHCONV=1 so paths are not mangled.
  paths=$(adb shell pm path "$PKG" 2>/dev/null | tr -d '\r' | sed 's/^package://')
  [ -n "$paths" ] || die "pm path returned nothing - is '$PKG' installed and the device authorized? (adb devices)"

  i=0
  base=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    out="$WORKDIR/input/$(basename "$p")"
    say "pull $p"
    adb pull "$p" "$out" >/dev/null 2>&1 || warn "pull failed: $p"
    case "$(basename "$p")" in base.apk) base="$out";; esac
    i=$((i+1))
  done <<EOF
$paths
EOF
  say "pulled $i file(s) to $WORKDIR/input/"
  [ -n "$base" ] || base=$(ls -1 "$WORKDIR"/input/*.apk 2>/dev/null | head -1)
  [ -n "$base" ] && record_identity "$base" || warn "no base.apk found to identify"

# ---------------------------------------------------------------------------
# local file
# ---------------------------------------------------------------------------
else
  [ -f "$TARGET" ] || die "no such file: $TARGET"
  stem=$(basename "$TARGET"); stem="${stem%.*}"
  WORKDIR="${WORKDIR:-work/$stem}"
  mkdir -p "$WORKDIR/input" "$WORKDIR/decoded" "$WORKDIR/evidence"
  IDENT="$WORKDIR/identity.txt"
  base=""

  case "$TARGET" in
    *.apk)
      cp "$TARGET" "$WORKDIR/input/base.apk"
      base="$WORKDIR/input/base.apk"
      say "copied apk -> $base"
      ;;
    *.apkm|*.xapk|*.aab|*.zip)
      have unzip || die "unzip not found"
      ext="$WORKDIR/input/decoded-input"
      mkdir -p "$ext"
      unzip -o -q "$TARGET" -d "$ext" || die "unzip failed for $TARGET"
      # find the base apk inside the bundle (names vary: base.apk, <pkg>.apk, *.apk at root)
      base=$(ls -1 "$ext"/base.apk 2>/dev/null | head -1)
      [ -n "$base" ] || base=$(find "$ext" -maxdepth 2 -name '*.apk' ! -name 'split_*' ! -name 'config.*' 2>/dev/null | head -1)
      [ -n "$base" ] || base=$(find "$ext" -maxdepth 2 -name '*.apk' 2>/dev/null | head -1)
      say "bundle unzipped to $ext"
      say "splits:"
      find "$ext" -maxdepth 2 -name '*.apk' 2>/dev/null | sed 's/^/  /'
      [ "${TARGET##*.}" = "aab" ] && warn "this is an .aab (app bundle), not installable directly; base module apk is inside"
      ;;
    *)
      die "unrecognised extension: $TARGET (want .apk/.apkm/.xapk/.aab)"
      ;;
  esac
  [ -n "$base" ] && record_identity "$base" || warn "no base.apk located inside the bundle"
fi

# ---- findings-ledger stub, shared layout ----
LEDGER="$WORKDIR/findings.md"
if [ ! -f "$LEDGER" ]; then
  cat > "$LEDGER" <<EOF
# Findings ledger

Working dir: $WORKDIR
Started: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?')

| ID | Stage | Finding | Evidence | Status |
|----|-------|---------|----------|--------|
EOF
  say "ledger  -> $LEDGER"
fi

say ""
say "working dir ready: $WORKDIR"
say "next: apktool d \"$base\" -o \"$WORKDIR/decoded\"   (Stage B)"
