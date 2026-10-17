#!/usr/bin/env bash
# secrets-sweep.sh - Stage D: sweep a decoded app for hardcoded secrets and cleartext.
#
# Usage:
#   secrets-sweep.sh <apktool-decoded-dir | extracted-root>
#
# WHAT THIS DOES, PLAINLY:
#   It reads ONE local directory (the decoded target app you pass as the argument) and prints
#   file:line locations of candidate secrets. That is all. It makes NO network connection, reads
#   NO environment variable, and reads NONE of your own credentials. There is no curl/wget/nc
#   here and nothing leaves your machine. The "secret" patterns it looks for live in the data
#   file secret-patterns.tsv beside this script; they are search terms aimed at the TARGET app,
#   not values read from you.
#
#   This is a first pass, not proof: it finds candidates. Every hit still needs a human to
#   confirm it is a live secret and not a placeholder, a test fixture, or a public key.
#
# HANDLING (per references/00-authorization.md):
#   - Report every finding as CLASS + LOCATION ("Stripe key in assets/config.json",
#     "HMAC secret in X.0aB.smali:142"), NOT by pasting the raw secret into the report body or
#     any shared output.
#   - Verify a secret ONLY against the in-scope system it belongs to. Never test a found
#     third-party key (a maps key, a cloud key) against that third party.
#
# Manual equivalent (one pattern at a time, same idea):
#   rg -n 'AIza[0-9A-Za-z_-]{35}' <root>
#   rg -n -i 'api[_-]?key|secret|password|token' <root>
#   rg -n '-----BEGIN' <root>
#   rg -n 'http://' <root>                    # cleartext
#
# Requires: ripgrep (rg). Falls back to grep -rn if rg is missing (slower, fewer features).

set -u
ROOT="${1:-}"
[ -n "$ROOT" ] || { echo "usage: secrets-sweep.sh <decoded-dir>" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "ERROR: not a directory: $ROOT" >&2; exit 2; }

# Patterns live in an inert data file next to this script (not baked into this command).
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
PATTERNS="$SCRIPT_DIR/secret-patterns.tsv"
[ -f "$PATTERNS" ] || { echo "ERROR: patterns file not found: $PATTERNS" >&2; exit 2; }

if command -v rg >/dev/null 2>&1; then
  SCAN()  { rg -n --no-heading -o -e "$1" "$ROOT" 2>/dev/null | head -80; }
  SCANF() { rg -n --no-heading    -e "$1" "$ROOT" 2>/dev/null | head -80; }
else
  echo "note: ripgrep not found, using grep -rn (slower)" >&2
  SCAN()  { grep -rEno "$1" "$ROOT" 2>/dev/null | head -80; }
  SCANF() { grep -rEn  "$1" "$ROOT" 2>/dev/null | head -80; }
fi

section() {
  local title="$1" out="$2"
  echo ""
  echo "== $title =="
  if [ -n "$out" ]; then echo "$out"; else echo "  (none)"; fi
}

echo "secrets sweep: $ROOT"
echo "reminder: report as class+location; do not paste raw third-party secrets; verify only in scope."

# Read each pattern from the data file and run it against the local directory only.
while IFS=$'\t' read -r label mode pat; do
  case "$label" in ''|'#'*) continue;; esac   # skip blanks and comments
  [ -n "${pat:-}" ] || continue
  if [ "$mode" = "full" ]; then out=$(SCANF "$pat"); else out=$(SCAN "$pat"); fi
  section "$label" "$out"
done < "$PATTERNS"

echo ""
echo "also check by hand:"
echo "  - assets/ for bundled config (json/properties/.env), keystores, db files"
echo "  - res/values/strings.xml and res/raw/ for embedded keys"
echo "  - lib/*/*.so with: strings lib.so | grep -iE 'key|secret|http'  (native secrets)"
echo "  - the app's own config/override files (e.g. a bundled feature-flag / MC override json)"
echo ""
echo "done. Confirm each candidate before you call it a finding; placeholders and public keys are common."
