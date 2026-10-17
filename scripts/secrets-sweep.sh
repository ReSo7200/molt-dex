#!/usr/bin/env bash
# secrets-sweep.sh - Stage D: sweep a decoded app for hardcoded secrets and cleartext.
#
# Usage:
#   secrets-sweep.sh <apktool-decoded-dir | extracted-root>
#
# Greps high-signal patterns across smali, assets, res and lib, grouped by category with
# file:line locations. This is a first pass, not proof: it finds candidates. Every hit still
# needs a human to confirm it is a live secret and not a placeholder, a test fixture, or a
# public key.
#
# HANDLING (per references/00-authorization.md):
#   - Report every finding as CLASS + LOCATION ("Stripe key in assets/config.json",
#     "HMAC secret in X.0aB.smali:142"), NOT by pasting the raw secret into the report body or
#     any shared output.
#   - Verify a secret ONLY against the in-scope system it belongs to. Never test a found
#     third-party key (a maps key, a cloud key) against that third party.
#
# Manual equivalent:
#   rg -n 'AIza[0-9A-Za-z_-]{35}' <root>      # one pattern at a time
#   rg -n -i 'api[_-]?key|secret|password|token' <root>
#   rg -n '-----BEGIN' <root>
#   rg -n 'http://' <root>                    # cleartext
#
# Requires: ripgrep (rg). Falls back to grep -rn if rg is missing (slower, fewer features).

set -u
ROOT="${1:-}"
[ -n "$ROOT" ] || { echo "usage: secrets-sweep.sh <decoded-dir>" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "ERROR: not a directory: $ROOT" >&2; exit 2; }

if command -v rg >/dev/null 2>&1; then
  SCAN() { rg -n --no-heading -o -e "$1" "$ROOT" 2>/dev/null | head -80; }
  SCANF() { rg -n --no-heading -e "$1" "$ROOT" 2>/dev/null | head -80; }
else
  echo "note: ripgrep not found, using grep -rn (slower)" >&2
  SCAN()  { grep -rEno "$1" "$ROOT" 2>/dev/null | head -80; }
  SCANF() { grep -rEn  "$1" "$ROOT" 2>/dev/null | head -80; }
fi

section() {
  local title="$1" pat="$2" full="${3:-}"
  echo ""
  echo "== $title =="
  local out
  if [ "$full" = "full" ]; then out=$(SCANF "$pat"); else out=$(SCAN "$pat"); fi
  if [ -n "$out" ]; then echo "$out"; else echo "  (none)"; fi
}

echo "secrets sweep: $ROOT"
echo "reminder: report as class+location; do not paste raw third-party secrets; verify only in scope."

section "Google API keys (AIza...)"      'AIza[0-9A-Za-z_-]{35}'
section "AWS access key ids (AKIA...)"   'AKIA[0-9A-Z]{16}'
section "Google OAuth client ids"        '[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com'
section "Slack tokens"                   'xox[baprs]-[0-9A-Za-z-]{10,}'
section "Private key blocks"             '-----BEGIN [A-Z ]*PRIVATE KEY-----' full
section "JWT-looking tokens"             'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'
section "Bearer tokens"                  'Bearer\s+[A-Za-z0-9._-]{16,}' full
section "Firebase / GCP URLs"            'https://[a-z0-9-]+\.(firebaseio|firebaseapp|appspot|cloudfunctions)\.[a-z.]+'
section "api_key / secret / token / password assignments" '(?i)(api[_-]?key|client[_-]?secret|app[_-]?secret|secret[_-]?key|access[_-]?token|auth[_-]?token|password)["'"'"':= ]{1,4}[A-Za-z0-9._/+-]{8,}' full
section "Cleartext http:// URLs"         'http://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]{4,}'

echo ""
echo "also check by hand:"
echo "  - assets/ for bundled config (json/properties/.env), keystores, db files"
echo "  - res/values/strings.xml and res/raw/ for embedded keys"
echo "  - lib/*/*.so with: strings lib.so | grep -iE 'key|secret|http'  (native secrets)"
echo "  - the app's own config/override files (e.g. a bundled feature-flag / MC override json)"
echo ""
echo "done. Confirm each candidate before you call it a finding; placeholders and public keys are common."
