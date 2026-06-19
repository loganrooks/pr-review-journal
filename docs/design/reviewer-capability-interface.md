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
  "clean":    { "supported": true, "verified": true,
    "any_of": [ {"type":"comment","by":"self","match":"Didn't find any major issues"} ] },
  "running":  { "supported": false, "verified": false }
}
```

Observation `type`s (the vocabulary a consumer implements):

| type | reads | notes |
|---|---|---|
| `review` | a PR review object | carries `state`, `commit.oid`, inline count → SHA-stampable. `commit:"head"` constrains it to the PR's current head SHA; `title_matches` filters by review title. **Preferred — persistent and verifiable.** |
| `comment` | an issue/PR comment body (REST `issues/N/comments`) | `match` regex. A last resort for *vague* prose — but it is Codex's **authoritative clean channel** (the exact string `Didn't find any major issues`, §6.4). ⚠️ the REST login carries a `[bot]` suffix (`chatgpt-codex-connector[bot]`), unlike the GraphQL `review` login — match both. |
| `check_run` | a commit check/status | for bots that expose a check (Codex does **not**) |
| `issue_reaction` | a reaction on the PR conversation | mutable, **not** SHA-stamped, and **often transient/live-only → hard to verify from history.** A live `+1` from Codex *does* accompany a clean pass, but as a co-signal to the persistent `comment` — stays `verified:false`; don't depend on it alone |
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

