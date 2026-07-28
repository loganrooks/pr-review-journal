# Outcome-linkage — giving the verdict ledger a ground-truth signal

> Status: **reserved, not built.** This documents a schema *reservation* (the
> `extras.outcome` shape) and the process that would populate it. It does not
> build the analysis engine, and it does not decide where that engine should
> live. See "Scope" below.

## Why

`VISION.md` frames this repo as a reviewer-quality **flywheel**: the accumulated
verdict trail is a dataset for (1) detecting sycophancy vs. warranted pushback in
the responder, and (2) improving reviewer-agent design. Both depend on a question
the current ledger cannot answer:

> **Was a verdict actually correct?**

Accept-rate can't tell you. "Accepted because the finding was right" and "accepted
to be agreeable" produce the *identical* record — `verdict: ACCEPTED`. The same
ambiguity runs the other way: a `REJECTED_FALSE_POSITIVE` is either warranted
pushback or a real defect waved away. The ledger captures the *decision*; it does
not capture what reality said about that decision afterward.

The only thing that disambiguates them is **what happened after the verdict**:

- An `ACCEPTED` fix that was **reverted or regressed** a week later → the
  acceptance was probably wrong (a candidate sycophantic accept).
- A `REJECTED_FALSE_POSITIVE` whose predicted problem **later occurred**, or which
  was **re-opened and then accepted** → the rejection was wrong (an unwarranted
  dismissal).
- An `ACCEPTED` fix that **stuck**, or a rejection that **stayed irrelevant** →
  the verdict held up.

That after-the-fact signal is *outcome-linkage*. This document reserves a place to
record it.

## What this reserves: `extras.outcome`

Outcome is recorded under each thread's existing `extras` map — the channel the
tool already documents for "a metrics consumer" and "a learning system" to attach
data post-hoc. Outcome-linkage is exactly that: it is observed *after merge*, by
an external process or a human audit, never at verdict time and never by the tool.

```json
"extras": {
  "outcome": {
    "status": "CONTRADICTED",
    "signal": "revert",
    "ref": "9c1f2ab",
    "observed_at": "2026-06-10T14:00:00Z",
    "notes": "Accepted CR fix reverted a week later — it broke relaunch."
  }
}
```

| Field         | Values | Meaning |
|---------------|--------|---------|
| `status`      | `UNKNOWN` / `CONFIRMED` / `CONTRADICTED` | Was the verdict borne out by reality? Absent ⇒ `UNKNOWN`. |
| `signal`      | `revert` / `regression` / `reopened` / `vindicated` / `audit` / `null` | The evidence behind the status. |
| `ref`         | string / `null` | Commit / issue / PR / thread evidencing the outcome. |
| `observed_at` | ISO-8601 / `null` | When the outcome was observed. |
| `notes`       | string / `null` | Human note. |

The **quality signal** comes from crossing `status` with the thread's `verdict`:

| verdict | + outcome | ⇒ reads as |
|---|---|---|
| `ACCEPTED` / `ACCEPTED_MODIFIED` | `CONTRADICTED` (revert / regression) | candidate **sycophantic acceptance** |
| `ACCEPTED` / `ACCEPTED_MODIFIED` | `CONFIRMED` | acceptance held up |
| `REJECTED_*` | `CONTRADICTED` (reopened / vindicated) | **unwarranted dismissal** |
| `REJECTED_*` | `CONFIRMED` | **warranted pushback** |

That interpretation is *engine logic*. The schema only carries the raw observation;
nothing in this tool computes the cross-product.

The `validate` subcommand shape-checks `extras.outcome` when present (valid
`status`/`signal`), so a typo can't silently corrupt the dataset — but the key is
never required, because the tool never writes it and most threads never carry it.

## How outcome gets captured (process — design only)

Two complementary mechanisms, ported from the ground-truth-anchoring discipline in
the AI failure-mode research that informs this family. Neither is built here.

1. **Post-merge signal tracking (automatic, high-volume, noisy).** Watch the
   merged history for events that contradict a prior verdict: a commit that
   reverts the `verdict_commit` of an `ACCEPTED` thread → `status: CONTRADICTED,
   signal: revert`; a bug later bisected to that commit → `signal: regression`; a
   rejected finding that is re-raised and then accepted → `signal: reopened`. Cheap
   and continuous, but only ever produces *negative* evidence (it sees contradiction,
   rarely confirmation).

2. **Periodic ground-truth audit of a sample (manual, low-volume, high-quality).**
   Draw a random sample of decided verdicts and have a grader assign an outcome
   (`signal: audit`). This is where the research's experimental discipline applies
   directly, to keep the audit honest:
   - **Grade unprimed.** The grader must not be told the verdict was suspected
     sycophantic — priming inflated the apparent effect in the original sycophancy
     experiment.
   - **Grade independently, n ≥ 3.** Self-grading over-reported drift; independent
     graders at n = 3 corrected it. The audit should not let the responding agent
     grade its own past verdicts.

Confirmation generally comes from (2); contradiction mostly from (1). A verdict
with no outcome from either is simply `UNKNOWN` — the honest default.

## Scope — what this does *not* do

This PR is the **cheap-now half** of cross-repo **OQ-004**. It deliberately stops
short of the rest:

- **No detection / aggregation engine.** Nothing here computes a sycophancy rate,
  clusters findings, or scores reviewers. The flywheel is still latent.
- **No decision on where the engine lives.** Whether the aggregation + learning
  layer belongs *inside* this repo or as a *separate consumer* attached to the
  verdict records is **OQ-004 part (1)**, still open. Reserving the field inside
  the already-free-form `extras` map (rather than promoting it to a first-class
  top-level field) is the low-commitment choice that keeps that question open: if
  OQ-004 later puts the engine inside the journal, promoting `extras.outcome` to a
  top-level `outcome` field is a clean, mechanical migration.
- **No change to what the tool writes.** Output shape is unchanged (`extras` was
  always consumer-owned and free-form), so `schema_version` stays `1.0`. The only
  code change is that `validate` now *recognizes and shape-checks* the reserved key.
- **No new burden on the responder.** Verdict blocks are unchanged. Outcome is
  attached later, by audit or consumer — not something a reviewer or responder
  fills in at decision time.

Why reserve it now if the engine doesn't exist yet? Because the data is the
expensive part. Recording verdicts without ever capturing their outcome is free
today and very costly to reconstruct later — you would have to re-investigate every
historical PR to ask "did this stick?". Standardizing the shape now means every
verdict recorded from here forward can carry its outcome in a consistent place the
day the engine is built.

## See also

- `VISION.md` — the reviewer-quality flywheel this signal feeds.
- `agentic-ecosystem` `OPEN_QUESTIONS.md` **OQ-004** — the cross-repo question this
  partially resolves (engine location + the sycophancy ground-truth requirement).
