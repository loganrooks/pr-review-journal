# ADR — Review governance: keep the ledger, split the enforcement

**Status:** Proposed. This ADR is not ratified.
**Date:** 2026-07-27 (rewrite of the 2026-06-22 draft)
**Authors:** Logan Rooks; rewritten against the evidence ledger below.
**Scope:** `pr-review-journal`, its review-journal tool, and the proposed review-governance capabilities around it.

## Decision summary

The operator has settled three decisions. They are recorded here as decisions, not recommendations:

| Decision | Settled outcome | Reason | Reversal condition |
|---|---|---|---|
| **A — name** | **Do not rename.** `pr-review-journal` keeps its name and remains the ledger. | The ecosystem map defines this repository as the independent verdict ledger and separates it from the controller. Renaming the ledger to advertise an enforcement role would encode the wrong boundary. (`/Users/rookslog/Development/agentic-ecosystem/ECOSYSTEM.md:92-110`) | Only an explicit later operator decision, backed by a consumer inventory, migration plan, and marketplace/URL compatibility check, may reopen the name. |
| **B — home** | **Split.** `respond` belongs in `pr-review-journal`. `gate-rerequest` and `watch` are per-repository CI infrastructure following the `power-toolkit` bootstrap pattern. They do not belong in this plugin and are not, yet, assigned to `agentic-review-loop`. | The ledger already owns verdict parsing, recording, and discipline. The CI pattern is the only measured implementation that directly enforces reply + reaction + resolution. ARL is still dormant and not installable. (`/Users/rookslog/Development/pr-review-journal/tools/review-journal/review_journal.py:486-515,1260-1388`; `/Users/rookslog/Development/power-toolkit/.github/workflows/review-gate.yml:171-214`; `/Users/rookslog/Development/agentic-review-loop/README.md:1-8`) | Revisit the split if ARL becomes installable, ships an executable controller/watch surface, and has an active consumer that explicitly accepts this ownership; or if the per-repo CI pattern proves insufficient across active repositories. |
| **C — Sophotron PR #19** | **Strike it.** The hold/merge recommendation is moot. PR #19 merged on 2026-06-30 and its check remains advisory. | The proposed action was aimed at a PR that is no longer open. (`gh pr view 19 -R loganrooks/sophotron`; `/Users/rookslog/Development/sophotron/.github/workflows/ci.yml:78-81`) | No reversal of this decision. A future Sophotron gate change is a new decision against its then-current state. |

## 1. Boundary first: the ledger is not the controller

### MEASURED

The ecosystem map says that its “Does NOT own” lines are the actual fences. It describes a three-stage review pipeline: producers → `pr-review-journal` ledger → `agentic-review-loop` controller. It assigns the ledger verdict discipline and measurement, while excluding “deciding what to do with a PR — loop timing, escalation, merge.” It assigns ARL the automated responder/controller role: read the ledger, decide escalation/merge, and write verdicts through the journal schema. (`/Users/rookslog/Development/agentic-ecosystem/ECOSYSTEM.md:11-15,36-41,92-110,113-129`)

Accordingly, this ADR records one coherent boundary: **keep the name**, keep the ledger/controller fence intact, and do not make the gate the journal's spine.

### INFERRED

The fence means that this repository may implement response mechanics and record their outcomes, but it must not silently become the owner of loop timing, escalation, merge, or a general PR controller. `respond` is a ledger-side interaction capability. `gate-rerequest` and `watch` are enforcement/coordination capabilities and therefore live in the per-repository CI lane for now.

## 2. Maturity constraint: ARL is a dormant dependency, not today's home

### MEASURED

`agentic-review-loop` describes itself as “P0 bootstrap” and “Not yet installable.” Its checked-out tip is `dcedd8745174022dd6ddc0d826cbeba15dc9cbbd`, dated 2026-05-29, with subject `docs(readme): add agentic-* family pointer to the ecosystem map`. The checkout has no `bin/pr-watch` and no `.claude-plugin/plugin.json`. (`/Users/rookslog/Development/agentic-review-loop/README.md:1-8`; `/Users/rookslog/Development/agentic-review-loop/.git` history; filesystem checks for `/Users/rookslog/Development/agentic-review-loop/bin/pr-watch` and `/Users/rookslog/Development/agentic-review-loop/.claude-plugin/plugin.json`)

