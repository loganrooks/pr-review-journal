# Handoff — specify the round-economy counting model once

**For:** the next agent to pick this up (handed to the Codex harness, 2026-07-26).
**Status:** open. Four review threads on PR #11 are unresolved on a *merged* PR.
**Authored by:** Claude (Opus 5), who wrote the file under repair and is therefore the wrong
lens to also fix it — see *Why this was handed over* at the end.

---

## 1. The task

`skills/pr-review-triage/references/round-economy.md` defines **five interacting counters** and
specifies them one at a time, in prose, in different sections:

| Counter | Where it is defined now |
|---|---|
| round index | `references/round-economy.md:14` — "one fix cycle, keyed to the head SHA" |
| substantive predicate | `references/round-economy.md:33`, restated at `SKILL.md:77` |
| nit exclusion | `references/round-economy.md:37` — "nit-only rounds don't count against the budget" |
| `DUPLICATE` exclusion | **does not exist** — this is round-3 finding 1 |
| dominance floor | `references/round-economy.md:69` — "four or more substantive findings" |

They are not consistent with each other, and every attempt so far has patched one pair and
broken a third. **Do not patch the four findings below individually.** Define the counting model
once, as one explicit spec, and derive the prose from it.

Escalation option 3 from the file's own tripwire section was chosen by the operator: *"the design
is wrong and review is finding it out one symptom at a time."*

## 2. The four open findings

All from `chatgpt-codex-connector`, all P2, all on PR #11, all **unresolved**. IDs are live.

| Thread ID | Comment ID (for the 👍) | Finding |
|---|---|---|
| `PRRT_kwDOSnPF4c6T5h8j` | `PRRC_kwDOSnPF4c7ZxR1j` | Exclude duplicate threads from the substantive count |
| `PRRT_kwDOSnPF4c6T5h8k` | `PRRC_kwDOSnPF4c7ZxR1k` | Define how nit-only cycles affect the round index |
| `PRRT_kwDOSnPF4c6T5h8m` | `PRRC_kwDOSnPF4c7ZxR1l` | Treat zero unresolved as closure rather than completeness |
| `PRRT_kwDOSnPF4c6T5h8n` | `PRRC_kwDOSnPF4c7ZxR1n` | Capture round and cluster identifiers before measuring the outcome |

Read the full bodies with:

```bash
gh api graphql -f query='
{ repository(owner:"rookslog",name:"pr-review-journal"){
    pullRequest(number:11){ reviewThreads(first:60){nodes{
      id isResolved comments(first:1){nodes{id body}}}}}}}' \
 --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false) | .comments.nodes[0].body'
```

### The two hard contradictions

**(a) Nit-only cycles vs the SHA-keyed index.** `round-economy.md:14` says a round is keyed to
the head SHA. `round-economy.md:37` says nit-only rounds don't count against the budget. After a
substantive round 1 and a nit-only round 2, a substantive review of the next SHA is
*simultaneously* round 3 (must stop, per the tripwire) and the second budgeted round (normal).
Codex's suggested resolutions: a separate budget index that skips nit-only cycles, **or** such
cycles advance the index but cannot themselves fire the tripwire. Pick one deliberately.

**(b) Duplicates inflate two thresholds at once.** The substantive predicate
(`round-economy.md:33`) excludes `REJECTED_FALSE_POSITIVE`, `OBSOLETE` and nits — but not
`DUPLICATE`. So two defects reported by two reviewers become four "substantive findings",
inflating both the four-finding dominance floor and the per-round tripwire total. Note this
interacts with a change made in round 2: clustering now explicitly keeps **one fix, N verdicts**,
so distinct-but-clustered findings legitimately produce N threads. The counting model has to
distinguish *duplicate report of one finding* from *distinct findings sharing a cause* — they
count differently and the file currently conflates them.

### The two independent ones

**(c) `SKILL.md:185` overclaims.** It says zero-unresolved is "a completeness check, not a
correctness check." Codex is right that even completeness is too strong: a thread can be resolved
with **no reply at all**, so the count proves neither. Verify reply presence and validity
independently.

