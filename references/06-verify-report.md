# Stage F: Verify and report

Everything up to here produced candidate findings. This stage turns them into a report you would
be willing to put your name on: each finding re-proven, ranked, and written up with its evidence
and a fix.

## 1. Verify before you claim

A finding you cannot reproduce on demand is not a finding yet. Before anything goes in the
report, run it again, cleanly.

- **Static findings** (a hardcoded secret, an exported component, a cleartext flag): re-open the
  exact file and line, confirm the string or attribute is still there and means what you said.
  Quote it.
- **Dynamic findings** (a reachable deep link, a token in cleartext, a signer using a constant
  key): reproduce the action from a known starting state and capture fresh evidence (a logcat
  excerpt, a screenshot, a captured request, a file dump). If it only worked once and you cannot
  make it happen again, say so and downgrade or drop it.

This is the discipline that keeps the report honest. "It probably does X" and "I saw it do X
once" are not the same as "here is X reproduced with this evidence". Downgrade anything that does
not survive a second run; drop anything that evaporates.

Record the verification status against each item in the findings ledger: `confirmed`,
`downgraded`, or `dropped`, with the evidence path.

## 2. Rank by severity

Rank on impact times likelihood, or map to whatever rubric the engagement expects (CVSS, or a
simple Critical / High / Medium / Low / Info scale). Keep it defensible, not dramatic.

- **Impact**: what an attacker gains (account takeover, data disclosure, privilege escalation,
  denial of service, information leak).
- **Likelihood**: how reachable it is (remote and unauthenticated beats local-and-needs-root;
  an exported component beats one that needs a crafted companion app; a hardcoded third-party key
  with wide scope beats one that is already public or useless).

A hardcoded backend admin key reachable from an exported component is Critical. A verbose log
line that leaks a non-sensitive internal id is Info. Say why each sits where it does.

## 3. Write the report

Build it from two sources you already have:

- **The engagement log** (`templates/engagement-log.md`) is your methodology and scope section.
  It already records the authorization, the target, the environment, and the actions you took.
  That is not boilerplate; it is what makes the work auditable and reproducible.
- **The findings ledger** is the body.

Use `templates/report.md`. Its shape:

1. **Summary** - what was assessed, the headline results, the count by severity.
2. **Scope and methodology** - lifted from the engagement log: target, authorization basis,
   what was and was not in scope, tools and versions, device.
3. **Attack surface** - the picture from Stage B: exported components, permissions, deep links,
   network posture. Orient the reader before the findings.
4. **Findings** - one per item, ranked most severe first. Each: title, severity and why, where
   (file + line, or endpoint, or component), evidence, reproduction steps, and remediation.
5. **Remediation summary** - the fixes collected in one place, so a developer can work the list.
6. **Appendix** - tool versions, artifact hashes, anything long.

## 4. How much exploit detail

Default to **class of problem plus location**: name the weakness and point at exactly where it
is, with enough evidence to prove it and enough direction to fix it. For example: "the session
token is stored in cleartext in `shared_prefs/auth.xml`, readable by any process with the app's
uid or by a backup", with the relevant line and a note on how you read it.

Give full step-by-step exploit detail only when the engagement explicitly asks for it (some
pentest deliverables want a working proof of concept). Even then, keep secrets as class and
location, not pasted in full, and keep it inside the authorized scope.

If the finding is a security vulnerability class, describe the class and the fix, not a weaponized
recipe for use against systems outside scope.

## 5. Remediation, concretely

Pair every finding with an actionable fix, not just "this is bad":

| Finding class | Typical remediation |
|---|---|
| Hardcoded secret | Move to a server-side exchange or the device keystore; rotate the exposed secret |
| Cleartext storage of a token | Use `EncryptedSharedPreferences` / the Keystore; do not persist long-lived secrets |
| Exported, unprotected component | Set `exported=false`, or guard with a signature-level permission and validate all input |
| Cleartext traffic | Enforce HTTPS, set a strict `networkSecurityConfig`, remove `usesCleartextTraffic` |
| Broken or absent cert pinning | Pin correctly, and fail closed |
| Debuggable release | Ship with `debuggable=false` |
| Weak deep-link handling | Validate and authorize every deep-link path; do not trust the URI |

Close the report by confirming the verification status of each finding, so the reader knows every
item in it was reproduced, not assumed.
