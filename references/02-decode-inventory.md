# Stage B: Decode & inventory

Goal: turn the APK into readable smali and resources with **apktool**, build the one index that
every later stage leans on (the string index), and read the manifest to map the attack surface.

This is static work on a local file, always fine. This stage is the backbone; time spent here pays back in every
later lookup.

## 1. Decode with apktool

```bash
cd "$WORK"
apktool d -r -f -o decoded/base artifact/base.apk
```

- `-r` ("no res") skips decoding resources back to source XML. It is much faster and gives you
  the raw compiled resources plus `AndroidManifest.xml` already made readable. Use it by default,
  it is what you want for code analysis.
- **Drop `-r`** when you specifically need the real resource XML: `res/values/strings.xml`,
  layouts, `res/xml/network_security_config.xml`, drawables by name. Then run a full decode:
  `apktool d -f -o decoded/base-full artifact/base.apk`. The network-security-config and string
  resources matter for Stage D, so a full decode of at least `res/` is usually worth it.
- `-f` overwrites a previous decode.

Decode the splits you need the same way (`decoded/split_feature`, etc.) when a class or resource
is missing from base.

Rebuild (for Stage E re-pack testing, noted here so it is in one place):

```bash
apktool b -o rebuilt.apk decoded/base      # then zipalign + apksigner sign with a debug key
```

## 2. Build the string index (the anchor backbone)

Obfuscated builds rename classes and methods every release, but the **string literals do not
change**: log tags, QPL/telemetry markers, JSON keys, URL fragments, resource names, error
messages. The string index is a flat table that lets you jump from "a string I can see in the UI
or the docs" to "the exact method that uses it". Almost every method you locate in Stage C starts
from a string hit here.

A practical index is a TSV of `(smali file, method, string literal)`:

```bash
cd "$WORK/decoded/base"
python3 -I - "$PWD" > "$WORK/notes/strings.tsv" <<'PY'
import os, re, sys
root = sys.argv[1]
meth = re.compile(r'^\.method\b.*?(\S+\(.*)')   # capture the method signature line
strg = re.compile(r'const-string(?:/jumbo)?\s+\w+,\s+"((?:\\.|[^"\\])*)"')
for dp, _, fns in os.walk(root):
    for fn in fns:
        if not fn.endswith(".smali"):
            continue
        path = os.path.relpath(os.path.join(dp, fn), root)
        cur = "<class>"
        with open(os.path.join(dp, fn), encoding="utf-8", errors="replace") as f:
            for line in f:
                m = meth.match(line.strip())
                if m:
                    cur = m.group(1); continue
                if line.strip() == ".end method":
                    cur = "<class>"; continue
                s = strg.search(line)
                if s:
                    print(f"{path}\t{cur}\t{s.group(1)}")
PY
wc -l "$WORK/notes/strings.tsv"
```

Now a string becomes a one-line lookup:

```bash
# which method builds the feed request?
grep -F 'homecoming_all' "$WORK/notes/strings.tsv"
# res\...  Media.smali   A01(...)   "reel_mentions"   <- file, method, the string
```

ripgrep straight over the tree works too, but the TSV gives you the enclosing method for free,
which is what you actually want:

```bash
rg -n 'const-string .*"IgFeedVideoPlayer' decoded/base   # file + line, but you then hunt for the method
```

Keep the TSV in `notes/`. You will `grep` it constantly.

## 3. Class and method inventory

A couple of cheap inventories help you navigate and spot the shape of the app:

```bash
cd "$WORK/decoded/base"
# every class, by smali path
find . -name '*.smali' | sed 's#^\./##; s#\.smali$##' > "$WORK/notes/classes.txt"
wc -l "$WORK/notes/classes.txt"

# obfuscation smell test: how many classes are single/double-letter or in X/
grep -cE '(^|/)[A-Za-z0-9]{1,2}(/|$)' "$WORK/notes/classes.txt"
rg -c '^\.method' $(find . -name '*.smali') | awk -F: '{s+=$2} END{print s" methods"}'
```

If most classes live under `X/` or have one and two character names, you are on the name-obfuscation
rung (see `references/obfuscation-ladder.md`). If class names are real (`com.example.net.ApiClient`),
Stage C is mostly reading.

## 4. Read the manifest (the attack surface)

`decoded/base/AndroidManifest.xml` is readable after apktool. Every item below is attack surface;
list each one into the engagement log with a note on why it matters.

### Exported components

A component is reachable by other apps if `android:exported="true"`, or implicitly when it has an
`<intent-filter>` and no explicit `exported` (behaviour varies by target SDK; on target SDK 31+ an
explicit value is required, so an intent-filter without `exported` is worth a closer look).

```bash
cd "$WORK/decoded/base"
rg -n 'android:exported="true"' AndroidManifest.xml
rg -n '<(activity|service|receiver|provider)\b' AndroidManifest.xml
```

| Component | Why it is surface |
|---|---|
| exported activity | can be started by any app; check what intent extras it trusts |
| exported service | can be bound/started externally; check what commands it accepts |
| exported receiver | can be sent broadcasts externally; check the actions it handles |
| exported provider | can be queried/written externally; check `grantUriPermissions`, path permissions, SQL built from the URI (traversal / injection) |

### Permissions

```bash
rg -n '<uses-permission|<permission\b' AndroidManifest.xml
```

- Requested permissions tell you what the app can do (location, SMS, accounts, storage).
- **Custom-defined** `<permission>` entries with a weak `protectionLevel` (`normal`/`dangerous`
  instead of `signature`) are a classic hole: a component "protected" by a custom permission any
  app can request is not protected at all.

### Flags that are findings on their own

```bash
rg -n 'android:debuggable|usesCleartextTraffic|networkSecurityConfig|allowBackup|taskAffinity' AndroidManifest.xml
```

| Flag | Meaning |
|---|---|
| `android:debuggable="true"` | anyone can attach a debugger / run as the app on any device. Should never ship. |
| `android:usesCleartextTraffic="true"` | plaintext HTTP allowed app-wide |
| `android:networkSecurityConfig` | points to `res/xml/...`; read it (pins, cleartext exceptions, trusted user CAs). A config that trusts user-added CAs makes proxying trivial and weakens pinning. |
| `android:allowBackup="true"` | app data can be extracted via `adb backup` on many devices |
| `android:taskAffinity` set oddly | task-hijack / StrandHogg style surface |

### Deep links

```bash
rg -n '<data ' AndroidManifest.xml      # android:scheme / android:host / android:pathPrefix
```

Each `<data>` scheme+host is an externally reachable entry point. Note them; Stage C traces what
the handler does with the URL (does it trust host/path, open a WebView, pass params to a privileged
action), and Stage E can fire them with `adb shell am start -a android.intent.action.VIEW -d`.

### Provider authorities

```bash
rg -n 'android:authorities' AndroidManifest.xml
```

List authorities and whether the provider is exported and uses `grantUriPermissions`. Exported
providers are a top source of path-traversal and data-leak bugs.

## 5. Output: the attack-surface summary

Write a short table into the ledger before leaving this stage:

- Exported activities / services / receivers / providers (with the intents/actions they take).
- Custom permissions and their protection level.
- debuggable / cleartext / backup / network-security-config findings.
- Deep-link schemes and hosts.
- Provider authorities.

This is the menu Stage C investigates and Stage E exercises.

## Done when

- `decoded/base` exists and (if you need resource XML) `decoded/base-full`.
- `notes/strings.tsv` and `notes/classes.txt` are built.
- The manifest attack-surface summary is in the ledger.

Next: `references/03-static-understanding.md`.
