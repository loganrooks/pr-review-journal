# Round economy

The rest of this skill is about disposing of a finding *well*. This file is about needing
fewer rounds of them.

**The claim:** round count is a property of the loop, not of the code. A PR that takes eight
reviewer passes is not being reviewed thoroughly; it is being reviewed repeatedly because
each pass fixes sites instead of causes, or introduces the next pass's findings. Treat a
high round count as a defect report against *this skill and your process*, not as evidence
of diligence.

## The budget

| Round | What it is for | If it carries substantive findings |
|---|---|---|
| 1 | Triage everything the reviewer found | Normal. This is the point. |
| 2 | Confirm the round-1 fixes; catch what the fixes exposed | Normal, and expected — a good fix changes the surface. |
| 3 | — | **Tripwire.** Stop fixing. Run the escalation below. |
| 4+ | — | The loop is broken. You are now generating findings, not resolving them. |

"Substantive" is the observable predicate: **a finding that is not `REJECTED_FALSE_POSITIVE`,
`OBSOLETE`, or a nit you'd have shipped without.** Count them per round; write the count in
the round's summary so the tripwire cannot be reached by not looking.

Nit-only rounds don't count against the budget. Two rounds of real findings then a nit round
is a healthy PR.

## Before you fix anything — read the shape of the round

Do this once per round, before touching code. It costs one pass over the findings and is the
single highest-leverage step in the file.

**1. Tabulate.** Category × locus × depth for every finding:

| Axis | Values | What it tells you |
|---|---|---|
| Category | correctness / concurrency / error-handling / API-contract / test-gap / docs / style | A category that dominates is a *skills* gap, not a code gap |
| Locus | one site / one module / cross-cutting | Cross-cutting means the fix is upstream of every site |
| Depth | surface symptom / structural cause | Surface-heavy rounds predict a round N+1 |

**2. Cluster.** If two or more findings share a root cause, they are **one** fix. Fix the
cause; dispose of the rest as `DUPLICATE` pointing at the primary thread. Resist the pull to
apply N suggested patches — N patches is N chances to introduce round N+1, and it leaves the
cause in place to generate more findings later.

**3. Ask the dominance question.** If one category is >50% of the round, the PR has a
systematic gap, and the right fix is usually a single structural change plus a test that
makes the class impossible — not per-site patches. Say so explicitly in the round summary.

## The surface-symptom test

This is what the user means by *"the bot is only catching the surface."* Automated reviewers
see the diff. They cannot see the sites you didn't touch, so they systematically report a
class of defect as a single instance.

For every finding, ask one question:

> **What would have to be true for this to be the only instance?**

If you can answer it (the code path genuinely exists once; the convention is enforced by a
type), fix the site and move on. If you cannot, **grep for the siblings the reviewer could
not see**, and fix the class. A finding you fixed at one site and left at three others is a
guaranteed future round the moment those lines enter a diff.

The corollary: a reviewer reporting a *specific* problem has told you where to look, not what
the problem is. Locality of the report is an artifact of the review window.

## Before you push — self-review the fix batch

The largest single source of round N+1 is round N's fix. Automated reviewers re-review the
new diff, so every line you wrote in response is new attack surface, and it was written under
time pressure with the reviewer's framing in your head.

Read your own fix diff as if it arrived from someone else, and answer:

- Does each fix address the cause you identified, or the symptom the reviewer described?
- Did any fix widen a signature, relax a guard, or add a branch that now needs its own test?
- Did I apply a suggested patch whose blast radius I did not actually trace?
- Is there a test that would have caught the original finding? If not, the next refactor
  reintroduces it.
- Would the *same reviewer*, seeing only this diff, file something new?

That last question is the whole exercise. If the answer is yes, fix it now — a round you
prevent costs one grep; a round you incur costs a full review cycle plus a re-triage.

## Fixes that only look like fixes

Two failure modes that produce a *confident* disposition and a next round anyway. Both are
cheap to check and neither is caught by re-reading the diff, which is why they get their own
rule rather than a bullet above.

### A verification that predates the change it covers is not a verification

Running the check, then editing, then reporting the earlier run's result. Nothing about it
feels like skipping verification — you *did* run it, and it *did* pass. But the command you
ran is no longer the command your change produces.

> A ruleset JSON was applied successfully against the live API. A documentation key was then
> added to the same file. The API rejects unknown keys with a 422, so the file could no longer
> be applied at all — and the "verified" claim came from the run before the key existed.

Before writing a verdict that cites evidence, ask: **was this evidence produced by the current
state of the change?** If the fix moved after the check, the check is stale. Re-run it, or
down-label the claim.

The same shape appears in tests: a test written after a fix, which passes, but whose assertion
is dominated by an unrelated code path and would pass with the fix reverted. If a test has
never failed, you have not yet learned anything from it — flip the fix off and watch it fail
before you trust it.

### Loud is not closed

Making a failure *visible* is not the same as making it *not happen*. The fix reports; the
consequence still lands.

> A gate's rule was "any failure must be loud — exit non-zero." But the merge was blocked by a
> published status, not by the job's exit code, so a red run informed the operator while the PR
> stayed green and mergeable. Several fixes written under that rule were weaker than they
> claimed.

For any fix whose mechanism is reporting — a log line, a warning, a non-zero exit, a
notification — name the thing that actually enforces, and check that your signal reaches *it*.
If the enforcing thing never sees the signal, you have improved the diagnostics of an
unchanged bug. That is worth doing, but it is a different verdict, and saying so is what keeps
the next round from finding it.

### A note on clustering

Both of these interact with the cluster rule above: a class is not fixed until **every consumer
of the shared thing** has been checked — not every use inside the file you happened to be
editing. Two files consuming one shared config list is the common case, and fixing one of them
while writing "fixed as a class" is how a closed finding reopens two rounds later.