### INFERRED — the routing bet

Decision B is a deliberate bet that ARL will remain dormant long enough for repositories that need review enforcement to bootstrap their own CI. This is not a claim that ARL is irrelevant. It is a maturity-aware routing choice: putting `gate-rerequest` or `watch` into a not-yet-installable controller would leave today's active repositories without an executable path, while putting them into the ledger would cross the fence.

The bet reverses when ARL is installable, has a controller/watch entry point, has an active consumer, and accepts the ownership contract. Until then, per-repo CI is the home for enforcement and monitoring; ARL remains a future controller consumer of the ledger.

## 3. What the evidence actually says: twelve mechanisms, not three

### MEASURED — review-gate census

The census found **12 distinct executable or configured mechanisms across 10 repositories**. The count treats independently runnable repo-local implementations and deployers as separate mechanisms. It excludes documents, fixtures, vendored dependencies, worktree copies, and mirrors.

| Repository | Mechanism / evidence | Reply | React | Resolve | Boundary | Wiring state |
|---|---|:---:|:---:|:---:|---|---|
| `power-toolkit` | `/Users/rookslog/Development/power-toolkit/.github/workflows/review-gate.yml:177` + `/Users/rookslog/Development/power-toolkit/.github/rulesets/review-gate.json:1` | ✓ | ✓ | ✓ | Merge; default branch only | Repo-wired; remote deployment not verified |
| `openhands-agent-sdk` | `/Users/rookslog/Development/openhands-agent-sdk/.github/workflows/review-thread-gate.yml:17-90` | — | — | ✓ | Merge CI | CI-wired; required remote status not locally represented |
| `gsd-core` | `/Users/rookslog/Development/gsd-core/.github/rulesets/main-protection.json:1` and `release-branches.json:1`; installer `/Users/rookslog/Development/gsd-core/scripts/setup-branch-protection.sh:132-145` | — | — | ✓ | Merge | Dormant checked-in rulesets; installer can apply classic protection |
| `agentic-harness-research-navigator` | `/Users/rookslog/Development/agentic-harness-research-navigator/scripts/configure_github.sh:34-50` | — | — | ✓ | Merge | Dormant manual deployer |
| `pr-review-journal` | `/Users/rookslog/Development/pr-review-journal/tools/review-journal/review_journal.py:486-515,1305-1388` | △ structured verdict reply is recorded | — | ✓ coupled to verdicts | Merge-oriented in strict mode | Dormant library/tool; no local workflow |
| `tap-n-filter` | `/Users/rookslog/Development/tap-n-filter/tools/review-journal/review_journal.py:467-489`; `/Users/rookslog/Development/tap-n-filter/.review-journal.json:1-4` | △ structured verdict reply | — | ✓ coupled to verdicts | Merge-oriented if strict mode is chosen | Dormant fork; CI does not invoke it |
| `erebus` | `/Users/rookslog/Development/erebus/.github/workflows/review-journal.yml:1-45` | △ structured verdict reply | — | ✓ coupled to verdicts | Merge-oriented | CI-wired but advisory (`--enforce warning`) |
| `erebus` | `/Users/rookslog/Development/erebus/scripts/wait-for-pr-merge.sh:92-127` | — | — | ✓ first 50 queried threads | Merge | Dormant/manual monitor; admin merge only with `AS_MONITOR=1` |
| `erebus` | `/Users/rookslog/Development/erebus/scripts/wait-for-codex-review.sh:1-25` | — | — | —; waits for any Codex review | Pre-merge wait | Dormant/manual monitor |
| `lectern` | `/Users/rookslog/Development/lectern/.github/workflows/ci.yml:105-115`; `/Users/rookslog/Development/lectern/tools/check_codex_review.py:170-185` | — | — | —; current-head Codex evidence | Merge-oriented CI | CI-wired; required-check status not locally represented |
| `sophotron` | `/Users/rookslog/Development/sophotron/.github/workflows/ci.yml:78-90`; `/Users/rookslog/Development/sophotron/tools/check_codex_review.py:1-18,242-255` | — | diagnostic only; reactions rejected as proof | —; current-head Codex artifact | Merge-oriented CI | CI-wired and explicitly advisory |
| `agentic-mail` | `/Users/rookslog/Development/agentic-mail/scripts/pr-ops/watch-pr.sh:37-48` | — | — | observes unresolved non-outdated threads | Neither; suggests `@codex review` | Dormant/manual monitor |

