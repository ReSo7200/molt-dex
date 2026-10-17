# Stage D: Secrets & misconfig

Goal: sweep the decoded app for hardcoded secrets and for configuration mistakes. Two passes, a
secrets sweep and a misconfig checklist, each producing findings in the format at the bottom.

This is static work on a local file, always fine. Per `references/00-authorization.md`, record every secret as
**class + location**, not by pasting the raw value into shared output, and verify a secret only
against the in-scope system it belongs to.

## Pass 1: secrets sweep

### Where to look

| Location | What hides there |
|---|---|
| `const-string` in smali | API keys, tokens, HMAC/signing secrets, hardcoded passwords, base URLs |
| `assets/`, `res/raw/` | config JSON, `.properties`, certificates, keystores, seed credentials |
| `res/values/strings.xml` (full decode) | keys devs put in string resources (very common) |
| native libs `lib/*/*.so` | keys moved to native to look "hidden"; `strings` still finds many |
| config / override files | default configs, feature-flag dumps, backend lists |
| `AndroidManifest.xml` `<meta-data>` | Maps/Firebase/ad-network keys declared as meta-data |

### High-signal patterns

Run these over the decoded tree and the string index. Treat hits as leads to confirm, not as
confirmed secrets.

```bash
cd "$WORK/decoded"

# Google / Firebase / Maps API keys
rg -rn 'AIza[0-9A-Za-z_\-]{35}' .

# AWS access key id, and nearby secret
rg -rn 'AKIA[0-9A-Z]{16}' .
rg -rn -i 'aws.?secret.?access.?key' .

# Google OAuth client ids
rg -rn '[0-9]{10,12}-[0-9a-z]{32}\.apps\.googleusercontent\.com' .

# Slack / GitHub / Stripe style tokens
rg -rn 'xox[baprs]-[0-9A-Za-z-]{10,}' .
rg -rn 'gh[pousr]_[0-9A-Za-z]{36}' .
rg -rn 'sk_(live|test)_[0-9A-Za-z]{24,}' .

# JWTs
rg -rn 'eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.' .

# private keys and keystores
rg -rn -- '-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----' .
find . -name '*.jks' -o -name '*.keystore' -o -name '*.p12' -o -name '*.pem'

# generic secret-shaped assignments
rg -rn -i '(secret|passwd|password|api[_-]?key|token|private[_-]?key)\s*[:=]\s*["'\''][^"'\'' ]{8,}' .

# backend hosts (map the surface even when not secret)
grep -oE 'https?://[A-Za-z0-9._-]+' "$WORK/notes/strings.tsv" | sort -u
```

For native libs, pull printable strings before assuming nothing is there:

```bash
for so in $(find . -name '*.so'); do echo "== $so"; strings -n 8 "$so" | rg -i 'key|secret|token|https?://'; done
```

### Reduce false positives

A match is a lead. Before reporting, confirm the value is actually a live secret and not a
placeholder, a public key, a sample from a library, or a test fixture. Check the surrounding code:
is it passed to an auth header, a signing routine, a cloud SDK init? A key that is only used to
talk to a first-party backend in scope is in scope to verify; a third-party key (someone else's
service) is reported but **not** tested against that third party.

## Pass 2: misconfig checklist

Most of these come straight from the Stage B manifest read; confirm and write them up here.

| Check | How to find it | Why it matters |
|---|---|---|
| Debuggable build | `android:debuggable="true"` | anyone can run-as the app, read its data, attach a debugger |
| Cleartext traffic | `usesCleartextTraffic="true"`, or no `network_security_config` on older target SDK | plaintext HTTP, trivially intercepted |
| Weak network-security-config | `res/xml/*.xml`: `cleartextTrafficPermitted="true"`, `<trust-anchors>` including `user` CAs, no `<pin-set>` | weakens or removes TLS protection; user-CA trust makes proxying easy |
| Exported + unprotected components | exported with no permission or a `normal`/`dangerous` custom permission | externally invokable; check what they trust |
| Exported content provider | `android:exported="true"` provider, `grantUriPermissions`, path rules | path traversal (`../`) and SQL injection via the query URI |
| World-readable storage | `MODE_WORLD_READABLE/WRITEABLE`, files written to external storage | other apps can read app data |
| Insecure deep-link handling | deep-link handler passes host/path to a WebView, a redirect, or a privileged action without validation | open redirect, WebView loadUrl with attacker URL, auth bypass |
| Broken / absent pinning | no `CertificatePinner`, a no-op `TrustManager`, pins only in a config that also trusts user CAs | MITM on a hostile network |
| Backup enabled | `allowBackup="true"` | `adb backup` can extract app data on many devices |
| Janus / v1-only signing | signed only with the v1 (JAR) scheme | historical tampering class; note the signing scheme from `apksigner verify -v` |

```bash
cd "$WORK/decoded"
rg -n 'MODE_WORLD_READABLE|MODE_WORLD_WRITEABLE' --include '*.smali' -r .
cat base-full/res/xml/network_security_config.xml 2>/dev/null
apksigner verify -v "$WORK/artifact/base.apk" | rg -i 'scheme|verified'
```

Each misconfig becomes a finding; the exported-component and deep-link ones usually get confirmed
for real in Stage E by actually invoking them (`am start`, `am broadcast`, `content query`) within
scope.

## Finding format

Write each finding into the ledger like this:

```
[severity] <short title>
  where:   res/values/strings.xml:48   (or X.0aB.smali:142, assets/config.json)
  class:   Google Maps API key   (class + location, not the raw value in shared output)
  impact:  one line on what an attacker gains
  verify:  how to confirm, against the in-scope system only
```

Example:

```
[medium] Hardcoded first-party API signing secret
  where:   smali_classes3/X/0aB.smali:142  (anchored by const-string "x-sig")
  class:   HMAC request-signing secret for api.example.com (in scope)
  impact:  lets a client forge signed requests to the first-party API
  verify:  replay a signed request to the in-scope api.example.com with a test account
```

Keep raw secret values only in the restricted working notes if the engagement needs them, never in
anything shared, and never test a third-party key against the third party.

## Done when

- Secrets sweep run over smali, assets, resources, native libs, and config; leads confirmed.
- Misconfig checklist walked; each hit written up.
- Every finding is in the ledger in the format above, as class + location.

Next: confirm the exploitable ones on device with `references/05-dynamic-analysis.md`, then write
them up with `references/06-verify-report.md`.
