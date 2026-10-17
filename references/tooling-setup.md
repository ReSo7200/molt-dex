# Tooling setup

Install and sanity-check the tools the pipeline uses. The core is deliberately small: **apktool**
to decode and rebuild, **adb** to talk to a device, **scrcpy** to watch and drive it,
**ripgrep** to search the decoded tree. The rest come in when a target needs them.

**apktool first, not JADX.** This pipeline reasons over apktool's decoded smali and resources,
which round-trip (you can rebuild and reinstall). JADX is an optional, read-only convenience for
eyeballing a decompiled Java view; nothing in the pipeline depends on it, so it is not required.

## Core tools

### apktool

Decodes resources and `AndroidManifest.xml` to readable XML and the DEX to smali, and can rebuild.

- Get the latest `apktool.jar` from the official releases, plus the small wrapper script for your
  OS. Many package managers also ship it (`brew install apktool`, `apt install apktool`).
- Sanity check:

```bash
apktool --version          # if using the wrapper
java -jar apktool.jar --version   # if calling the jar directly
```

- Decode / rebuild:

```bash
java -jar apktool.jar d target.apk -o work/target_src      # decode
java -jar apktool.jar b work/target_src -o work/rebuilt.apk # rebuild
```

### Android platform-tools (adb)

The device bridge. Install the platform-tools package from the Android SDK (or `brew install
android-platform-tools`, `apt install android-tools-adb`).

```bash
adb version
adb devices        # a device should show as "device", not "unauthorized"/"offline"
```

If it shows `unauthorized` or `offline`, see the adb gotchas in `references/device-loop.md`
(`kill-server` / `start-server` and accept the on-device prompt).

### scrcpy

Mirror and control the device over adb.

```bash
scrcpy --version
scrcpy --stay-awake
```

### ripgrep

Fast search over the decoded tree and the string index.

```bash
rg --version
rg -n "some_string" work/target_src/
```

## Supporting tools (as needed)

### apksigner and keytool

To install a rebuilt APK on a test device you must sign it. A debug key is fine for testing.

```bash
keytool -genkey -v -keystore debug.keystore -alias a -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android -dname "CN=debug"
apksigner sign --ks debug.keystore --ks-pass pass:android work/rebuilt.apk
apksigner verify work/rebuilt.apk
```

Note: an app already installed with a different signing key will refuse an update signed with your
key. Uninstall first on the test device.

### Native disassembler (for `.so`)

When logic lives in native libraries (rung 5 of the obfuscation ladder), start with the basics and
reach for a disassembler for the real work.

```bash
readelf -a lib/arm64-v8a/libfoo.so | less     # headers, exported symbols
strings -n 6 lib/arm64-v8a/libfoo.so | less    # embedded strings, constants
```

For the logic: radare2 (`r2 libfoo.so`) or Ghidra (GUI, strong decompiler) are both good options.
Pick whichever you know.

### Proxy for traffic

To read API traffic (in scope only), run an intercepting proxy (mitmproxy-style), point the test
device's Wi-Fi proxy at it, and install the proxy's CA on the device.

Two Android facts to know:

- **Android 7+ ignores user-added CAs for app traffic by default.** An app only trusts a
  user-installed CA if its `networkSecurityConfig` opts in (`<certificates src="user"/>`). For an
  app you can rebuild in-scope, you can add a debug network-security-config; for one you cannot,
  you are limited to what the app already trusts.
- **Certificate pinning** defeats even a trusted CA. That is the pinning rung in
  `references/obfuscation-ladder.md`: document it, and only work around it under explicit
  authorization.

### Runtime resolution and hooking (Stage E, gated)

For resolving and instrumenting an obfuscated app at runtime, see
`references/07-runtime-resolution-instrumentation.md`. In short:

- **DexKit** (library, runs inside the target) to resolve a member by string / shape /
  relationship when the name is obfuscated.
- The **Xposed API** for the hooks, delivered by **LSPosed** (needs a rooted device or rooted
  emulator) or **LSPatch** (patches the in-scope APK, no root). Install the framework, then load
  your module.
- **Frida** (`frida-server` on root, or a gadget in a repackaged in-scope app) for quick traces
  and memory dumps with nothing left installed.

These only matter once dynamic work is authorized.

## Windows / Git-Bash notes

If you run the tooling under Git-Bash / MSYS on Windows, two things from our experience:

- **Device-side absolute paths get rewritten.** A command like
  `adb shell uiautomator dump /sdcard/ui.xml` fails because MSYS turns `/sdcard/...` into a Windows
  path. Export `MSYS_NO_PATHCONV=1` for those commands (see `references/device-loop.md`).
- **Prefer forward slashes and quote paths** when invoking `java -jar` with Windows paths, and use
  absolute paths for the jar and the APK to avoid surprises with the working directory.

## Minimum to start

For static-only work (Stages A to D) you need just **apktool** and **ripgrep**. Add **adb** and
**scrcpy** when you move to dynamic analysis (Stage E), which is gated anyway. Everything else is
per-target.