The census was a local source audit. Live GitHub branch protection, required-check deployment, and remote workflow state were not treated as measured because they require live repository API state; the accessible Sophotron PR query is the exception noted in Decision C.

The repository currently has a documentation/count discrepancy: `README.md` describes **35** tests, while the local `tools/review-journal/tests/run-tests.sh` runner executed **41** test scripts, all passing in this verification. The exact count is therefore not used as a decision argument here. (`/Users/rookslog/Development/pr-review-journal/README.md:17-28,114-122`; `/Users/rookslog/Development/pr-review-journal/tools/review-journal/tests/run-tests.sh`)

### INFERRED — semantic divergence

These mechanisms are not one interchangeable system. `power-toolkit` requires a PR-author reply, a reaction, and resolution; OpenHands/GSD/branch-protection paths require resolution; journal paths require a structured disposition coupled to resolution; Lectern/Sophotron require current-head Codex evidence. (`/Users/rookslog/Development/power-toolkit/.github/workflows/review-gate.yml:177-214`; `/Users/rookslog/Development/openhands-agent-sdk/.github/workflows/review-thread-gate.yml:36-90`; `/Users/rookslog/Development/pr-review-journal/tools/review-journal/review_journal.py:1305-1388`; `/Users/rookslog/Development/sophotron/tools/check_codex_review.py:326-381`)

Reaction semantics conflict by design: `power-toolkit` treats a reaction as one of its obligations, while Sophotron treats reactions as diagnostic because a reaction is not commit-bound. (`/Users/rookslog/Development/power-toolkit/.github/workflows/review-gate.yml:186-203`; `/Users/rookslog/Development/sophotron/docs/governance/review-protocol.md:33-52`)

Failure handling also differs: `power-toolkit` fail-closes on truncated result windows, while Erebus queries only `first:50` threads and turns a failed GraphQL command into `0` through `|| echo "0"`. (`/Users/rookslog/Development/power-toolkit/.github/workflows/review-gate.yml:159-175`; `/Users/rookslog/Development/erebus/scripts/wait-for-pr-merge.sh:122-127`)

## 4. The critical ecosystem gap

### MEASURED

None of the 12 mechanisms in the census blocks a **new review request** until prior findings satisfy reply, reaction, and resolution. The measured mechanisms gate merge, run as advisory CI, wait for a review, or monitor a PR. The `power-toolkit` workflow's three-predicate logic is a merge-path status check; its source has no pre-request guard. (`/Users/rookslog/Development/power-toolkit/.github/workflows/review-gate.yml:159-214`; `/Users/rookslog/Development/agentic-mail/scripts/pr-ops/watch-pr.sh:37-48`)

### INFERRED

The “genuinely net-new” conclusion applies across the whole discovered ecosystem, not merely across three compared repositories. This is the strongest reason to add the capability while keeping its enforcement home outside the ledger plugin.

No implementation may claim that merge-readiness or zero unresolved threads prevents a new `@codex review`. Those are different predicates: one describes a merge path; the other protects the next review request from racing an unread, un-dispositioned prior round.

## 5. Operational incidents and capability requirements

### MEASURED — available local evidence

`stylewright#32` documents a manual response that required writing hand-rolled GraphQL twice in one session. A later array-indexing mistake sent six verdict blocks to the wrong threads, resolved those wrong threads, and still reported `0 unresolved`. (`docs/design/HANDOFF-counting-model.md:91-100`)

`pr-review-journal#11` documents a merge on a `0 unresolved` snapshot, followed by a third Codex round landing 5m14s after merge. The local handoff records three rounds and four findings in that late round. (`docs/design/HANDOFF-counting-model.md:115-129`)

These are sufficient measured evidence for `respond` and `watch`: response must be keyed by stable thread identity, and monitoring must distinguish “the current snapshot is clear” from “no later review round can still arrive.”

