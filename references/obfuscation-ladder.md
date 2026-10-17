# The obfuscation ladder

Apps sit on a spectrum from "real names, read it like source" to "packed, encrypted, and actively
fighting you". Work out which rungs a target is on, because that decides your tactics for Stage C
and often pushes work into Stage E.

For each rung: how to **detect** it, and the **tactic**. One theme runs through all of them, and
it is the core habit from `SKILL.md`: **resolve by shape, not by name.** Names are the first thing
obfuscation takes away; strings, resource names, method shapes, class relationships and JSON keys
are what survive.

A second theme for the protective rungs: **document a protection as a finding, do not treat
defeating it as the goal.** Bypassing anti-tamper, pinning, or root detection is only in scope
when the authorization explicitly covers it, and even then it is reported, not silently removed.

---

## Rung 0: none or light

**Detect.** Real class and method names (`com.example.auth.TokenStore.refresh`), readable string
literals, a clear package structure.

**Tactic.** Read it directly. Grep for the feature's strings and resource names, follow the call
graph, done. Most of your effort goes into understanding behaviour, not fighting the binary.

---

## Rung 1: name obfuscation (R8 / ProGuard)

**Detect.** Classes and methods renamed to `a`, `b`, `X.0aB`, single letters and short tokens in
an `X` package; no human-meaningful names; the ProGuard/R8 mapping file is not shipped (it never
is in a release you did not build).

**Tactic.** This is the main event for most large apps, and the recipe is the one to internalize.
Anchor on what did **not** get renamed:

- **String literals.** Log tags, error messages, API path fragments, analytics event names,
  internal debug strings. These are rarely obfuscated and they pin a class or method precisely.
  Build the string index (Stage B) and search it.
- **Resource names.** Layout ids, view ids, drawable and string resource names stay readable in
  the decoded resources, and the code references them. A `R.id.login_button` reference locates the
  login screen even when its class is named `q`.
- **Method shape.** Parameter types and return type, in order. "A `void` method taking
  `(Media, SomeBuilder)`" or "a static method returning `CharSequence[]`" identifies the method
  across versions even as its name churns.
- **Superclass and interface.** `X.0dJg` is meaningless, but "the subclass of the class holding
  the `IgFeedVideoPlayer` string" is stable. Walk `.super` and `.implements` relationships.
- **JSON keys.** Serializers and model classes are renamed, but the wire JSON keys
  (`reel_mentions`, `story_link_stickers`, `expiring_at`) are part of the protocol and do not
  change. Find the getter guarded by a given JSON key rather than by name.

See `03-static-understanding.md` for how these anchors drive the behaviour map. The payoff: an
analysis anchored this way keeps working when the app updates and every name shifts. One anchored
on `X.05fU.A0M` breaks on the next build.

Note too that **the same logical action can be handled by different methods in different code
paths** (for example a `static` helper for one case and an instance method for another). When one
anchor finds several candidates, hook or check them all and let runtime tell you which fires,
rather than picking by name.

---

## Rung 2: string encryption

**Detect.** Almost no readable literals in the string index, yet the app clearly uses URLs, keys,
and tags. One small method (or a few) is called from everywhere, taking an int or a byte array and
returning a `String`. That is the decryptor.

**Tactic.** Do not try to reimplement the decryptor from the smali and guess plaintexts; that is
slow and error-prone. Recover the plaintext **dynamically**: hook the decrypt method (Stage E) and
log its return value, ideally alongside the caller, so you learn both the plaintext and where it
is used. The encrypted form is static; the plaintext exists the moment the app runs.

---

## Rung 3: reflection and dynamic loading

**Detect.** Calls into `Class.forName`, `getMethod`/`getDeclaredMethod`, `invoke`,
`DexClassLoader`/`PathClassLoader`; target names assembled at runtime (often from the encrypted
strings of rung 2) rather than written literally.

**Tactic.** The static tree will not show you the target of a reflective call whose name is built
at runtime. Trace it live: hook the reflection entry points and log the class and method names
being resolved and invoked. Now you know what the indirection actually reaches.

---

## Rung 4: packing (encrypted DEX)

**Detect.** A thin outer app whose real code is not in the visible DEX; a large encrypted blob in
`assets/` or `lib/`; a custom `Application` class that loads a DEX at startup; little meaningful
logic in what apktool decoded.

**Tactic (authorization-gated).** The real DEX is decrypted into memory at runtime. Under explicit
authorization, dump the decrypted DEX from the running process (from memory, or by hooking the
class loader as it loads), then decode that with apktool and analyse it like any other DEX.
Without authorization to run and instrument the app, you document that it is packed and stop.

---

## Rung 5: native stubs and JNI logic

**Detect.** Key logic is missing from the Java/smali side; `native` method declarations; `.so`
libraries in `lib/<abi>/`; `System.loadLibrary` calls. Crypto, signing, and anti-tamper often live
here specifically to be harder to read.

**Tactic.** Inspect the native libraries: `readelf` and `strings` for a first look (exported
symbols, embedded strings, obvious constants), then a disassembler (radare2, Ghidra, or similar)
for the logic. Trace across the JNI boundary: which Java `native` method maps to which native
function, what crosses in each direction. Confirm behaviour dynamically by hooking at the JNI
boundary when the engagement allows.

---

## Rung 6: anti-analysis protections

These are protections, not obfuscation of logic: root detection, debugger and emulator detection,
tamper/signature checks, and TLS certificate pinning. They exist to stop exactly the dynamic work
in Stage E.

**Detect.** Startup checks that read `su` paths, build props, debugger flags, or the app's own
signature; the app refusing to run, crashing, or behaving differently under a proxy, on an
emulator, on a rooted device, or when repackaged. Pinning shows up as TLS failures the moment you
insert your proxy CA.

**Tactic.** First and always: **document the protection as a finding** (or as a constraint on the
assessment). It is part of the app's security posture and belongs in the report either way.

Only when the authorization explicitly covers it do you work around a protection to continue
testing, and then you report both the protection and that you bypassed it for the engagement. The
goal is to assess the app, not to produce a reusable bypass. Never frame defeating a protection as
the objective, and never do it against a system you are not authorized to test.

---

## Putting it together

A heavily obfuscated app is usually several rungs at once: R8 names, encrypted strings, some
native logic, and pinning. Identify which rungs apply early, because it tells you how much of the
answer lives in static reading versus how much you will only get at runtime in Stage E. The more
rungs, the more the work shifts to "anchor statically, confirm dynamically", which is the whole
shape of this pipeline.

The runtime half of every tactic above (resolving a renamed or moved member by query, hooking a
decrypt routine, logging reflection targets, dumping DEX from memory) is covered in
`07-runtime-resolution-instrumentation.md`: DexKit for resolving by string/shape/relationship, and
the Xposed API via LSPosed (root) or LSPatch (no root), or Frida, for the hooks. All of it stays
authorization-gated per `00-authorization.md`.