**(d) The journal cannot measure what the file claims.** Verified against code, not inferred:
`ThreadRecord` at `tools/review-journal/review_journal.py:797` carries `created_at`, `reviewer`,
`category`, `verdict_commit` — but **no reviewed head SHA and no cluster/root-cause id**. The
closing paragraph of `round-economy.md` claims the journal "stores the data needed to check
whether round count tracks cluster-blindness." That is false as written. Either add the two
fields or delete the claim. Recommendation from the outgoing agent: **delete the claim** — it is
the claim that is wrong, and adding schema to support an unrun measurement is speculative. This
is a judgment call, not a settled one.

## 3. Definition of done

1. One explicit counting-model spec, in one place, that resolves (a) and (b) rather than
   patching them. Prose in `SKILL.md` and `round-economy.md` derives from it — remember **both
   files carry a copy of every rule**, and a defect in a rule is a defect in two places.
2. (c) and (d) dispositioned.
3. All four threads get a reply carrying a ` ```review-verdict ` block, a 👍 on the original
   comment, and a resolve. Format and vocabulary: `skills/pr-review-triage/references/verdicts.md`.
   Reply, react, resolve are three separate obligations here; all three are required.
4. A PR against `main`.

**Pair threads to reply bodies by a key re-derived from the thread, never by array position.**
The outgoing agent shipped all six round-1/2 verdicts one row off by indexing a zsh array from 0
(zsh is 1-indexed), then auto-resolved them — wrong *and* closed, while reporting `0 unresolved`.
That incident is what produced finding (c). Audit afterwards by printing each thread's finding
title next to its reply's `finding_category` and reading the rows.

## 4. Operational gotchas

- **This working tree is a live deployment.** `~/.claude/skills/pr-review-journal-dev` is a
  symlink to this repo, loaded as `pr-review-journal@skills-dir`. Edits to `skills/` change the
  running skill immediately, and **checking out a branch changes what is deployed.** The pinned
  `0.1.0` marketplace install was uninstalled to free the plugin name; restore it with
  `claude plugin install pr-review-journal@pr-review-journal`.
- Validate with `claude plugin validate .` before pushing.
- The `description:` frontmatter in `SKILL.md` must stay **≤1024 characters** (currently 938).
  It is the P1 from round 1.
- `@codex` task delegation is **not** available on this repo — Codex Cloud has no environment for
  it (bot comment, 2026-06-19). Review works; task hand-off does not.

## 5. History, so the round count is not restarted

PR #11 ran **three rounds** before merge, not one. The summary comment posted on #11 says "Round
1 summary: 6 findings" — that is wrong, by the very definition the PR introduced.

| Round | Head | Findings | Notes |
|---|---|---|---|
| 1 | `b2efea9` | 3 | |
| 2 | `8a57837` | 3 | one caused by the round-1 push |
| 3 | `7afd724` | 4 | **3 of 4 self-inflicted by round-1/2 fixes**; landed 5m14s *after* merge |

The PR was merged at 22:20:51Z; round 3 arrived at 22:26:05Z. It was merged on a
`0 unresolved` check without waiting for the round, despite this plugin shipping
`references/monitoring.md` with the exact wait pattern. Prior codex turnaround on this PR was
10–17 minutes, so the wait was bounded and known.

Under the file's own budget, **this is past the tripwire.** Round 3 carrying four substantive
findings is where it says to stop patching and escalate — which is why you are reading a design
handoff rather than a fix.

## 6. Why this was handed over

Two reasons, and the second is the load-bearing one.

The operator chose escalation option 3, and the counting model is a design problem rather than a
wording problem.

More importantly: **every finding on this PR came from codex acting as an independent lens on
Claude's work.** That independence is what made them good — three of round 3's four are defects
Claude introduced while fixing round 2. Having Claude also author the repair keeps the same
lineage on both sides of the gate. Handing the authoring to a different lineage preserves the
property that has been doing the work.

The corollary applies in reverse and should be honoured: **this PR should be reviewed by
something other than codex.** `skills/pr-reviewer/SKILL.md` is this plugin's reviewer-side skill
and has never been exercised on a real PR.

## 7. Standing caveat on the file itself

`round-economy.md` is not validated guidance. Its status section is accurate and should stay
that way: the round budget, the 3-round tripwire and the >50% dominance threshold are
**Conjecture**; the 26-findings/9-rounds evidence is **Observed on one corpus** (one repo, one
reviewer, one author); and no fresh-context agent has ever been given a multi-round PR with the
file withheld, so **no GREEN result exists**. Whatever counting model you specify inherits that
status. Do not let the act of formalising it read as evidence that it is calibrated.