### UNCHECKED — stylewright#27

The operator reports that two P1 findings were followed 82 seconds later by `@codex review` on the unchanged commit `67737ed`, producing a false clean result over open findings. The local checkout has no durable incident record for that PR, and the remote `loganrooks/stylewright` repository/PR was not accessible through the current GitHub API session. This incident is therefore **not independently verified here** and is not counted as measured evidence. If confirmed later, it is a direct additional example for `gate-rerequest`.

The general need does not depend on that unchecked incident: the measured merge-vs-request gap and the two documented stale-snapshot incidents already establish the capability requirements.

## 6. Proposed capability profile and ownership

The capability set is retained and expanded. “Proposed” describes this ADR; it does not claim that the capability exists today.

| Capability | Proposed home | Contract | Current evidence/status |
|---|---|---|---|
| `sync`, `validate`, `extract`, `parse-block` | `pr-review-journal` | Read and normalize review threads, parse verdict blocks, persist the journal, and report missing/invalid dispositions. | Existing tool paths and test contract are documented in `/Users/rookslog/Development/pr-review-journal/README.md:17-28,72-122` and `/Users/rookslog/Development/pr-review-journal/tools/review-journal/review_journal.py:486-515,1305-1388`. |
| `respond` | `pr-review-journal` | Given stable thread IDs, post the structured verdict reply, apply the configured reaction, and resolve the intended thread; dry-run and idempotency are required. | Proposed. The current tool fetches and records threads but has no mutation subcommand in `/Users/rookslog/Development/pr-review-journal/tools/review-journal/review_journal.py:486-515,1260-1388`. |
| `check-status` | Per-repo CI infrastructure | Evaluate the profile-driven RED/YELLOW/GREEN state for the current head and publish the repository's status. | Proposed split-lane implementation; `power-toolkit` is the bootstrap pattern at `/Users/rookslog/Development/power-toolkit/.github/workflows/review-gate.yml:159-214`. |
| `gate-rerequest` | Per-repo CI infrastructure | Permit a new review request only when every prior tracked finding is resolved and, when supported, rated and responded to; unsupported feedback is `n/a`, not a block. | Proposed and genuinely net-new across the census. Not part of this plugin and not assigned to ARL yet. |
| `watch` | Per-repo CI infrastructure | Wait for a new head-bound terminal review/clean signal, enforce a timeout, then re-check the ledger/merge snapshot before reporting readiness. | Proposed. The late-round evidence is `/Users/rookslog/Development/pr-review-journal/docs/design/HANDOFF-counting-model.md:115-129`. |
| `request-review` | Unassigned by this ADR | Any trigger adapter must call `gate-rerequest`; no direct trigger path may bypass the guard. | Deliberately left open until the CI lane is designed. This ADR does not put it in the plugin or ARL. |

The `respond` implementation must use thread IDs or another stable server identifier. It must not pair bodies to threads by array position; the documented zsh off-by-one incident is precisely the failure this contract prevents. (`docs/design/HANDOFF-counting-model.md:96-100`)

## 7. Retained semantics

### 7.1 RED / YELLOW / GREEN

Keep the state machine as a cross-component contract:

```text
GREEN  = a verified clean signal for head H
         OR findings on H with zero unresolved findings and all supported
         disposition predicates satisfied.

YELLOW = reviewer still running;
         trigger observed but no head-bound terminal signal yet;
         supported-but-unverified capability;
         or an unverified clean state that needs an operator checkpoint.

RED    = current-head changes requested;
         head advanced while a prior round remains open;
         or a new review request violated the prior-round gate.
```

The state machine is a proposed contract, not a claim that this repository currently publishes those statuses. “No findings observed” is never equivalent to a verified clean result for a reviewer without a verified clean signal. (`/Users/rookslog/Development/pr-review-journal/docs/design/reviewer-capability-interface.md:365-380`)

YELLOW is an advisory/checkpoint state, not a RED merge block by itself; whether a repository promotes a checkpoint to a required check remains a per-repository CI decision. (`/Users/rookslog/Development/power-toolkit/.github/workflows/review-gate.yml:168-175,240-241`; `/Users/rookslog/Development/sophotron/.github/workflows/ci.yml:78-81`)

