# Reviewer Capability Interface (RCI) — design spec

| | |
|---|---|
| **Status** | Draft (for review) |
| **RCI schema version** | 1.0 (proposed) |
| **Author** | Logan Rooks |
| **Created** | 2026-06-07 |
| **Last revised** | 2026-06-08 — codex signal model corrected against live data (§18: trigger non-determinism, feedback verified, no check-run); open questions resolved (§17) |
| **Supersedes** | nothing (additive to the existing `reviewer_profiles` system) |

> This is a design document, not yet an implementation. It defines the contracts
> and semantics; the phased rollout in §16 sequences the code. Example JSON blocks
> are illustrative of shape, not a frozen JSON Schema (that comes in Phase 1).

---

## 1. Problem

The package already models the **journal side** of reviewer behaviour: how to
parse a finding, attribute it to a reviewer, extract severity, and infer a
disposition (`reviewer_profiles` in `tools/review-journal/review_journal.py`,
with `severity_patterns` / `auto_resolve_patterns` / `inference_rules`). That
half treats reviewer behaviour as **config, not code**, and it works.

It does **not** model the **live side**:

1. **Signal detection** — "is a review running?", "did it post findings?", "is
   it clean?". These are reverse-engineered ad hoc each session.
2. **Feedback** — the bot solicits a reaction (Codex: "Useful? React with 👍 /
   👎"); nothing in the package records or sends that.
3. **Triggering** — "does this reviewer auto-re-review on push, or must I ask?"

The gap is not cosmetic. `skills/pr-review-triage/references/monitoring.md`
Pattern 1 originally waited for a reviewer's **review count to increment** — a
count is fragile (thread-reply review objects inflate it → false triggers) and
key-on-count misses the SHA the review actually targets. The fix (§11) keys on
the pushed commit SHA and the persistent **review object**, with a timeout.

This spec adds the live side **as data, with the same config-not-code ethos**,
and—because the tool is becoming public-facing—promotes the relevant formats to
**versioned public contracts**.

## 2. Stakeholders

The design serves a deliberate (not exhaustive) set:

| Stakeholder | Need | What it demands of the design |
|---|---|---|
| **First user / orchestrator** | Triage + convergence + audit that works now, zero-config | Simple write-path; defaults always work |
| **Workflow builders** (custom bot / Actions) | Plug in their own reviewer | Profile/adapter schema is a **public, versioned contract** + conformance kit |
| **Evaluators** (compare reviewers) | Apples-to-apples metrics across bots | **Normalized severity + canonical categories**, captured at source |
| **Operators** (how's my setup doing) | Trends over time | Analytics output is a **stable, documented format** |
| **Future platform** (UI, analysis, experiments) | Aggregate many journals; attribute outcomes to setups | **Self-describing, exportable records + config/policy provenance** |

## 3. Design principles

1. **The files are the API.** The journal JSON, the profile schema, and the
   analytics output are the public surface. Every consumer — this CLI, a third-
   party dashboard, a researcher's notebook, a future UI — reads the same files.
2. **Three versioned contracts** (§5), each semver'd with its own codebook.
3. **Declarative observation, executable action.** Detecting a signal is a pure
   predicate over fetched GitHub data → declarative (like `severity_patterns`).
   Performing an action (react / trigger / resolve) is effectful and shape-
   varying → a thin executable hook, with a declarative default for the common
   case. (Functional core / imperative shell.)
4. **Capability negotiation with a safe generic fallback.** Each profile
   declares which capabilities it supports; an unknown reviewer degrades to the
   forge-native universals and **marks the rest unknown** — it never guesses
   (§6.4, §10).
5. **Verify before you trust.** A signal is `verified: true` only with a backing
   fixture (§12). Signals that can't be reproduced from history (live-only
   reactions) stay `verified: false` and the orchestrator must not *depend* on
   them — it falls back to a persistent signal or a checkpoint. (This rule
   caught a wrong `clean` mechanism in this very spec — see §18.)
6. **Ledger of decisions, not a mirror of conversations.** Store the derived
   disposition + a URL back to the thread, not the raw chat.
7. **Propose-and-confirm for anything self-modifying.** Inference, rule
   synthesis, profile calibration: the tool *proposes*; a human/agent confirms.
8. **Read-models are separate consumers**, never new responsibilities of `sync`.
9. **`extras`-first, promote later.** Prototype new data in the per-thread
   `extras` escape hatch; promote to a validated field once proven.
10. **Progressive disclosure / local-first.** Zero-config keeps working; data
    lives in the owner's repo by default (privacy posture, not just simplicity).
11. **One-way vs two-way doors.** Get right now only what is irreversible *and*
    cheap, or unrecoverable-if-deferred (§15). Defer the rest with a trigger.

## 4. Naming

A bot is a **black box we observe**, not a system that implements our interface.
We author a **profile** (a declarative *capability descriptor* / adapter) per
reviewer. "RCI" = the contract those profiles target plus the semantics an
orchestrator follows when consuming them.

## 5. The three contracts (overview)

- **Contract A — Reviewer profile / capability schema** (§6). For builders.
  Extends today's `reviewer_profiles`. `rci_version`.
- **Contract B — Journal record schema** (§7). For evaluators / researchers /
  platform. Extends today's `pr-N.json`. `schema_version` (already exists).
- **Contract C — Analytics output schema** (§8). For operators / dashboards.
  New, trivial. `analytics_version`.

Each version moves independently. Additive fields → minor bump; breaking shape →
major bump + migration note (§13).

## 6. Contract A — Reviewer profile / capability schema

A profile is one object per reviewer login, in `.review-journal.json`'s
`reviewer_profiles`. Existing fields (`kind`, `display_name`, `aliases`,
`severity_patterns`, `auto_resolve_patterns`, `inference_rules`, `notes`) are
unchanged. RCI adds: `rci_version`, `forge`, per-signal `verified`, `signals`,
`feedback`, `trigger`, and an optional `canonical` on each severity pattern.

### 6.1 Severity, now normalized at capture

Each `severity_patterns` entry gains an optional `canonical` mapping its raw
badge to the canonical scale (§9.1). Captured at sync time because the journal
only stores a 300-char excerpt — raw severity may be **unrecoverable later**.

```jsonc
"severity_patterns": [
  { "pattern": "\\bP0\\b", "severity": "P0", "canonical": "blocker" },
  { "pattern": "\\bP1\\b", "severity": "P1", "canonical": "high" }
]
```

### 6.2 Signals (declarative observation)

A signal is a predicate over fetched GitHub data, plus a `supported` flag and a
`verified` flag.

```jsonc
"signals": {
  "findings": { "supported": true, "verified": true,
    "any_of": [ {"type":"review","by":"self","title_matches":"Codex Review","commit":"head","has_inline_comments":true} ] },
  "clean":    { "supported": true, "verified": false, "any_of": [ … ] },
  "running":  { "supported": false, "verified": false }
}
```

Observation `type`s (the vocabulary a consumer implements):

| type | reads | notes |
|---|---|---|
| `review` | a PR review object | carries `state`, `commit.oid`, inline count → SHA-stampable. `commit:"head"` constrains it to the PR's current head SHA; `title_matches` filters by review title. **Preferred — persistent and verifiable.** |
| `comment` | an issue/PR comment body | `match` regex; prose-scraping is a last resort |
| `check_run` | a commit check/status | for bots that expose a check |
| `issue_reaction` | a reaction on the PR conversation | mutable, **not** SHA-stamped, and **often transient/live-only → hard to verify from history.** Stays `verified:false`; don't depend on it |
| `comment_reaction` | a reaction on a specific comment | same caveat |

`by: "self"` resolves to the reviewer's login + `aliases`. `supported:false`
declares a capability *absent* → triggers degradation (§10). Default
`supported:true`, `verified:false`.

**`verified` (normative).** Only signals with a backing fixture (§12) may be
`verified:true`. Reaction-type signals are frequently live-only and cannot be
captured from a closed PR; they stay `verified:false` and the orchestrator polls
a persistent signal (a `review` on head SHA) or falls back to a checkpoint (§10)
instead of waiting on them.

**SHA-baseline rule (normative).** Re-review detection keys on the pushed commit
SHA, never a count. `review`-type signals compare `commit.oid` to the head SHA
(`commit:"head"`). Note a reviewer may *not* re-review the final head (the head
can advance past its last review via more pushes or a merge commit) — so any
wait on a `review` signal **must be timeout-bounded** (§11).

### 6.3 Feedback and trigger (action, thin executable default)

```jsonc
"feedback": {
  "supported": true, "verified": false,
  "accept": { "type": "comment_reaction", "content": "+1", "target": "finding_comment" },
  "reject": { "type": "comment_reaction", "content": "-1", "target": "finding_comment" }
},
"trigger": { "manual": { "type": "issue_comment", "body": "@codex review" }, "manual_verified": true, "auto_on_push": "unreliable", "auto_verified": false }
```

The **default action implementation** interprets these descriptors (POST a
reaction; post a comment; re-request review). For a bot whose actions can't be
expressed declaratively, a profile may set an **escape-hatch hook**:

```jsonc
"action_hook": "adapters/mybot.sh"   // implements the fixed CLI below
```

```
<hook> detect-state   <repo> <pr> <head_sha>   -> running|clean|findings|none|unknown
<hook> list-findings  <repo> <pr>              -> JSON array of findings
<hook> react          <comment_id> accept|reject
<hook> trigger        <repo> <pr>
```
Hooks are **opt-in and security-sensitive** (arbitrary code) → §14.

### 6.4 The two reference profiles

**Codex — `findings`/`trigger` verified, `clean`/`running`/`feedback` not**
(empirically characterized on `loganrooks/philpapers-mcp` PRs #8/#9,
2026-06-08; see §18):

```jsonc
"chatgpt-codex-connector": {
  "rci_version": "1.0",
  "kind": "bot:agentic-llm",
  "display_name": "Codex (via chatgpt-codex-connector)",
  "forge": "github",
  "severity_patterns": [
    {"pattern":"\\bP0\\b","severity":"P0","canonical":"blocker"},
    {"pattern":"\\bP1\\b","severity":"P1","canonical":"high"},
    {"pattern":"\\bP2\\b","severity":"P2","canonical":"medium"},
    {"pattern":"\\bP3\\b","severity":"P3","canonical":"low"}
  ],
  "signals": {
    "findings": {"supported": true, "verified": true,
      "any_of": [{"type":"review","by":"self","title_matches":"Codex Review","commit":"head","has_inline_comments":true}]},
    "clean":    {"supported": true, "verified": false,
      "any_of": [{"type":"review","by":"self","title_matches":"Codex Review","commit":"head","has_inline_comments":false}],
      "note": "Candidate only — a zero-finding Codex review was never observed. Operational merge-readiness uses reviewer-agnostic unresolvedThreadCount==0, not this."},
    "running":  {"supported": false, "verified": false,
      "note": "👀 on the @codex trigger comment is transient/live-only; not reproducible from closed PRs. Poll for the terminal 'findings' signal instead."}
  },
  "feedback": {"supported": true, "verified": true,
    "accept": {"type":"comment_reaction","content":"+1","target":"finding_comment"},
    "reject": {"type":"comment_reaction","content":"-1","target":"finding_comment"},
    "note": "Codex solicits 👍/👎 in each finding's text. The channel is persistent + queryable: #9 carries 7 👍 + 2 👎 by the maintainer on Codex finding (review-thread) comments. Verifies the action persists; NOT that Codex ingests it."},
  "trigger": {
    "manual": {"type":"issue_comment","body":"@codex review"}, "manual_verified": true,
    "auto_on_push": "unreliable", "auto_verified": false,
    "note": "One @codex review arms the PR and reliably yields >=1 review. Auto-re-review on later pushes is NON-DETERMINISTIC: every #9 push got reviewed (minutes), none of #8's two post-fix pushes did (10.6h open before merge, same single-trigger arming, cause unknown). Do NOT wait passively for auto — re-post @codex review per push you want reviewed."},
  "notes": "VERIFIED 2026-06-08 (closed PRs #8/#9): Codex posts a COMMENTED review titled '💡 Codex Review' per pass, stamped with commit.oid; every observed pass carried inline findings. It uses NO issue comments and NO persistent self-reactions (checked issue, issue-comments, review-thread comments) and NO check-run. Verified: 'findings' (review objects), 'feedback' (persistent 👍/👎 on finding comments), 'manual' trigger. Unreliable/unverified: 'auto_on_push' (non-deterministic), 'clean'/'running' (no persistent signal found)."
}
```

**Generic fallback — conservative** (any reviewer with no registered profile;
extends today's `profile_for()` human stub to signals):

```jsonc
"__default__": {
  "rci_version": "1.0", "kind": "unknown", "forge": "github",
  "severity_patterns": [],
  "signals": {
    "findings": {"supported": true, "verified": false, "any_of": [{"type":"review","by":"self","commit":"head","has_inline_comments":true}]},
    "clean":    {"supported": false},
    "running":  {"supported": false}
  },
  "feedback": {"supported": false},
  "trigger":  {"auto_on_push": null}
}
```

`findings` (a review on head SHA with inline comments) is the **one universally
available signal** — it's forge-native thread state. `clean` is *unprovable* for
an unknown reviewer (and, notably, for Codex too — see §10) → checkpoint. CR and
Copilot profiles are reserved but unverified until observed (§12).

## 7. Contract B — Journal record additions

All additive; old journals validate unchanged (§13). New fields:

- **`severity_canonical`** (per thread) — the §9.1 level, captured at sync.
  `severity` (raw) stays.
- **`reviewer_feedback`** (per thread) — the 👍/👎 usefulness signal. **Lands in
  `extras.reviewer_feedback` first** (principle 9), promoted to a top-level field
  at schema 1.1 once proven:
  ```jsonc
  "extras": { "reviewer_feedback": { "reaction": "+1", "at": "…", "by": "agent:claude-code" } }
  ```
- **`policy`** (per file / per pass) — config + policy provenance, **the enabling
  condition for later experiments and fair comparison** (impossible to
  reconstruct after the fact). Per the §17/Q2 resolution: the authoritative
  fingerprint is over the **whole config file** (never under-inclusive — a false
  "same config" silently corrupts an experiment, which is worse than over-
  splitting), and the actual **reviewer-relevant subset is stored as a snapshot**,
  deduplicated by hash in a sidecar, so any later bucketing (by full config, by
  reviewing-subset, by a single field) is reconstructable without pre-committing
  to a brittle "what's relevant" definition:
  ```jsonc
  "policy": {
    "config_fingerprint": "sha256:…",        // hash of the WHOLE .review-journal.json
    "config_snapshot_ref": "configs/<sha>.json", // deduped copy of profiles+reviewers+rules+categories
    "reviewers_active": ["coderabbitai","chatgpt-codex-connector"],
    "tool_version": "0.2.0",
    "rci_version": "1.0"
  }
  ```
- **History completeness** — every state transition lands in `verdict_history`
  with `at` + `source` + `verdict` + (where applicable) head SHA, so a future
  platform can *reconstruct an event stream* without full event-sourcing now.
  (Minor existing gap: block-derived first verdicts aren't seeded into history;
  close it.)

## 8. Contract C — Analytics output schema

A **read-only consumer** (e.g. `review_journal.py analyze`), never part of
`sync`. Reads one or many journals; emits stable JSON + a thin text summary:

```jsonc
{
  "analytics_version": "1.0",
  "generated_at": "…",
  "scope": {"repos": ["…"], "prs": [ … ]},
  "per_reviewer": {
    "chatgpt-codex-connector": {
      "findings": 8, "accepted": 5, "accept_rate": 0.625, "false_positive_rate": 0.375,
      "by_canonical_severity": { … }, "by_category": { … },
      "severity_calibration": { "blocker": {"accept_rate": 1.0}, "low": {"accept_rate": 0.2} },
      "median_time_to_resolve_s": 5400
    }
  },
  "agreement": { "coderabbitai__chatgpt-codex-connector": {"overlap_findings": 3, "agree": 2} }
}
```

This feeds the **router** (the README's north star): a function from
`(reviewer, category) → trust weight`, learned from accept-rate history.

## 9. Canonical taxonomy (opinionated core + extension)

Cross-*anything* comparison needs a shared spine; pure free-form forecloses the
evaluator/research/platform value. Ship an opinionated core, let users extend.

### 9.1 Canonical severity scale (5 levels)

| canonical | meaning | maps from |
|---|---|---|
| `blocker` | must fix before merge | Codex P0, CR Critical, Copilot High+security |
| `high` | serious; fix this PR | P1, Major, High |
| `medium` | should fix | P2, Minor, Medium |
| `low` | minor / optional | P3, substantive Nit, Low |
| `info` | FYI / style / nit | trivial Nit, style notes |

### 9.2 Categories — broad spine + open tags (resolves §17/Q3)

14 flat categories were too many *as a flat space* — the boundaries between
`correctness`/`error-handling`/`resource-management`, or `dependency`/`security`,
are exactly where raters disagree, and analytics quality depends on consistent
labels. Instead: **~7 broad, high-agreement top-level buckets** (the comparable
spine the router and evaluators run on) + an open **`tags`** field for finer,
optional description.

- **Top-level (canonical):** `correctness`, `security`, `performance`,
  `maintainability`, `testing`, `docs`, `other`.
- **Suggested tags (extensible):** `concurrency`, `error-handling`,
  `resource-leak`, `api-contract`, `supply-chain`, `style`, `build-config`, …

A finding you can only confidently place at top level just gets the bucket;
detail is additive and non-blocking. Configured via `.review-journal.json`'s
`categories` (top-level) + free `tags`.

## 10. Capability negotiation — degradation semantics (normative)

Given profile `P` for reviewer `R` on a PR at head SHA `H`:

1. **running** — if `P.signals.running` is supported+verified, evaluate it; else
   fall back to "a new `review` on `H`, or a new comment by `R`" (noisy), or skip
   (poll for the terminal signal directly).
2. **findings** — evaluate `P.signals.findings` (universal default: a review with
   inline comments on `H`). Always available; **timeout-bound** the wait (R may
   never review `H`).
3. **clean** — if `P.signals.clean` is supported+**verified**, evaluate it; **else
   `clean` is unprovable** → checkpoint:
   *"No findings observed on `H`, but `R` has no verified clean-signal — confirm
   before treating as done."* **Never auto-conclude clean on silence.** This
   applies to the generic fallback *and to Codex* (its `clean` is `verified:false`
   — a zero-finding review was never observed, and its reactions are live-only).
   Operational merge-readiness uses the reviewer-agnostic `unresolvedThreadCount
   == 0`, which is a triage-state, not a reviewer signal.
4. **feedback** — if supported, perform it; else no-op (optionally a plain reply).
5. **trigger** — prefer the *reliable* path: post `P.trigger.manual` after each
   push you want reviewed. Treat `auto_on_push` as a bonus, never a guarantee
   (non-deterministic for Codex), so **don't wait passively for an auto-review** —
   re-trigger, then wait with a generous timeout. The orchestrator must never
   merge on "no review yet" without either the review landing or a deliberate
   decision.

Step 3 is load-bearing: it converts an undetectable/unverified signal into a
checkpoint instead of a false "done."

## 11. First concrete deliverable — `monitoring.md` remediation (DONE)

Independent of the rest of the rollout; applied 2026-06-08. The fixes:

1. **Wait on the persistent review object, not a reaction or a count.** Pattern 1
   now terminates when a `chatgpt-codex-connector` review whose `commit.oid` ==
   head SHA appears, reporting findings (`comments.totalCount > 0`) vs clean
   (`== 0`). Validated against closed #9 (`findings(2)`) and #8 (no review on the
   final head → times out).
2. **SHA baseline, not count** — with an inline note that thread-reply review
   objects inflate counts.
3. **Mandatory timeout** — because Codex's auto-re-review on push is
   non-deterministic (it never re-reviewed #8's post-fix pushes across a 10.6h
   window) and may post nothing on a fully-clean commit (unconfirmed); the
   no-review outcome is "verify / re-trigger", never a silent success. The
   transient 👀/👍 reactions are live-only/unverified, not waited on.
4. **Re-trigger, don't wait passively.** The loop posts `@codex review` after
   each push (the reliable trigger) rather than waiting for an auto-review that
   may never come — moving the real "hang" risk (no auto-trigger) into an action
   the orchestrator controls.

## 12. Conformance & testing

- **Fixture replay.** The signal evaluator consumes the same captured-PR fixtures
  the parser uses (`tests/fixtures/*.json`). A profile's `verified` signals are
  asserted against a real captured response. The Codex fixture is the **review
  objects** (titled "💡 Codex Review", with `commit.oid` + inline counts) from a
  findings pass; a clean-pass fixture is still **needed** (none observed yet).
- **`validate-profile`** subcommand — checks a profile against the RCI schema
  (required keys, known observation types, `verified` only where a fixture backs
  it).
- **`verified` gate.** No signal ships `verified:true` without a backing fixture.
  Codex `clean`/`running`/`feedback`, and all CR/Copilot signals, stay
  `verified:false` until observed.

## 13. Versioning & migration

- Three independent versions: `rci_version` (A), `schema_version` (B, exists),
  `analytics_version` (C).
- **Additive** field → minor bump, default-safe, old data still validates.
- **Breaking** shape → major bump + a documented migration + a one-shot upgrader.
- Consumers ignore unknown fields (forward-compat) and tolerate missing optional
  fields (backward-compat).

## 14. Security & privacy

- **Untrusted input.** Reviewer comments and any `action_hook` output are *data*,
  never instructions. Reaction/trigger targets are validated before any API call.
- **Hooks are opt-in and user-confirmed** before first run — arbitrary code per
  "plugin" is the largest surface here; most bots need none (declarative default).
- **Local-first.** Journals live in the owner's repo; finding text (possibly
  proprietary) never leaves their boundary. A future platform must make
  centralization an explicit opt-in; a research corpus needs a consent +
  anonymization story before any export.

## 15. Non-goals / deferred (with revisit triggers)

| Deferred | Why | Revisit when |
|---|---|---|
| UI / dashboard | Consumer of the files; not the substrate | A second operator asks for it |
| Database / central store | Per-repo JSON + opt-in roll-up suffices | Measurable scale/query pain (cf. the consumer repo's "defer SQLite with a trigger" precedent) |
| Experiment orchestration | Only provenance (§7 `policy`) is needed now | A real A/B is designed |
| Multi-tenancy / auth / hosted privacy | Only matters once hosted | The platform is funded/scoped |

**Captured now precisely because it is unrecoverable later:** normalized severity
at capture, `policy` provenance, complete append-only history, fixture-testable
profiles, versioned contracts.

## 16. Delivery phases

- **Phase 0 (now):** this spec + the `monitoring.md` fix (§11). ✅
- **Phase 1:** profile schema extension (`signals`/`feedback`/`trigger`/
  `canonical`/per-signal `verified`), generic fallback, Codex profile + findings
  fixture, `validate-profile`.
- **Phase 2:** journal additions (`severity_canonical`, `extras.reviewer_feedback`,
  `policy` + config snapshot sidecar), history completeness.
- **Phase 3:** `analyze` read-only consumer (Contract C) + canonical taxonomy docs.
- **Phase 4:** router (trust weights) + propose-and-confirm rule synthesis.
- Each phase is its own PR to `loganrooks/pr-review-journal`, dogfooded against
  live Codex PRs, behind the existing test suite.

## 17. Open questions — resolutions

- **Q1 (reaction-based `clean` robustness) — DISSOLVED.** Live data (§18) shows
  Codex's `clean`/`running` reactions are not reproducible from history (transient
  / live-only). The design no longer depends on them; it polls the persistent
  `review`-on-head-SHA signal with a timeout. The stale-👍 problem disappears with
  the reaction.
- **Q2 (`config_fingerprint` scope) — RESOLVED: whole-file hash + subset
  snapshot.** A false "same config" silently corrupts an experiment (worse than
  over-splitting), so the authoritative hash is over the whole file; the reviewer-
  relevant subset is stored verbatim (deduped by hash) so any bucketing is
  reconstructable later without a brittle "relevant subset" definition. (§7.)
- **Q3 (category granularity) — RESOLVED: ~7 top-level + open tags.** Few high-
  agreement buckets as the comparable spine; tags carry optional detail. (§9.2.)
- **Q4 (NEW, open):** Does Codex post a *zero-finding* review on a fully-clean
  commit, or nothing at all? Unknown — no clean pass observed on #8/#9. Resolving
  it needs a live PR where Codex has nothing to flag; until then `clean` stays
  `verified:false` and the timeout/checkpoint covers both cases.

## 18. Empirical basis (dogfood, 2026-06-08)

Probed closed PRs #8/#9 on `loganrooks/philpapers-mcp` (read-only `gh`):

- Codex communicates via **review objects** titled "💡 Codex Review", state
  `COMMENTED`, each stamped with `commit.oid`. #9 had five Codex review passes
  (`75dfaf4`, `34d4f6d`, `02a7127`, `ceeda11`, `e91c9eb`), inline counts 3/1/1/2;
  the final pass is on the head SHA `e91c9eb` with `inline=2`.
- **No persistent self-reactions** across all three plausible subjects — issue,
  issue-comments, *and* review-thread comments. The only review-thread reactions
  are 7 👍 + 2 👎 placed *by the maintainer* on Codex's finding comments (the
  feedback channel, below), never a Codex 👀/👍 of its own. So the earlier
  "👀→👍 clean signal" is not reproducible from history; whether it is live-only
  or never existed is **undetermined** — either way the design doesn't depend on
  it (`running`/`clean` stay unverified).
