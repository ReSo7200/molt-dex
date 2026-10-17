<div align="center">
  <h1>molt-DEX</h1>
  <p><b>A staged, evidence-first skill for reverse-engineering and assessing Android apps.</b><br/>
  From plain APKs to heavily obfuscated ones, built on apktool, adb and scrcpy.</p>
</div>

---

## What it is

molt-DEX is a [Claude skill](https://docs.claude.com/en/docs/claude-code/skills): a packaged
pipeline that takes an Android app from "here is an APK" to "here is how it is built, how it
behaves, and where its weaknesses are."

It is designed for the full obfuscation spectrum, plain apps, R8/ProGuard name obfuscation,
string encryption, packing and anti-tamper, and it leans on a single habit that makes analysis
survive app updates: **resolve by shape, not by name.** Anchor on strings, resource names, method
shapes and class relationships, never on obfuscated identifiers that change every build.

It reasons over **apktool**-decoded smali and resources rather than a Java decompile, confirms
findings on a real device with **adb** and **scrcpy**, and cites evidence for every claim.

## Authorization first

The line that matters is self-contained work vs reaching other people's systems, not static vs
dynamic:

- **Static analysis** of an artifact you supply (your own app, an in-scope target, a CTF binary, a
  lab app) is always fine.
- **Local modding and on-device analysis** on your own device and account, installing, driving the
  UI, instrumenting with Frida / LSPosed / LSPatch, and building a module that changes how your own
  copy behaves, is fine and needs no pentest authorization. This is how the Instagram module was
  built.
- **Assessment of a target** that reaches past your own instance (testing a backend with crafted
  traffic, probing another account, a pentest or VA you were engaged for) is **gated**: state the
  target, basis, and scope, recorded in an engagement log.

It refuses, regardless of stated purpose, to touch third-party accounts or data, to hit backends
you are not authorized to test, to harvest credentials, or to build something to harm others. See
[`references/00-authorization.md`](references/00-authorization.md).

## The pipeline

| Stage | What it does |
|---|---|
| A. Acquire & identify | Get the artifact (local, pulled from a device, or an `.apkm`/`.xapk`/split bundle), record identity and hashes |
| B. Decode & inventory | apktool decode, build a string index, parse the manifest and map the attack surface |
| C. Static understanding | Entry points, data flow, network layer, and a behaviour map |
| D. Secrets & misconfig | Sweep for hardcoded secrets and misconfiguration |
| E. Dynamic analysis | Install on your device, drive with scrcpy + adb, instrument, correlate against the static model (local; gated only if you probe backends or other accounts) |
| F. Verify & report | Re-prove each finding and write the report |

See [`SKILL.md`](SKILL.md) for the full map and [`references/`](references/) for each stage.

## Tooling

[apktool](https://apktool.org/) (decode/rebuild, not JADX), the Android platform-tools
([adb](https://developer.android.com/tools/adb)), [scrcpy](https://github.com/Genymobile/scrcpy)
(mirror + control), ripgrep, a disassembler for native libraries, a proxy for traffic, and
apksigner for re-pack testing. JADX is an optional read-only convenience only.

See [`references/tooling-setup.md`](references/tooling-setup.md).

## Layout

```
SKILL.md                      entry point: the gate, principles, pipeline map
references/
  00-authorization.md         what kind of work this is: local vs assessment (read first)
  01-acquire.md               Stage A
  02-decode-inventory.md      Stage B
  03-static-understanding.md  Stage C
  04-secrets-misconfig.md     Stage D
  05-dynamic-analysis.md      Stage E
  06-verify-report.md         Stage F
  obfuscation-ladder.md       none -> name -> string -> packer playbook
  tooling-setup.md            install and sanity-check the tools
  device-loop.md              the scrcpy + adb screenshot/act loop
scripts/                      optional helpers (acquire, index, manifest, secrets, device)
templates/                    engagement-log.md, report.md
```

## Install

Copy this folder into your skills directory (for Claude Code,
`~/.claude/skills/molt-dex/`, or a project `.claude/skills/`), then invoke it by name.

## License

See [LICENSE](LICENSE).