## At the tripwire (round 3 with substantive findings)

Stop fixing. Write a short note on the PR and pick one:

1. **The clustering was wrong.** Re-run the shape pass across *all rounds together*, not just
   the current one. Usually one cause explains most of what's left.
2. **The PR is too large or does too many things.** Split it. Round count scales worse than
   linearly with diff size, because each round's fixes become the next round's surface.
3. **The design is wrong and review is finding that out one symptom at a time.** This is the
   expensive one and the most common at round 4+. Escalate to a design decision rather than
   continuing to patch.
4. **The reviewer is miscalibrated for this repo** (generic patterns vs. a local convention).
   The fix is repo configuration or a `CLAUDE.md` / `AGENTS.md` note, not more rounds.

Record which one, with reasons. A tripwire that fires and gets waved through is not a
tripwire.

## Rationalizations that keep the loop spinning

| What you'll think | Why it's wrong |
|---|---|
| "It's only a small fix, I'll just apply it." | Small unclustered fixes are how a round-2 PR becomes a round-6 PR. Cost per round is a full review cycle, not the size of the edit. |
| "The reviewer will catch it if I got it wrong." | Using the reviewer as your test suite is what buys the extra rounds. It is also the slowest possible feedback loop you have access to. |
| "Lots of rounds means it's being reviewed thoroughly." | Thoroughness is findings-per-round-1, not rounds. A high round count means findings arrived late, which means they were cheap to find and you didn't look. |
| "Each round had fewer findings, so it's converging." | Converging on *this* diff. Nothing about a decaying count says the causes were fixed rather than the sites. |
| "I'll cluster after I clear the easy ones." | The easy ones are the evidence for the clustering. Clear them first and you've discarded the pattern. |
| "The tripwire doesn't apply, these are all different." | Then say what the categories are, out loud, in the round summary. If you can't, they aren't different. |

## Red flags

- You applied a suggested diff without opening the surrounding file.
- Two threads got near-identical replies. That is an unnoticed cluster.
- A round's fixes touched files no finding mentioned, and you didn't say why.
- You are on round 3+ and have not written down a category tabulation for any round.
- You resolved a thread whose reply contains no verdict block.
- The PR's diff grew every round.
- A verdict cites evidence from a command you ran *before* your most recent edit.
- A test you wrote for this fix has never been observed to fail.
- The fix's mechanism is a log line, a warning or an exit code, and you have not named the
  thing that actually enforces.
- You wrote "fixed as a class" without listing the consumers you checked.

## Status of this file

Written 2026-07-26 from an operator observation, then exercised the same day against a live
sequence: **26 findings over 9 review rounds on 3 PRs** in `loganrooks/power-toolkit` (#1–#3),
reviewed by `chatgpt-codex-connector`.

What that run supports, as **Observed on one corpus** — one repo, one reviewer, one author, so
treat it as an existence proof rather than a rate:

- Roughly 15 of 26 findings were a **class reported as a single instance**. The
  surface-symptom question found a sibling every time it was asked, including siblings outside
  the diff the reviewer could see.
- Roughly 10 were **self-inflicted** — the previous round's fix authoring the next round's
  finding. This is the mechanism the budget and the pre-push self-review exist for, and it was
  the single largest source of rounds.
- Both rules in *Fixes that only look like fixes* are transcribed from real defects in that
  run, not invented.

What it does **not** establish: the round budget, the 3-round tripwire and the >50% dominance
threshold are still **Conjecture** — the run is consistent with them but did not test them, and
one repo cannot calibrate a threshold.

### The no-guidance control, and where it came from

`writing-skills` asks for a **no-guidance control** before authoring: watch agents fail without
the skill, or there is nothing to fix. That control exists, and it was run by accident.

**Measured.** The plugin build installed and loading during the power-toolkit run was pinned at
`72715c7` (2026-05-25). That commit does not contain this file:

```
git ls-tree -r --name-only 72715c7 -- skills/pr-review-triage/
  skills/pr-review-triage/SKILL.md
  skills/pr-review-triage/references/monitoring.md
  skills/pr-review-triage/references/verdicts.md
```

So the agent that ran those 9 rounds had `pr-review-triage` loaded and had **none** of this
file's guidance from it. The control exhibited the failure the file addresses: ~10 of 26 findings
were authored by the previous round's fix.

**The contamination, stated plainly.** This is not a clean control. The same agent wrote this
file partway through the run, so the later rounds had the reasoning in working context even
though the skill did not carry it. The uncontaminated portion is the rounds that precede
`5b3efd1`; after that point the run is an author dogfooding their own draft. One repo, one
reviewer, one author.

**What that leaves.** The RED phase is satisfied in the weak sense that matters — the failure is
real, observed, and not invented to justify the file. It is *not* satisfied in the strong sense
`writing-skills` intends: no fresh-context agent was given a multi-round PR with this file
withheld, so nothing here is a controlled comparison, and no GREEN result exists at all.

### The deployment arm

Deployed 2026-07-26 as a live dev build (`~/.claude/skills/pr-review-journal-dev` → this working
tree; the pinned `72715c7` install was removed to free the plugin name). Subsequent review cycles
are the with-guidance arm.

The observable needs no extra instrumentation, because this file already prescribes it: a round
worked under this guidance leaves a **substantive-finding count** and a **category tabulation** in
its round summary. Their presence in the PR threads says the file was applied; their absence says
it was not, however many times `skillUsage` records the skill firing. Baseline at deployment:
`pr-review-journal:pr-review-triage` had fired 5 times, all against the build without this file.

`tools/review-journal/` stores per-thread verdicts and reviewers, which is the data needed to
check whether round count tracks cluster-blindness across repos. That measurement has not
been run.
