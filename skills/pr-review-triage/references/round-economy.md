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

## Status of this file

**Untested.** Written 2026-07-26 from an operator observation, not from a watched failure.
The Iron Law in obra/superpowers `writing-skills` is that no skill ships without a failing
test first; this file does not satisfy it. The predicates above (round budget, dominance
threshold, the "only instance" question) are **Conjecture** until measured against real PR
histories. `tools/review-journal/` already stores per-thread verdicts and reviewers, which is
the data needed to check whether round count actually correlates with cluster-blindness —
that measurement has not been run.
