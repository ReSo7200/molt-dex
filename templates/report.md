# Android app assessment: <APP NAME> <VERSION>

- **Package:** `com.example.app`
- **Version:** versionName / versionCode
- **Date:** YYYY-MM-DD
- **Analyst:**
- **Assessment type:** static only / static + dynamic

---

## 1. Scope and authorization

Pulled from `templates/engagement-log.md`.

- **Basis:** (own app / written PT authorization <name, dates> / in-scope bounty <program URL> / CTF / lab)
- **In scope:** (hosts, endpoints, components, accounts)
- **Out of scope:**
- **Data rule:** test accounts only; no real user data touched or exfiltrated.

---

## 2. Summary

Two or three sentences: what the app is, what was assessed, and the headline result.

| Severity | Count |
|----------|-------|
| Critical |       |
| High     |       |
| Medium   |       |
| Low      |       |
| Info     |       |

---

## 3. Methodology

From the engagement log. The pipeline that was run:

- **A. Acquire:** how the artifact was obtained (local / pulled / bundle), hashes.
- **B. Decode & inventory:** apktool decode, string index built, manifest parsed.
- **C. Static understanding:** entry points, data flow, network layer, behaviour map.
- **D. Secrets & misconfig:** sweep results.
- **E. Dynamic (if run):** device, how the app was driven, what was observed (logcat, traffic).
- **F. Verify:** each finding re-proved before inclusion.

Obfuscation level: none / name (R8-ProGuard) / string encryption / packing / anti-tamper.
Note how anchors were chosen (strings, resource names, method shapes) rather than obfuscated names.

---

## 4. Attack surface

- Exported components and whether each is guarded by a permission.
- Deep-link schemes and hosts.
- Content-provider authorities and URI-permission grants.
- Flags: debuggable, cleartext traffic, allowBackup, network-security-config.
- Backend endpoints and how the app authenticates to them.

---

## 5. Findings

| ID | Title | Severity | Component / location | Evidence | Status |
|----|-------|----------|----------------------|----------|--------|
| F-01 |  |  |  | `evidence/...` | Verified / Plausible |
| F-02 |  |  |  |  |  |

### F-01 <title>

- **Severity:** Critical / High / Medium / Low / Info
- **Component / location:** exported activity / `assets/config.json` / `X.0aB.smali:142` / endpoint
- **Description:** what the weakness is, in plain terms.
- **Impact:** what an attacker gains, under what preconditions.
- **Evidence:** the smali method + string anchor, the manifest line, the logcat line, the
  screenshot or captured request. Reference paths under `evidence/`. Keep secrets as
  class + location, not pasted in full.
- **Reproduction:** the minimal steps or shape that triggers it, at the class + location level.
- **Remediation:** the concrete fix (set `exported="false"`, add a permission, move the secret
  server-side, enforce pinning, remove cleartext, and so on).

### F-02 <title>

(repeat)

---

## 6. Appendix

- **Tooling versions:** apktool, adb, scrcpy, ripgrep, aapt/aapt2, apksigner.
- **Artifact hashes:** sha256 of base.apk and each split.
- **Working directory:** `work/<target>/` layout (input, decoded, evidence, findings.md).
- **Signing certificate:** issuer / subject / SHA-256 fingerprint.