**Codex — `findings`/`clean`/`feedback`/manual-`trigger` verified; `running`
and `auto_on_push` not** (characterized on `loganrooks/philpapers-mcp`: findings
on closed PRs #8/#9, the clean pass on live probe #10, all 2026-06-08; see §18).
This is the **hosted GitHub App** (`chatgpt-codex-connector`), *not* the
open-source `openai/codex-action` whose documented SHA-ancestor/cache re-review
logic does **not** apply here:

```jsonc
"chatgpt-codex-connector": {
  "rci_version": "1.0",
  "kind": "bot:agentic-llm",
  "display_name": "Codex (via chatgpt-codex-connector)",
  "forge": "github",
  "identity": {"graphql_login": "chatgpt-codex-connector", "rest_login": "chatgpt-codex-connector[bot]",
    "note": "GOTCHA: the login differs by API surface. GraphQL reviews.author.login has NO suffix; REST issues/N/comments[].user.login HAS '[bot]'. A detector mixing REST+GraphQL must match BOTH — filtering REST by the bare login silently matches nothing (this bit the probe's own watcher, §18)."},
  "severity_patterns": [
    {"pattern":"\\bP0\\b","severity":"P0","canonical":"blocker"},
    {"pattern":"\\bP1\\b","severity":"P1","canonical":"high"},
    {"pattern":"\\bP2\\b","severity":"P2","canonical":"medium"},
    {"pattern":"\\bP3\\b","severity":"P3","canonical":"low"}
  ],
  "severity_note": "Codex uses a P0–P3 priority scale (P0 critical … P3 suggestion). On GitHub it surfaces ONLY P0/P1 by default — P2/P3 won't appear unless an AGENTS.md review guideline escalates them. So absence of a finding ≠ no lower-priority issues; it means none at P0/P1.",
  "signals": {
    "findings": {"supported": true, "verified": true,
      "any_of": [{"type":"review","by":"self","title_matches":"Codex Review","commit":"head","has_inline_comments":true}],
      "note": "FINDINGS path: a COMMENTED review object stamped commit.oid carrying >=1 inline comment (verified #8/#9). A DISTINCT channel from 'clean'."},
    "clean":    {"supported": true, "verified": true,
      "any_of": [
        {"type":"comment","by":"self","match":"Didn't find any major issues"},
        {"type":"issue_reaction","by":"self","content":"+1"}
      ],
      "note": "VERIFIED live on probe #10 (clean no-op): Codex posts a PR ISSUE COMMENT 'Codex Review: Didn't find any major issues. Hooray!' (~85s after @codex review) and a +1 reaction on the PR body. The issue comment is the AUTHORITATIVE channel and matches independent 3rd-party attestation; the +1 is a secondary live co-signal (possibly elicited by the PR body asking it to 'indicate a clean pass'). CRITICAL: on a clean pass there is NO review object — a review-object-only detector misses clean entirely and times out. REPLICATED on probe #12 (2026-06-19, a real two-finding fix PR, not a no-op): clean issue comment at commit 85662d7 ~4.5m after @codex review, again with a +1 and NO review object — confirms the channel on independent content. NB the sign-off WORD VARIES ('Hooray!' on #10, 'Breezy!' on #12); match the stable substring 'Didn't find any major issues', NEVER the sign-off."},
    "running":  {"supported": false, "verified": false,
      "note": "No durable 'running' signal. A 👀 may precede the response but was not captured on #10 (terminal response in ~85s); bare 👀-without-review is a documented OUTAGE (openai/codex#3808), not progress. Poll for the terminal clean/findings signal with a timeout."}
  },
  "feedback": {"supported": true, "verified": true,
    "accept": {"type":"comment_reaction","content":"+1","target":"finding_comment"},
    "reject": {"type":"comment_reaction","content":"-1","target":"finding_comment"},
    "note": "Codex solicits 👍/👎 in each finding's text. The channel is persistent + queryable: #9 carries 7 👍 + 2 👎 by the maintainer on Codex finding (review-thread) comments. Verifies the action persists; NOT that Codex ingests it."},
  "trigger": {
    "manual": {"type":"issue_comment","body":"@codex review"}, "manual_verified": true,
    "auto_on_push": "unreliable", "auto_verified": false,
    "note": "One @codex review arms the PR and reliably yields >=1 review (#10: clean comment in ~85s). Auto-re-review on later pushes is NON-DETERMINISTIC: every #9 push got reviewed (minutes); NONE of #8's two post-fix pushes (10.6h) nor #10's clean 2nd push (15m) did. Mechanism (online research): GitHub exposes no reliable bot re-review hook, and the App's push-event ingestion silently drifts (openai/codex#15477). Do NOT wait passively for auto — re-post @codex review per push you want reviewed."},
  "notes": "VERIFIED 2026-06-08 (clean-pass replicated on #12, 2026-06-19). SPLIT-CHANNEL model: FINDINGS arrive as a COMMENTED review object titled 'Codex Review', stamped commit.oid, with inline comments (closed #8/#9). A CLEAN pass arrives instead as a PR ISSUE COMMENT 'Codex Review: Didn't find any major issues' + a +1 on the PR body, with NO review object (live probe #10). (An earlier note here said Codex 'uses NO issue comments' — FALSE; that was inferred from findings-only closed PRs. Corrected by #10.) No check-run (only github-actions). Verified: 'findings', 'clean', 'feedback' (persistent maintainer 👍/👎 on finding comments), 'manual' trigger. Unverified: 'running', and 'auto_on_push' (non-deterministic — see trigger.note)."
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
an unknown reviewer (silence ≠ clean) → checkpoint. Codex is the exception: it
emits an explicit clean signal (the "Didn't find any major issues" issue comment,
§6.4), so its `clean` is verifiable — but on a *different channel* than its
`findings`, which is why a single review-object poll is insufficient (§10/§11). CR
and Copilot profiles are reserved but unverified until observed (§12).

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
3. **clean** — if `P.signals.clean` is supported+**verified**, evaluate it **on its
   declared channel**; **else `clean` is unprovable** → checkpoint:
   *"No findings observed on `H`, but `R` has no verified clean-signal — confirm
   before treating as done."* **Never auto-conclude clean on silence.** This
   applies to the generic fallback. **Codex is the exception**: its `clean` IS
   verified, but on a *different channel than `findings`* — a PR **issue comment**
   matching "Didn't find any major issues" (+ a `+1` on the PR body), with **no
   review object**. So evaluating Codex's `clean` requires polling the
   issue-comment channel (REST, `[bot]` login), not just review objects (§11).
   Operational merge-readiness still uses the reviewer-agnostic
   `unresolvedThreadCount == 0`, a triage-state, not a reviewer signal.
4. **feedback** — if supported, perform it; else no-op (optionally a plain reply).
5. **trigger** — prefer the *reliable* path: post `P.trigger.manual` after each
   push you want reviewed. Treat `auto_on_push` as a bonus, never a guarantee
   (non-deterministic for Codex), so **don't wait passively for an auto-review** —
   re-trigger, then wait with a generous timeout. The orchestrator must never
   merge on "no review yet" without either the review landing or a deliberate
   decision.

Step 3 is load-bearing: it converts an undetectable/unverified signal into a
checkpoint instead of a false "done."

## 11. First concrete deliverable — `monitoring.md` remediation (DONE, amended by probe #10)

Independent of the rest of the rollout; applied 2026-06-08, **amended the same day
after live probe #10 disproved the clean-pass assumption.** The fixes:

1. **Detect on BOTH channels — this is the load-bearing correction.** Codex is
   split-channel: **findings** arrive as a review object on head SHA with inline
   comments; a **clean** pass arrives as a PR **issue comment** "Codex Review:
   Didn't find any major issues" with **no review object at all**. The original
   remediation polled only review objects, so it would have run a clean PR to
   timeout and reported a false "no review" (probe #10 confirmed this — the clean
   comment landed in ~85s while a review-only poll saw nothing for 30 min). Pattern
   1 must therefore terminate on *either*: a Codex review whose `commit.oid` ==
   head SHA (findings, `comments.totalCount > 0`), **or** a Codex issue comment
   matching `Didn't find any major issues` (clean).
2. **Mind the `[bot]` login split.** GraphQL `reviews.author.login` is
   `chatgpt-codex-connector`; REST `issues/N/comments[].user.login` is
   `chatgpt-codex-connector[bot]`. A poll mixing the two must match both spellings
   — filtering REST by the bare login matches nothing (this exact bug made probe
   #10's own watcher miss the response and time out; §18).
3. **SHA baseline + mandatory timeout.** SHA baseline (not review count — thread
   replies inflate counts). The timeout remains mandatory because the head may
   advance past Codex's last action, or its push-event ingestion may **silently
   drift** (openai/codex#15477) and post nothing; the no-response outcome is
   "verify / re-trigger", never a silent success.
4. **Re-trigger, don't wait passively.** The loop posts `@codex review` after each
   push (the reliable trigger — there is **no reliable GitHub re-review hook** for
   bots) rather than waiting for an auto-review that may never come.

*Status:* the embedded Pattern-1 bash in `references/monitoring.md` is updated to
the two-channel detector below. It remains an acknowledged Phase-0 stopgap that
should migrate to a fixture-tested `review_journal.py` subcommand (§12, §16).

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

- **Q1 (reaction-based `clean` robustness) — DISSOLVED.** A live `+1` *does* appear
  on a clean pass (probe #10, §18), so a reaction exists — but the design keys
  `clean` on the **persistent issue-comment text** ("Didn't find any major issues"),
  not the reaction, so the stale-👍 problem never arises. The reaction is at most a
  secondary co-signal.
- **Q2 (`config_fingerprint` scope) — RESOLVED: whole-file hash + subset
  snapshot.** A false "same config" silently corrupts an experiment (worse than
  over-splitting), so the authoritative hash is over the whole file; the reviewer-
  relevant subset is stored verbatim (deduped by hash) so any bucketing is
  reconstructable later without a brittle "relevant subset" definition. (§7.)
- **Q3 (category granularity) — RESOLVED: ~7 top-level + open tags.** Few high-
  agreement buckets as the comparable spine; tags carry optional detail. (§9.2.)
- **Q4 — RESOLVED (live probe #10, §18): neither a zero-finding *review* nor
  silence.** On a fully-clean commit Codex posts a PR **issue comment** "Codex
  Review: Didn't find any major issues. Hooray!" (+ a `+1` on the PR body) and **no
  review object**. So `clean` is now `verified:true` but on a *separate channel*
  from `findings` — which is exactly why a review-object-only poll fails (§10/§11).
  Corroborated independently by the online research (two 3rd-party merge gates key
  on the same string; the OpenAI SDK cookbook documents an always-present verdict).

## 18. Empirical basis (dogfood, 2026-06-08; clean-pass replicated on #12, 2026-06-19)

Probed closed PRs #8/#9 on `loganrooks/philpapers-mcp` (read-only `gh`):

- Codex communicates **findings** via **review objects** titled "Codex Review",
  state `COMMENTED`, each stamped with `commit.oid` (clean passes use a different
  channel — see the live-probe block below). #9 had five Codex review passes
  (`75dfaf4`, `34d4f6d`, `02a7127`, `ceeda11`, `e91c9eb`), inline counts 4/3/1/1/2;
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

**Live probe #10 (clean-pass — the one closed PRs couldn't show).** A self-declared
no-op PR (`test/codex-reviewer-probe`, a trivial pure function under
`src/experiments/`, excluded from the build) + one `@codex review`. Result in ~85s:

- **Clean pass = a PR issue comment** "Codex Review: Didn't find any major issues.
  Hooray!" (+ a collapsible "About Codex" block), **plus a `+1` reaction on the PR
  body** by `chatgpt-codex-connector[bot]`, and **no review object**. This overturns
  the earlier §6.4 "clean = a zero-inline-comment review" candidate: findings and
  clean are *different channels*.
- **A self-inflicted detection bug confirmed the very risk this work targets.** The
  probe's own watcher filtered REST issue-comments by the GraphQL login
  `chatgpt-codex-connector` and so matched nothing — it ran a full 30-min timeout
  while Codex had actually answered in 85s. The REST login is
  `chatgpt-codex-connector[bot]`. Now a first-class `identity` field (§6.4) and a
  §11 caveat: the exact failure the monitoring fix exists to prevent, reproduced
  live by the verifier itself.
- **No Codex check-run** (only `build-and-test`), consistent with #8/#9.
- **Auto-on-push held false a third time — and on a *clean* push.** A second
  trivially-clean push (`e8c8d7c`, no re-trigger) drew **no review and no comment
  within 15 min**. This rules out the alternative that #8's un-reviewed pushes were
  simply "clean → silent": a clean pass *does* post a comment when reviewed, so the
  absence is genuinely "auto didn't fire," matching #8. → `auto_on_push: "unreliable"`.

**Live probe #12 (clean-pass on a *real* fix — replication, 2026-06-19).** Unlike #10's
no-op, this was a genuine two-finding bugfix PR (`philpapers-mcp#12`, fixing the two Codex
P2 threads on #9). One `@codex review` → in ~4.5 min, the *same* clean channel: a PR issue
comment "Codex Review: Didn't find any major issues. **Breezy!**" stamped `Reviewed commit:
85662d7`, **plus a `+1`** on the PR body, and **no review object** — independently
replicating #10 on different content. Two refinements: (a) the sign-off word **varies**
("Hooray!" #10 → "Breezy!" #12), so a detector must match the stable substring `Didn't find
any major issues`, never the sign-off; (b) the two-channel `pass_done()` from §11 /
`monitoring.md` was itself run live against #12 and returned `clean` correctly — the
remediation validated by the very loop that produced it.

**Online research (two web agents, 2026-06-08).** Frames and corroborates the above:
(a) the reviewer here is the **hosted GitHub App**, distinct from the open-source
`openai/codex-action` whose deterministic SHA/cache re-review logic does *not*
apply; (b) the clean string is independently attested (two 3rd-party merge-gate
tools key on it; the OpenAI SDK cookbook documents an always-present verdict +
possibly-empty `findings[]`); (c) severity is **P0–P3**, GitHub surfacing only
P0/P1; (d) the auto-on-push non-determinism has a *mechanism* — GitHub exposes **no
reliable bot re-review hook**, and the App's push-event ingestion **silently
drifts** (openai/codex#15477, #3808) — so "re-trigger manually" is the documented
remedy, not a workaround; (e) the 👍/👎 feedback is telemetry with no documented
functional effect. Sources in the project memory.

This is the evidence behind §6.4's flags and the §11 remediation. The section was
revised **three times** on 2026-06-08 as principle 5 (verify before you trust) bit
in turn: first the review-object model (over closed PRs), then the trigger
non-determinism (a wider probe refuting "doesn't re-review the final head"), then
the clean-pass channel (a *live* probe refuting both "clean = empty review" and the
convenient "maybe it posts nothing"). Each correction came from probing the
unprobed subject rather than trusting the first convenient negative — including, the
third time, a bug in the verifier itself.
