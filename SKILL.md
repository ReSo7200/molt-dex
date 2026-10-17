---
name: molt-dex
description: >-
  Reverse-engineer and assess Android apps, from unobfuscated to heavily obfuscated, using a
  staged, evidence-first pipeline built on apktool, adb and scrcpy. Use when the user wants to
  understand how an APK is built, what it does, where its secrets and misconfigurations are, or
  wants to drive an app on a device to observe its behaviour. Dynamic testing (anything that
  touches a running system or backend) is authorization-gated and must be in scope.
---

# molt-DEX

A pipeline for taking an Android app from "here is an APK (or an installed package)" to "here is
how it is built, how it behaves, and where its weaknesses are." It works on a spectrum from plain
apps to ones with name obfuscation, string encryption, packing and anti-tamper.

It reasons over **apktool**-decoded smali and resources (not a Java decompile), confirms on a
device with **adb** + **scrcpy**, and cites evidence for every claim.

## Before anything: what kind of work is this?

Load `references/00-authorization.md` first, every session. The line that matters is not "static
vs dynamic", it is **self-contained work vs reaching other people's systems**:

- **Static analysis** of an artifact the user supplied: always fine. (`local_allowed`)
- **Local modding and on-device analysis** on your own device and account, installing, driving
  the UI, instrumenting with Frida / LSPosed / LSPatch, and building a module that changes how
  your own copy behaves: fine, no pentest authorization needed. This is how the Instagram work
  was done. (`local_allowed`)
- **Assessment of a target** that reaches beyond your own instance (sending crafted traffic to
  backends to test them, probing another account, a pentest / VA you were engaged for): **gated**.
  State the target, basis, and scope, and record it in an engagement log. (`assessment_allowed`)

Refuse, regardless of stated purpose: touching accounts/data that are not the user's own and not
in authorized scope, hitting backends you do not own and are not authorized to test, harvesting
third-party credentials, or building something to harm others. Modding your own app on your own
device is not any of these.

This skill needs no credentials and reads none from the user's machine. Every mention of secrets,
tokens, or keys below refers to *finding them inside the target app being analysed* (Stage D), not
to collecting the user's own. There is nothing here to put behind a `user_config` option, because
the skill asks the user for nothing sensitive.

## Core principles

1. **Evidence over claims.** Every finding cites a smali file + method, a string-table hit, a
   logcat line, a screenshot, or a captured request. Never "it probably does X".
2. **Resolve by shape, not by name.** Obfuscated names change every build. Anchor on things that
   do not: literal strings, resource names, method signatures and shapes, superclass chains,
   JSON keys. This is the single most important habit; it is what makes analysis survive version
   bumps.
3. **Stage the work, cache between stages.** Decode once, index once, reuse. Keep a per-target
   working directory and a findings ledger.
4. **Fail soft and say so.** A lookup that misses reports what it tried; it never fabricates.
5. **Static first, dynamic to confirm.** Read code to form a hypothesis, then prove or kill it on
   the device. Correlating the two is a first-class step.
6. **Human-paced device loop.** Screenshot, read, act, screenshot. Stay in scope; never touch
   other people's content.

## The pipeline

Run the stages in order; each writes to the working dir and the findings ledger, and each is
resumable. Load the matching reference page when you start a stage.

The "needs" column: `local` = your own device/app/account, always fine; `assessment` = only when
an action reaches a backend or another user's data (see category 3 in `00-authorization.md`).

| Stage | Page | What it does | Needs |
|---|---|---|---|
| A. Acquire & identify | `references/01-acquire.md` | Get the artifact (local / pulled / bundle), record identity, hashes | local |
| B. Decode & inventory | `references/02-decode-inventory.md` | apktool decode, string index, manifest & attack surface | local |
| C. Static understanding | `references/03-static-understanding.md` | Entry points, data flow, network layer, behaviour map | local |
| D. Secrets & misconfig | `references/04-secrets-misconfig.md` | Hardcoded secrets and misconfiguration sweep | local |
| E. Dynamic analysis | `references/05-dynamic-analysis.md` | Install on your device, drive with scrcpy+adb, logcat, instrument, correlate | local; **assessment** only if you probe backends / other accounts |
| F. Verify & report | `references/06-verify-report.md` | Re-prove each finding, write the report | local |

Supporting references, loaded when relevant:

- `references/07-runtime-resolution-instrumentation.md` - resolving obfuscated members at runtime
  with **DexKit**, the **Xposed hooking API** (before/after/replace, `setResult`, reflection
  helpers), and the frameworks that provide it: **LSPosed** (root), **LSPatch** (no root), plus
  **Frida**. This is the bridge from static shape to live confirmation.
- `references/obfuscation-ladder.md` - the none -> name -> string -> packer playbook and detectors.
- `references/tooling-setup.md` - installing and sanity-checking apktool, adb, scrcpy and friends.
- `references/device-loop.md` - the scrcpy + adb screenshot/act loop in detail, with gotchas.

Templates:

- `templates/engagement-log.md` - the authorization + action record (also the report's method).
- `templates/report.md` - the final findings report.

Scripts (helpers, see `scripts/`): acquire, build-string-index, manifest-summary, secrets-sweep,
device helpers. They are conveniences; the pipeline works by hand without them.

## Tooling, in one line

apktool (decode/rebuild, **not** JADX), adb (device), scrcpy (mirror + control), ripgrep +
a string index (anchoring), a disassembler for native `.so`, a proxy for traffic (in scope),
apksigner (re-pack testing). JADX is an optional read-only convenience only.

## Untrusted-artifact hygiene

Every downloaded APK/bundle is untrusted input. Put each in its own empty directory, keep your
scripts elsewhere, pass paths as arguments, and never run an interpreter or build tool from
inside the artifact's directory. Run analysis scripts that read artifacts with the interpreter's
isolated mode where available.
