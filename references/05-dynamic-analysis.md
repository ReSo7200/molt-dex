# Stage E: Dynamic analysis

**Know which category you are in (see `00-authorization.md`).** Running the app on your own device
or emulator, with your own account, and instrumenting it to understand or mod it is `local` work:
fine, no authorization record needed. That covers almost everything in this stage, and it is
exactly how the Instagram work was done. The moment an action reaches past your own instance,
sending crafted traffic to the backend to test it, probing another account, exploiting a
server-side flaw, it becomes `assessment` work: stop and make sure the gate has passed and the
scope is in `templates/engagement-log.md` first.

Static reading (Stages B to D) told you how the app is *supposed* to work and where the
interesting code is. This stage proves or kills each of those hypotheses against the running app.
A method you suspect handles auth either fires with the arguments you expected, or it does not.
That confirmation is the whole point, not just "poking the app".

Log every action with a timestamp in the engagement log as you go.

## 1. Set up the test device

Use a device or emulator you control, in scope, with test accounts only.

```bash
adb devices                      # confirm the device is attached and authorized
adb shell getprop ro.build.version.release   # Android version
adb shell getprop ro.product.model
```

Install the build you are testing:

```bash
adb install -r target.apk        # -r replaces an existing install (same signing key)
# split bundle:
adb install-multiple base.apk split_config.*.apk
```

Grant only the permissions the test needs, nothing broad "to be safe". Runtime permissions and
special app-ops are set per package:

```bash
adb shell pm grant <pkg> android.permission.CAMERA
adb shell appops set <pkg> MANAGE_EXTERNAL_STORAGE allow   # "all files access"
```

Note in the log: **a reinstall resets runtime permissions and special app-ops.** If the app
silently stops writing files or loses a permission after you reinstall a new build, re-grant
before you conclude anything is broken. This bites every time you iterate on builds.

## 2. The screenshot to read to act loop

This is how you actually operate the app. Full mechanics and gotchas are in
`references/device-loop.md`; the short version:

1. Have `scrcpy` mirroring so you can watch what happens.
2. `adb exec-out screencap -p > shot.png`, then read the screenshot.
3. When you need to tap a specific control, dump the view tree
   (`adb shell uiautomator dump`), find the node by its `text` / `content-desc` /
   `resource-id`, compute the centre of its `bounds`, and `adb shell input tap x y`.
4. Screenshot again to confirm the result before the next action.

Stay inside scope. Drive your own test accounts and test content. Never tap into another person's
profile, chat, or data to "see what happens".

## 3. Observe the running app

### Logcat, filtered to the package

Unfiltered logcat is noise. Scope it to the process:

```bash
pid=$(adb shell pidof <pkg> | tr -d '\r')
adb logcat --pid="$pid"
# or filter by a tag the app uses, or by your own instrumentation tag:
adb logcat -s MyHookTag:V
adb logcat | grep -a <pkg>
```

Look for: stack traces, the app's own debug logging, URLs, request/response fragments, and
anything your instrumentation prints.

### File writes under the app's data dir

The app's private storage shows you what it persists: shared-prefs XML, SQLite DBs, cached
tokens, downloaded config.

```bash
# rooted device / emulator:
adb shell su -c 'ls -la /data/data/<pkg>/shared_prefs /data/data/<pkg>/files'
adb shell su -c 'cat /data/data/<pkg>/shared_prefs/<name>.xml'

# debuggable app, no root:
adb shell run-as <pkg> ls -la shared_prefs
adb shell run-as <pkg> cat shared_prefs/<name>.xml
```

Reading a file to find where a setting lives, or to confirm a token is stored in cleartext, is
exactly the kind of evidence a finding needs. Record the path.

### Network traffic (in scope only)

Route the device through a proxy and read the API calls: base URLs, auth headers, what data goes
out, whether TLS is enforced, whether the app pins. Only point it at hosts inside the stated
scope. Cert pinning and user-CA trust are handled in `references/tooling-setup.md` and the
pinning rung in `references/obfuscation-ladder.md`.

### Runtime-decrypted strings and in-memory values

When the static tree had no readable literals (string encryption, see the obfuscation ladder),
the plaintext still exists at runtime. Capture it where it is produced rather than trying to
reimplement the decryptor. Likewise, the real value of a token or key is whatever is in memory
when the app uses it, not necessarily what is stored at rest.

## 4. Instrumentation under authorization

To watch specific methods, attach a hooking framework (Frida for a quick, root-or-gadget attach;
the Xposed API via LSPosed for root or LSPatch for no root, as a persistent module) and log the
arguments and return values of the methods you anchored in Stage C. In an obfuscated app, resolve
the member first with DexKit, then hook it. The tools, the Xposed before/after/replace callbacks,
and the exact patterns are in `references/07-runtime-resolution-instrumentation.md`. Keep it to
observation and confirmation, inside scope.

The habit that makes this productive is the same one from static analysis: **you already located
the method by shape, now you log it to learn the shape better.** Concretely, the pattern that
works again and again:

- Hook the method you suspect is a dispatcher or a builder, print its declaring class, its
  parameter types, and the live values. You often find that one logical action (say, building a
  menu, or entering a screen) is handled by *different* methods in different code paths, for
  example a `static` helper for one case and an instance method for another. Logging all the
  candidates behind a shared string anchor, then checking which actually fires, is how you find
  the real one without guessing from names that changed between versions.
- Print a value tree for an opaque object (walk its fields, call its no-arg getters) to learn
  which field holds the thing you care about, instead of hardcoding a field name.
- Dump the arguments of a serializer or a network call to recover plaintext that the static tree
  encrypted or built dynamically.

Remove or gate your instrumentation when done; do not leave a live hook running past the
engagement.

## 5. Correlate static and runtime (the heart of the stage)

For each hypothesis from Stage C, write down the prediction, then test it:

| Static hypothesis | Runtime check | Outcome |
|---|---|---|
| `X.0aB.A05(Media, Context)` builds the download menu | Hook it, open the menu, confirm it fires with those arg types | confirmed / wrong method / never fires |
| Auth token is HMAC-signed with a hardcoded key | Hook the signer, compare the key bytes to the static constant | confirmed / key comes from elsewhere |
| Deep link `app://x` reaches an exported activity unguarded | `adb shell am start -a VIEW -d 'app://x' <pkg>/...` and watch | reachable / blocked / needs auth |

A hypothesis that fires as predicted becomes a confirmed finding with runtime evidence. One that
does not is either wrong (drop it) or points at a code path you have not found yet (go back to
Stage C). Either way you now know, instead of guessing. Record the result and the evidence path
(log excerpt, screenshot, pcap) in the findings ledger.

Carry confirmed findings into `references/06-verify-report.md`.
