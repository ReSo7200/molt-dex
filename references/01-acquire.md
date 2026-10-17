# Stage A: Acquire & identify

Goal: get the app's artifact into a clean working directory, record exactly what it is, and set
up the ledger the rest of the pipeline writes to. Nothing here decompiles yet; this stage is
about provenance and hygiene.

Working on a file the user hands you is always fine. **Pulling an app off a device is a
dynamic action** (it touches a running system), so it needs the gate from
`references/00-authorization.md` to have passed.

## 1. Set up the working directory

One target, one working dir, kept separate from your scripts and from the skill itself.

```bash
export TARGET=com.example.app          # the package, used as a label
export WORK="$HOME/recon/$TARGET"
mkdir -p "$WORK/artifact" "$WORK/decoded" "$WORK/evidence" "$WORK/notes"
cp templates/engagement-log.md "$WORK/notes/engagement-log.md"
cp templates/report.md        "$WORK/notes/report.md"
```

- `artifact/` holds the untrusted input (APK, splits, bundle).
- `decoded/` is where apktool output lands in Stage B.
- `evidence/` collects screenshots, logcat snippets, captured requests.
- `notes/engagement-log.md` is the **findings ledger and audit trail**. Start filling it now with
  the artifact details below.

## 2. Get the artifact (three ways)

### a. A local file the user supplies

The simplest and lowest-risk path. Copy it into `artifact/` as-is and move to identity.

```bash
cp "/path/they/gave/app.apk" "$WORK/artifact/"
```

### b. Pull an installed package from a device

Pulling from your own device is fine; pulling to analyse a target you were engaged to assess is
category-3 work (see `00-authorization.md`). Modern apps are split, so list every path and pull
all of them, not just `base.apk`.

```bash
# every APK that makes up the installed app (base + splits)
adb shell pm path "$TARGET"
# -> package:/data/app/~~.../base.apk
#    package:/data/app/~~.../split_config.arm64_v8a.apk
#    package:/data/app/~~.../split_config.xxhdpi.apk   ...

mkdir -p "$WORK/artifact/installed"
adb shell pm path "$TARGET" | sed 's/^package://' | tr -d '\r' | while read -r p; do
  adb pull "$p" "$WORK/artifact/installed/"
done
```

On Windows / Git Bash, device paths like `/data/app/...` get mangled by path conversion. Prefix
the adb command with `MSYS_NO_PATHCONV=1` (this bites throughout the device loop; see
`references/device-loop.md`).

### c. A bundle: .apkm, .xapk, .aab

`.apkm` (APKMirror) and `.xapk` are just zip files that contain `base.apk` plus `split_*.apk`.
Unzip and treat the result like a split install.

```bash
cd "$WORK/artifact"
unzip -o app.apkm -d bundle/        # -> bundle/base.apk, bundle/split_config.*.apk, ...
```

`.aab` (Android App Bundle) is the publishing format, not an installable one. If you only have an
`.aab`, generate a device-specific APK set with `bundletool build-apks` and then `extract-apks`,
or just work from `base/` inside the bundle for static analysis.

### Merging splits

Most code lives in `base.apk`. Resources, per-ABI native libs, and occasionally a class live in a
`split_*.apk`. When Stage C says a class is referenced but you cannot find its definition in the
decoded base, decode the relevant split too and search there. You do not usually need to physically
merge; decoding base + the feature/config splits into sibling dirs and searching across both is
enough.

> Real example: Instagram ships as `base.apk` + a dozen `split_*.apk` (config, DPI, feature). We
> pulled the full set into `insta452/` and decoded `base.apk`; that held the Java/Kotlin classes
> we needed, while the splits carried resources and native code.

## 3. Record identity

Write all of this into the engagement log. It is how you tell two builds apart later and how a
reader reproduces your work.

```bash
cd "$WORK/artifact"
APK=base.apk                           # or bundle/base.apk

# hash first, always
sha256sum "$APK"

# package, versions, SDK levels (aapt from build-tools, or aapt2)
aapt dump badging "$APK" | grep -E "package:|sdkVersion|targetSdkVersion"
# package: name='...' versionCode='...' versionName='...'
# sdkVersion:'24'
# targetSdkVersion:'34'

# signing certificate (who signed it, and the digest you compare across builds)
apksigner verify --print-certs "$APK"
# Signer #1 certificate SHA-256 digest: ...
# (or: keytool -printcert -jarfile "$APK")

# split layout and size
ls -la .
du -h "$APK"
```

Minimum to capture:

| Field | Command source |
|---|---|
| package name | `aapt dump badging` |
| versionName / versionCode | `aapt dump badging` |
| minSdk / targetSdk | `aapt dump badging` |
| signing cert SHA-256 | `apksigner verify --print-certs` |
| split layout | `ls` of the bundle |
| file size + sha256 | `du`, `sha256sum` |

The signing cert digest matters twice: it tells you whether two APKs are from the same signer
(official vs repacked), and it is what a device checks when you later try to install a modified
build over an existing one (a different signer means you must uninstall first).

## 4. Untrusted-artifact hygiene

Treat every APK and bundle as hostile input:

- Keep it in its own `artifact/` dir, separate from your scripts.
- Pass paths as arguments to tools; do not `cd` into the artifact dir and run interpreters or
  build tools there (a planted `json.py` next to it would be imported before the real one).
- Run any analysis script that reads the artifact with the interpreter's isolated mode
  (`python -I script.py "$APK"`), so it will not load code from the artifact's directory.
- Do not execute anything from inside the artifact. You are reading it, not running it, until the
  authorized dynamic stage.

## Done when

- The artifact (and all splits) is in `artifact/`.
- The engagement log has package, versions, SDK levels, signer digest, and sha256.
- You know whether you are static-only or cleared for dynamic work.

Next: `references/02-decode-inventory.md`.
