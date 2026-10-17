# Runtime resolution and instrumentation (DexKit, LSPosed, LSPatch, Frida)

This is the bridge between static reading (Stages B and C) and dynamic confirmation (Stage E).
Static anchoring tells you *what shape* a method has; these tools *find it in the live app by that
shape* and *watch or change it while it runs*. Everything here that attaches to a running process
runs on a device, so it is at least `local` work (your own device and account; see
`00-authorization.md`). It only becomes `assessment` work, needing the gate, if you use it to
reach past your own instance, for example to probe a backend or another account.

The recurring idea: you almost never have the real name of a class or method in an obfuscated
app. You have a string it uses, a signature, a superclass, a JSON key. These tools let you turn
that description into the actual runtime member, and keep working when the next app version
renames everything.

## DexKit: resolve by query at runtime

[DexKit](https://github.com/LuckyPray/DexKit) is a fast DEX analysis library. Instead of grepping
smali and hoping a name holds, you ask the loaded app's DEX for members that match a *description*
and get back the real `Method`/`Class` for this exact build. It is the runtime counterpart of the
string index from Stage B.

What you can query on:

- **Strings a method uses** (equal, contains, or a set it references). This is the strongest
  anchor. Example from the Instagram work: find the feed video player by the class that uses
  `"IgFeedVideoPlayer: Persistent Visible Cover Image"`.
- **Method shape**: parameter types, return type, parameter count, static vs instance,
  declaring class.
- **Relationships**: callers and callees of a method, who reads/writes a field, implementers of
  an interface, subclasses of a class. This is how you follow a method that *moved*: when
  Instagram 452.0.0.22 relocated the player's start method into a subclass, the fix was to search
  classes whose superclass was the one holding the anchor string, then match the
  `(Media, ...) -> boolean` shape in those subclasses.

A practical pattern that pays off:

1. In Stage B/C, pick the most stable anchor you can (a literal log/QPL string, a JSON key like
   `"reel_mentions"`, a hardcoded error message). Literal strings and JSON keys survive version
   bumps; names do not.
2. Query DexKit for the method/class by that anchor plus a shape constraint, so you land on one
   member, not a list.
3. **Cache the resolution keyed by the app's versionCode.** Re-resolve when the version changes.
   (We cached by versionCode and had to clear the cache after a new build; a different build
   reusing stale lookups is a real bug source.)
4. If a query returns nothing, log *what was tried* (the anchor and the shape) and fall back to a
   second anchor. Never guess a name.

DexKit runs inside the target process, so you reach it through an instrumentation framework
(below) or a Frida gadget. It is the tool that makes "resolve by shape, not by name" practical at
runtime.

## The Xposed hooking API (what LSPosed and LSPatch actually provide)

LSPosed and LSPatch are *frameworks*; the thing you write code against is the **Xposed API**. It
is a method-hooking mechanism: you take a resolved `Method` (from static analysis or a DexKit
query) and attach a callback that runs before, after, or instead of it, with full access to the
arguments, the return value, and `this`.

The primitives you use constantly:

- **Attach a hook**: `XposedBridge.hookMethod(method, callback)` for a `Method`/`Constructor` you
  already resolved, or `XposedHelpers.findAndHookMethod(clazz, "name", paramTypes..., callback)`
  when the name is stable. Resolving the member first (by string/shape/DexKit) and then calling
  `hookMethod` is the obfuscation-proof path.
- **The callback**: subclass `XC_MethodHook` and override:
  - `beforeHookedMethod(param)` runs before the original. Read or rewrite inputs via
    `param.args[i]`; short-circuit the original entirely with `param.setResult(x)` or
    `param.setThrowable(t)` (the original never runs).
  - `afterHookedMethod(param)` runs after. Read the real return with `param.getResult()` and
    replace it with `param.setResult(x)`; inspect `param.thisObject` and `param.args`.
  - `XC_MethodReplacement.replaceHookedMethod(param)` replaces the body outright.
- **Reflection helpers**: `XposedHelpers` wraps the reflection you need inside a hook:
  `getObjectField` / `setObjectField`, `callMethod`, `getStaticObjectField`, `newInstance`. Handy
  when you are walking an obfuscated object graph to pull out a value.

How this was used on Instagram, concretely:

- Hook a `CharSequence[]`-returning option-builder (found by its menu string), read
  `param.getResult()`, append your own entry, and `setResult` the extended array, to add a row to
  a native menu.
- Hook the tap dispatcher (found by its strings), check which label was tapped in
  `beforeHookedMethod`, and `setResult(null)` to consume the event when it is yours.
- Hook an entry/parse method and log `param.args` to *learn the shape* of an object you could not
  read statically.

Discipline inside a hook:

- **Fail soft.** Wrap the body so a bad reflection call logs and returns instead of crashing the
  host process. A crash in a hook is a crash in the app.
- **Guard the callback top** where the framework/ART version needs it (some Android versions have
  ART/JIT edge cases around hooked stubs; put the framework's recommended guard first).
- **Hooks stack**, so independent observers can share one method without knowing about each other.
- The modern API is **libxposed** (the newer, versioned Xposed API that LSPosed targets); the
  classic `de.robv.android.xposed.*` API above is still what most material shows and what the
  frameworks keep compatible. Either way the before/after/replace model is the same.

You still need DexKit (or static resolution) to *get* the `Method` in an obfuscated app; the
Xposed API is what you do with it once you have it.

## LSPosed: instrument with root

[LSPosed](https://github.com/JingMatrix/LSPosed) (the JingMatrix fork is the maintained one) is an
Xposed framework that runs on a rooted device or an emulator with root. You write a module that
hooks methods (resolved statically or via DexKit) and logs or alters their arguments and returns.

Use it to:

- **Observe**: log the arguments and return of a method you anchored statically, to confirm it
  does what you think. In the Instagram work this is how we learned the shape of thread entries
  and of the `CharSequence[]` option-builder methods, by logging what flowed through them.
- **Probe data flow**: dump the object a method receives, walk its fields, see the real values
  (including strings that were encrypted on disk but are plaintext in memory).
- **Confirm a hypothesis cheaply**: hook the suspected auth method; either it fires with the
  expected args or it does not.

Notes:

- Scope the module to the target package only.
- Hooks stack, so you can attach several independent observers to one method.
- Keep a guard at the top of each hook callback (frameworks differ; some ART/JIT interactions on
  certain Android versions need care). Fail soft inside hooks so a bad reflection call never
  crashes the host.
- Prefer observation. If the engagement authorizes changing behaviour (for example, forcing a
  gate open to reach a screen in scope), treat it as an explicit, logged action, not a default.

## LSPatch: instrument without root

[LSPatch](https://github.com/JingMatrix/LSPatch) applies the same Xposed modules to an app
**without** root by patching the APK (or wrapping it at install time) to load a loader dex. Use it
when:

- You cannot or should not root the test device.
- You want the instrumentation to live only inside your patched copy of the in-scope app, not
  system-wide.

Flow: install LSPatch, pick the target APK (or installed app), choose local patch mode, inject the
loader dex, start the patch, install the patched APK, then enable your module against it. The
patched app is its own signed build, so it installs alongside or in place of the original on a
test device (different signature means uninstall-first if the original was present).

LSPatch is the no-root path; LSPosed is the root path. The module and the DexKit queries inside it
are identical either way.

## Frida: no-persistence instrumentation

[Frida](https://github.com/frida/frida) attaches to a process and runs JavaScript to hook, trace, and dump,
with nothing left installed. Good for:

- Quick, exploratory tracing without building a module (`frida-trace`, interactive REPL).
- Dumping decrypted DEX or strings from memory (useful against string encryption and packers,
  under authorization).
- Bypassing a protection *only when the engagement authorizes it* and documenting it as a
  finding, for example SSL-pinning bypass to see traffic you are allowed to see.

Root runs a `frida-server`; non-root uses a gadget injected into a repackaged in-scope app (the
same idea as LSPatch, different payload).

## Choosing between them

| Situation | Reach for |
|---|---|
| Find an obfuscated member by string/shape/relationship at runtime | DexKit (inside a module or gadget) |
| Persistent, structured instrumentation on a rooted test device | LSPosed module |
| Same, but no root allowed | LSPatch + the same module |
| Quick exploration, memory dumps, one-off traces, no install | Frida |

All of them serve Stage E's real job: **correlate static and runtime.** You formed a hypothesis by
reading apktool output; here you prove or kill it against the live app, in scope, with the result
written to the engagement log.
