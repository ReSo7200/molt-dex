# Stage C: Static understanding

Goal: turn the decoded tree into a model of how the app is built, where its data lives, and how it
talks to its backend. The output is a behaviour map you can test against on the device in Stage E.

This is static work on a local file, always fine. The one technique that makes this stage possible on an obfuscated
app, resolving code by shape instead of by name, is below and is worth reading before you start.

## 1. Entry points

Start where execution starts. These are where you pick up the threads to follow.

- **Application subclass.** `<application android:name=...>` in the manifest. Its `onCreate` wires
  up the app: dependency graph, network client, analytics, crash reporting, feature flags, often
  the first place keys and base URLs appear.
- **Launcher activity.** The `<activity>` with `MAIN` / `LAUNCHER` in its intent-filter. The first
  screen and its navigation.
- **Exported component handlers.** Every exported activity/service/receiver/provider from the
  Stage B attack-surface list: these are entry points reachable from outside the app, so trace
  what each does with the intent/URI it receives.
- **`JNI_OnLoad` and native entry points.** If the app loads native libraries (`System.loadLibrary`),
  `JNI_OnLoad` in the `.so` runs at load time. Relevant when crypto, string decryption, or
  anti-tamper lives in native code (see `references/obfuscation-ladder.md`).

```bash
cd "$WORK/decoded/base"
rg -n 'android:name' AndroidManifest.xml | rg -i 'application|activity'
rg -rn 'loadLibrary|System\.load' --include '*.smali' | head
```

## 2. Data flow: where secrets and state live

Follow the data, not just the code. For each sensitive item (auth token, session, API key, device
id, user id) find where it is produced, where it is stored, and where it is read.

| Store | Look for | Notes |
|---|---|---|
| SharedPreferences | `getSharedPreferences`, `.edit()`, `putString` | plaintext XML in the app's data dir unless the app uses EncryptedSharedPreferences |
| SQLite | `openOrCreateDatabase`, `SQLiteDatabase`, `.db` assets | tokens and PII often cached here |
| Android Keystore | `AndroidKeyStore`, `KeyGenParameterSpec`, `Cipher` | the right place for keys; check whether the app actually uses it or just stores raw secrets |
| Bundled assets | `assets/`, `res/raw/` | config files, default credentials, certificates, seed data |
| Hardcoded constants | `const-string` in init code | the Stage D sweep covers these; note the ones in the data path here |

```bash
rg -rn 'getSharedPreferences|AndroidKeyStore|openOrCreateDatabase' --include '*.smali' | head
```

Note which prefs file and which keys hold what. Stage E confirms the on-device values
(`adb ... run-as` or root, reading the data dir).

## 3. Network layer

How the app reaches its backend is usually the richest surface.

- **Base URLs and endpoints.** Search the string index for `https://`, API hostnames, path
  fragments. Endpoint builders are often one class that assembles paths.
- **Auth header construction.** Find where `Authorization`, a bearer token, an HMAC signature, or
  a custom header is added. This is where request-signing secrets show up and where you learn how
  to replay or forge a request (in scope).
- **Certificate pinning.** The app may pin to defeat proxying:
  - OkHttp `CertificatePinner` (`.add(` with `sha256/...` pins),
  - a custom `X509TrustManager` / `HostnameVerifier`,
  - pins declared in `res/xml/network_security_config.xml` (`<pin-set>`).

```bash
grep -F 'https://' "$WORK/notes/strings.tsv" | sort -u | head
rg -rn 'CertificatePinner|X509TrustManager|HostnameVerifier' --include '*.smali'
rg -n '<pin-set|<domain-config|cleartextTrafficPermitted' decoded/base-full/res/xml/*.xml 2>/dev/null
```

Record each pin location. Stage E decides how to handle pinning (user-CA trust if the config
allows it; otherwise a documented runtime bypass, only under authorization).

## 4. The central technique: resolve by shape, not by name

On an obfuscated build a method is named `A0M` on one class called `X.05fU`, and both names change
next release. You cannot search for the name. You search for what does not change, then confirm the
shape.

Four stable anchors, best first:

1. **A literal string the method uses.** A log tag, a QPL marker, an error message, a JSON key.
   This is why the string index exists. One `grep` gives you file + method.