- **The feedback channel is persistent and verified.** Those 7 👍 / 2 👎 on
  Codex finding (review-thread) comments are the usefulness reactions Codex
  solicits; the action persists and is queryable (fixture in hand) → `feedback`
  `verified:true`. (Verifies the *channel*, not that Codex ingests it.)
- **No Codex check-run or commit status.** The only checks on either head are
  `build-and-test` (github-actions). No persistent check-based running/clean
  signal exists — the conservative §10 treatment of `clean` stands.
- **No clean-pass sample.** Every observed Codex pass carried inline findings;
  "clean" was reached by *resolving threads* (`unresolvedThreadCount==0`), not a
  Codex signal. Findings remain on the review object after resolution, so a
  review's inline count is the pass's *posted* findings, not the *unresolved*
  count.
- **Trigger is non-deterministic.** Both PRs had exactly one `@codex review`
  comment. #8 → 1 review (`1aa2a01`); its two post-fix pushes (`c346c6c` 22:29,
  `9b6cc88` 23:17) went **un-reviewed across a 10.6h window** before merge
  (09:55 next day). #9 → 5 reviews from the same single trigger, following pushes
  within minutes (plus one ~10.5h-lagged pass, landing ~5 min *after* merge). So
  one trigger *arms* the PR, but whether a given push gets re-reviewed is
  unreliable and latency ranges minutes→hours; cause unknown from the
  orchestrator's vantage. → `auto_on_push: "unreliable"`; reliable path is an
  explicit `@codex review` per push + a generous timeout (§6.4, §10, §11).

This is the evidence behind §6.4's flags and the §11 remediation. Note this
section was itself revised on 2026-06-08 after the prior framing ("transient/
live-only reactions", "doesn't re-review the final head") was challenged and
probed further — principle 5 (verify before you trust) correcting the spec a
second time, against a wider search rather than the first convenient negative.
