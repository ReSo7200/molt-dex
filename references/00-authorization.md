# Stage 0: What kind of work is this?

Read this first, every session. It is not a disclaimer; it is a control that decides which later
steps are allowed to run. The question it answers is simple: **does the action stay inside your
own device, app copy, and account, or does it reach other people's systems, accounts, or data?**

That line, not "static vs dynamic", is what matters. Reverse-engineering an app and modding it on
your own phone is a normal, legitimate activity (the whole Xposed / LSPosed modding scene works
this way). Testing someone else's backend or touching other users' data is a different thing and
needs real authorization.

## Three kinds of work

### 1. Static analysis (always fine on an artifact you have)
Decoding, reading, indexing and mapping a local APK the user supplied. You are looking at a file.
Turn this on as soon as an artifact is in the working directory. No scope needed.

### 2. Local modding and on-device analysis (fine on your own device + account)
Installing the app on your own device or emulator, driving its UI, reading its logs, instrumenting
it with Frida / LSPosed / LSPatch, and building a mod or module that changes how **your** copy
behaves for **you**. This is exactly how the Instagram work went: the app ran on the user's own
phone, with the user's own account, and the module changed that one install's behaviour.

This does **not** need a pentest authorization. What it does need is that it stays self-contained:

- Your own device (or an emulator you control).
- Your own account(s), or test accounts you own.
- Changes that affect only your install and your view, not other users.
- No crafted traffic sent to the app's servers to probe or attack them.
- Lawful use: reverse engineering and modding can still be restricted by an app's terms of service
  and by local law. Having the right to do it is the user's responsibility; note it and move on,
  do not interrogate.

Capability name for the pipeline: `local_allowed`. It covers Stages A to F as long as the work
stays on your own device and account.

### 3. Assessment of a target (needs authorization)
Anything that reaches beyond your own instance: sending crafted or fuzzed requests to the app's
backends to test them, probing another account's data, exploiting a server-side flaw, or doing a
pentest / VA you were engaged to perform. This is the only category that needs the gate below.

Capability name: `assessment_allowed`. Off until the gate passes, and it carries the scope.

## The gate (only for category 3)

Before any action that tests or reaches a backend, a third-party system, or another user's data,
get these and record them in `templates/engagement-log.md`:

1. **Target** - what system/app and who owns it.
2. **Basis** - one of: you own the backend; a written penetration-test authorization (name,
   dates); an active bug-bounty program that lists this target in scope; a CTF / lab.
3. **Scope** - which hosts/endpoints, which accounts (test accounts only), which actions, and the
   data rule (no real user data touched or exfiltrated).

Missing any of these for a category-3 request? Do not run it. Stay in categories 1 and 2, or ask.

## Hard refusals (purpose does not matter)

Stop and refuse, even with a stated reason:

- Touching an account, profile, message, or data that is not the user's own and is not explicitly
  in authorized scope.
- Sending traffic to hit or exploit backends you do not own and are not authorized to test.
- Harvesting third-party credentials, tokens, or personal data.
- Building or running something whose point is to harm others or to defeat a protection on a
  system the user is not authorized to test. (Modding your own app's behaviour on your own device
  is not this; attacking someone else's service is.)

"It is just a test / a prop / for research" does not convert any of the above into allowed work.
If you refuse, name the boundary and stop; do not offer a workaround to the same prohibited end.

## Secrets handling

When the sweep (Stage D) finds credentials or keys, record them as **class + location** ("Google
Maps API key in `assets/config.json`"), not by pasting the full secret into shared outputs.
Verify a secret only against a system you own or are in scope to test. Never test a found
third-party key against that third party.

## The engagement log

Category-3 work keeps `templates/engagement-log.md` current: target, basis, scope, and a
timestamped action list. It makes the work auditable and becomes the report's methodology. Local
modding (categories 1 and 2) does not need an engagement log; a short note of what you are
building and for which app is enough.