2. **The method's shape.** Parameter types, return type, static vs instance, parameter count.
   "The `(Media, ...) -> boolean` method on this class", "the paramless `-> List` getter", "the
   `(Context, OnClickListener, String, int) -> void` adder". Shapes survive renames.
3. **The declaring class's relationships.** Its superclass, the interface it implements. "The
   class that extends the one holding this string", "the implementors of this interface".
4. **A stable data key.** A JSON field name the method parses (`"reel_mentions"`, `"story_cta"`).
   App protocols keep their wire keys stable across builds even when code is renamed.

### Worked example (Instagram, obfuscated)

Find the feed video player's "start playing this media" method, so you can hook playback:

- **Step 1, anchor on a string.** The player class logs a unique line. Search the index:

  ```bash
  grep -F 'IgFeedVideoPlayer: Persistent Visible Cover Image' "$WORK/notes/strings.tsv"
  # -> smali_classesN/X/05fU.smali   <clinit or a method>   "IgFeedVideoPlayer: ..."
  ```

  That pins the player class, `X.05fU`, by a string that cannot be renamed away.

- **Step 2, find the method by shape.** The start method is not named anything meaningful; it is
  the instance method that takes a `Media` and returns `boolean`:

  ```bash
  rg -n '^\.method .*\(Lcom/instagram/feed/media/Media;.*\)Z$' decoded/base/smali*/X/05fU.smali
  # -> A0M(Lcom/instagram/feed/media/Media; ... )Z
  ```

  You matched it by its signature, not its name.

- **Step 3, follow relationships when the code moves.** In a later build the player class became a
  base class and the start method moved to a subclass. The string still anchored the base class;
  to find the real method you searched for classes whose superclass is that base and checked each
  for the same `(Media, ...)Z` shape:

  ```bash
  rg -ln '^\.super LX/05fU;' decoded/base/smali*     # subclasses of the anchored base
  # then grep each for the (Media,...)Z method
  ```

  Same anchor, one more hop, no reliance on a single name.

### The recipe, generalized

1. Pick a stable anchor you can see from outside: a string in the UI/logs/docs, or a wire key.
2. `grep` the string index to land on a class/method.
3. Confirm you have the right one by its shape (params, return, static/instance) and its role.
4. If the exact method is not on the anchored class, climb the relationships: its superclass,
   subclasses, implemented interfaces, or the callers/callees of a nearby method.
5. Write down the anchor you used, not the obfuscated name. Next release you re-run the anchor;
   the name you wrote down would be stale. (This is the difference between analysis that survives
   an app update and analysis that breaks on the next one.)

For string encryption, packing, and other rungs where even strings are hidden, see
`references/obfuscation-ladder.md`. Where static reading runs out, confirm the hypothesis at
runtime: `references/05-dynamic-analysis.md`.

The same "anchor by string/shape/relationship" recipe runs at runtime with **DexKit**, which
queries the loaded app for a member matching that description and returns the real `Method` for
this build (and follows a method that moved by querying subclasses of the anchored class). That is
also where you hook it with the **Xposed API** (LSPosed for root, LSPatch for no root) or Frida to
log its arguments and confirm the shape you inferred: see
`references/07-runtime-resolution-instrumentation.md`.

## 5. The behaviour map

Pull it together into one table in the ledger: component to behaviour to data to endpoint.

| Component | What it does | Data it touches | Endpoint / sink |
|---|---|---|---|
| `LoginActivity` | credential entry | writes session token to `prefs/auth.xml` | `POST /api/v1/login`, bearer added in `ApiClient` |
| exported `ShareReceiver` | handles share intents | reads clipboard, user id | `POST /api/v1/share` |
| `FeedVideoPlayer` (anchored by string) | plays feed video | media id | video CDN URL from `video_versions` |

The map is the thing you hand to Stage E to confirm ("does `ShareReceiver` really trust the intent
extra?") and the skeleton of the Stage F report.

## Done when

- Entry points listed.
- Sensitive data stores and their keys identified.
- Network base URLs, auth construction, and pinning located.
- A behaviour map in the ledger, with anchors (strings/shapes), not obfuscated names, recorded for
  each located method.

Next: `references/04-secrets-misconfig.md`, then confirm on device with
`references/05-dynamic-analysis.md`.