### 7.2 Capability profiles

Keep the reviewer-capability design: reviewer behavior is configuration, not duplicated reviewer-specific code. Profiles declare `signals`, `feedback`, `trigger`, `verified`, `supported`, and forge identity. Codex remains the empirical profile example: findings arrive through a current-head review object, while clean arrives through a current-head issue comment; these are separate channels. (`/Users/rookslog/Development/pr-review-journal/docs/design/reviewer-capability-interface.md:107-154,210-242`)

### 7.3 Vacuous satisfaction, scoped correctly

Keep the vacuous-satisfaction rule for **unsupported feedback capabilities**: if a profile cannot support rating or responding, that predicate records `n/a` and does not create a permanent RED. Do not extend that rule to unverified observation signals. An unverified signal is a YELLOW/checkpoint until confirmed; silence never proves clean. (`/Users/rookslog/Development/pr-review-journal/docs/design/reviewer-capability-interface.md:365-380`)

### 7.4 Telemetry envelope

Keep the proposed seven-field JSONL telemetry envelope (`ts`, `component`, `component_version`, `envelope`, `event`, `session`, `payload`) as a cross-component contract. The payload should include PR, head SHA, profile, state, predicate results, and a configuration stamp. This is future design work: the current journal source contains `verdict_history` but no telemetry envelope emitter. (`/Users/rookslog/Development/pr-review-journal/tools/review-journal/review_journal.py:815-837,983-1037`; `/Users/rookslog/Development/pr-review-journal/docs/design/reviewer-capability-interface.md:277-305`)

## 8. What this ADR drops

1. **Rename and gate-spine inversion.** Dropped because they violate the measured ledger/controller fence. The journal remains the ledger; it is not renamed to imply that it owns enforcement. (`/Users/rookslog/Development/agentic-ecosystem/ECOSYSTEM.md:92-110`)
2. **Consolidating all enforcement into this plugin.** Dropped because the census shows divergent semantics and because the only directly measured three-predicate gate is a repo-local CI workflow. The plugin can provide the ledger-side response capability and shared contracts; per-repo CI owns enforcement for now. (`/Users/rookslog/Development/power-toolkit/.github/workflows/review-gate.yml:171-214`)
3. **Treating ARL as today's implementation home.** Dropped because ARL is not installable and has no checked-out watch entry point. This is a timing decision, not a rejection of the ecosystem fence. (`/Users/rookslog/Development/agentic-review-loop/README.md:1-8`)
4. **The three-repository census.** Dropped because the source audit found 12 mechanisms across 10 repositories. The systems are semantically divergent, so “three implementations” understates both the duplication and the integration risk.
5. **Holding Sophotron PR #19.** Dropped because it merged on 2026-06-30. (`gh pr view 19 -R loganrooks/sophotron`)

## 9. Proposed next steps and non-decisions

This ADR does not ratify implementation or change `skills/` or `tools/`. A future implementation sequence should be:

1. Specify and test `respond` in the ledger repository, with stable thread-ID pairing, dry-run, idempotency, mutation error reporting, and a post-action re-fetch.
2. Bootstrap `check-status`, `gate-rerequest`, and `watch` in the repositories that need them, using the `power-toolkit` workflow/ruleset pattern as the starting point and recording each repository's actual wiring state.
3. Keep the RCI profile and state-machine semantics shared as contracts, while allowing repo-local CI to choose its deployment details.
4. Revisit ARL only when the reversal conditions in Decision B are measured as true.
5. Add telemetry only with a versioned envelope and a configuration stamp; do not describe a proposed emitter as existing functionality.

The unresolved implementation questions are intentionally not converted into operator decisions here: the final `request-review` home, the exact CI distribution mechanism, live branch-protection promotion, and the confirmation of stylewright#27 remain open or unchecked.

**Decision record:** keep `pr-review-journal` as the independent ledger; put `respond` here; build `gate-rerequest` and `watch` per repository in CI; retain the state/profile/vacuous-satisfaction/telemetry contracts; and do not ratify a rename, a plugin-wide controller, or a stale action against merged Sophotron PR #19.