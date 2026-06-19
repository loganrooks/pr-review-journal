# Vision

`pr-review-journal` exists at two levels: the thing that ships today (a
verdict ledger) and the purpose it serves (a reviewer-quality flywheel).

## Today — a verdict ledger ("reasoning over acceptance")

Every reviewer recommendation on a PR gets a parseable verdict: accepted,
modified, deferred, rejected (and why), obsolete, or duplicate. The point is
the *why*. Rejecting a reviewer's suggestion — because it conflicts with a
local convention the reviewer's training data doesn't know about — otherwise
leaves no durable record. Hidden reasoning is the failure mode the journal
catches. This is shipped (`v0.1.0`).

## The point — a reviewer-quality flywheel

The accumulated verdict trail is a dataset, not just an archive. Across many
PRs it drives two improvement loops:

1. **Responder quality — sycophancy vs. warranted pushback.** An agent
   answering CodeRabbit / Codex can rubber-stamp findings just to close
   threads. The verdict trail plus its reasoning is the evidence to detect
   that — and to recognise *warranted* pushback (a reasoned rejection that
   protects a local convention) as the healthy behaviour it is.
2. **Reviewer design — build better reviewers.** Finding classes that are
   consistently rejected are noise to suppress; real defects that slipped
   through and caused later bugs are gaps to close. Fed back into
   reviewer-agent design, this raises the quality of the PRs and the codebase
   — not just the tidiness of the threads.

The ledger is the instrument; the flywheel is what the instrument is for.

## What this is *not* — the measure-vs-implement fence

The journal **measures and disciplines** the reviewer↔responder interaction.
It does not **implement** reviewers. It is vendor-agnostic by design (reviewer
behaviour is config, not code), so it improves *any* reviewer — CodeRabbit,
Codex, `agentic-ops/review.yml`, an in-house bot — without owning any of them.
Nor does it decide what to *do* with a PR (merge, escalate, loop); that
belongs to the consumer driving the review.

## Honest status

The ledger ships. The **flywheel is latent, not built.** The per-thread
`extras` map already reserves extension points for "a metrics consumer"
(`time_to_resolution_hours`) and "a learning system" (`embeddings_id`,
`cluster_id`, `learned_category`), but no aggregation or learning layer exists
yet. Naming the flywheel as the purpose is the first step toward building it
deliberately rather than by accident.

## The hard part — sycophancy needs ground truth

Accept-rate cannot measure sycophancy. Agreeing with a *correct* finding is
good; the failure is agreeing with a *wrong* one to be agreeable — and counts
can't tell those apart. Distinguishing them needs an **outcome signal**
attached to each verdict:

- Was an **accepted** finding later reverted, or did it introduce a
  regression? (a false-accept — the sycophancy signal)
- Was a **rejected** finding later vindicated, or re-opened? (this calibrates
  pushback quality)

The verdict schema carries no outcome-linkage field today. Adding one is cheap
now and expensive to backfill, so it is a near-term design question, not a
someday one. This is ground-truth anchoring applied to the responder.

## Why a separate repo

"Reasoning over acceptance" is general: it was born in `tap-n-filter`, is used
in `erebus`, and serves many reviewers and many responders at once. A tool
with that many independent consumers stays independent rather than folding
into any one of them. The cross-family decision recording this — and the open
questions on where the flywheel *engine* should live and what outcome-linkage
sycophancy detection requires — live in the `agentic-ecosystem` governance
repo (ADR-001 and OQ-004).
