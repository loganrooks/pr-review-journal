# Monitoring PR Activity

When the orchestrator triggers a review (`@codex review`, push a fix, request CI) and then needs to wait for the response, polling is wasteful and waiting for the user to nudge is rude. The right tool depends on how many notifications you need and whether the wait has a natural end.

## Three patterns

| Pattern | How many notifications | Right tool | When |
|---|---|---|---|
| One signal, known end | 1 | `Bash` with `run_in_background` + `until` loop | "Tell me when CI finishes." "Tell me when Codex finishes a pass (findings or clean)." |
| Per-occurrence, indefinite | N (unbounded) | `Monitor` with `persistent: true` | "Tell me every time a new comment lands on PR #N during this session." |
| Per-occurrence, known end | N (bounded) | `Monitor` with a loop that exits | "Emit each CI check as it lands, stop when the run completes." |

The single most common mistake is using `Monitor` with `tail -f` or `while true` when you only need one notification. An unbounded command stays armed until timeout even after the event has fired. For "wake me when X happens once," use `Bash` with `run_in_background` and an `until` loop that exits.

## Pattern 1 — wait for one signal (single notification)

Use case: you posted `@codex review` (the reliable trigger — a bare push may *not* auto-re-review; see the note) and need to know when the pass *finishes*. Codex is **split-channel**: a pass with **findings** lands as a review object keyed to the pushed commit SHA; a **clean** pass lands as a **PR issue comment** ("…Didn't find any major issues") with *no review object at all*. You must poll **both** — polling reviews alone runs a clean pass to timeout.

> **Codex specifics (verified 2026-06-08; clean pass confirmed live on probe #10).**
> - **Findings:** a `COMMENTED` review titled "Codex Review", stamped `commit.oid`, with ≥1 inline comment. **Key on `commit.oid == head SHA`, not a review *count*** — thread-reply review objects inflate counts.
> - **Clean:** a PR **issue comment** "Codex Review: Didn't find any major issues. Hooray!" (plus a `+1` reaction on the PR body), and **no review object**. There is *no* zero-inline-comment review for a clean pass — polling reviews alone misses it entirely.
> - **`[bot]` login gotcha:** GraphQL `reviews.author.login` is `chatgpt-codex-connector`; REST `issues/N/comments[].user.login` is `chatgpt-codex-connector[bot]`. Match **both** — filtering the REST surface by the bare login silently matches nothing (this bit the very probe that found the clean channel).
> - **Timeout still mandatory:** the head may advance past Codex's last action, or its push-event ingestion may **silently drift and post nothing** (openai/codex#15477). A bare 👀-without-review is an *outage* (#3808), not progress — don't wait on it.
> - **Trigger caveat:** one `@codex review` arms the PR, but auto-re-review on later pushes is **non-deterministic** (followed every #9 push, *none* of #8's across 10.6h; GitHub exposes no reliable bot re-review hook) — **re-post `@codex review` after each push** and keep the timeout generous. See `docs/design/reviewer-capability-interface.md` §6.4/§10/§11.

```bash
PR=9
REPO=loganrooks/philpapers-mcp
OWNER=${REPO%/*}; NAME=${REPO#*/}
GQL_BOT=chatgpt-codex-connector          # GraphQL reviews.author.login (NO suffix)
REST_BOT='chatgpt-codex-connector[bot]'  # REST comments .user.login (WITH [bot])

SHA=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid)
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # set BEFORE you post @codex review; a clean comment must be newer
DEADLINE=$(( $(date +%s) + 1200 ))     # head may move, or push-event ingestion may drift and post nothing

pass_done() {
  # Codex is SPLIT-CHANNEL. (1) FINDINGS = NEW UNRESOLVED review threads from Codex
  # created after your trigger. (2) a CLEAN pass = a PR ISSUE COMMENT "...find any
  # major issues" with NO review object. (3) some repos run @codex review as a cloud
  # AGENT that posts a "no changes needed" review WITHOUT opening any thread — treat
  # that (a Codex review after the trigger, no new unresolved threads) as converged.
  # Poll all three; mind the [bot] login on REST.
  local f c r
  # (1) FINDINGS = NEW UNRESOLVED review threads authored by Codex, created after the
  #     trigger. Counting a review's inline TOTAL instead misfires: a re-trigger reply
  #     INTO an already-resolved thread (or a cloud-agent confirmation) inflates the
  #     count and falsely reports findings. Gate on thread RESOLUTION, not raw count.
  f=$(gh api graphql -f query='
    query($o:String!,$n:String!,$p:Int!){repository(owner:$o,name:$n){
      pullRequest(number:$p){reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{author{login} createdAt}}}}}}}' \
    -F o="$OWNER" -F n="$NAME" -F p="$PR" \
    --jq "[.data.repository.pullRequest.reviewThreads.nodes[]
           | select(.isResolved | not)
           | select(.comments.nodes[0].author.login==\"$GQL_BOT\" and (.comments.nodes[0].createdAt > \"$SINCE\"))]
          | length" 2>/dev/null)
  if [ "${f:-0}" -gt 0 ] 2>/dev/null; then echo "findings($f)"; return 0; fi
  # (2) clean channel — REST ([bot] login): a clean comment newer than your trigger.
  # ?since= filters server-side to comments updated since the trigger (small set),
  # so the clean comment can't hide past the default 30-per-page window. (Prefer
  # this to `--paginate`, which composes badly with a `length` jq — it counts
  # per-page, not a total.)
  c=$(gh api "repos/$REPO/issues/$PR/comments?since=$SINCE&per_page=100" \
        --jq "[.[] | select(.user.login==\"$REST_BOT\"
               and (.created_at > \"$SINCE\")
               and (.body | test(\"find any major issues\")))] | length" 2>/dev/null)
  if [ "${c:-0}" -gt 0 ] 2>/dev/null; then echo clean; return 0; fi
  # (3) cloud-agent CONFIRMATION: a Codex review submitted after the trigger on the
  #     head SHA, with NO new unresolved thread (step 1 was 0) and no clean comment —
  #     an agentic "no changes needed" summary. Codex responded; nothing to fix.
  r=$(gh api graphql -f query='
    query($o:String!,$n:String!,$p:Int!){repository(owner:$o,name:$n){
      pullRequest(number:$p){reviews(last:10){nodes{author{login} submittedAt commit{oid}}}}}}' \
    -F o="$OWNER" -F n="$NAME" -F p="$PR" \
    --jq "[.data.repository.pullRequest.reviews.nodes[]
           | select(.author.login==\"$GQL_BOT\" and .commit.oid==\"$SHA\" and (.submittedAt > \"$SINCE\"))]
          | length" 2>/dev/null)
  if [ "${r:-0}" -gt 0 ] 2>/dev/null; then echo "clean (agent confirmation; no new threads)"; return 0; fi
  return 1
}

until OUT=$(pass_done); do
  [ "$(date +%s)" -ge "$DEADLINE" ] && { echo "timeout: no findings-review or clean-comment on $SHA — verify (slow, head moved, or ingestion drift) and re-post @codex review"; break; }
  sleep 30
done
[ -n "$OUT" ] && echo "Codex pass on PR $PR ($SHA): $OUT"
```

Run via `Bash` with `run_in_background: true`. The loop exits when **either** a findings-review on the head SHA **or** a clean issue-comment appears, **or** the deadline trips — so it neither hangs on a clean pass (the old review-only version did) nor declares a silent success. *Validated 2026-06-08:* probe #10's clean pass posted `Codex Review: Didn't find any major issues` ~85s after the trigger (issue comment, no review object); closed #9 returns `findings(2)` for head `e91c9eb`. Note: a pass finishing is "this pass finished", **not** "ready to merge" — merge-readiness is `unresolvedThreadCount==0` (reviewer-agnostic; see the quick-decision table), since Codex's findings stay on its review object after you resolve the threads.

Variant — **generic fallback for a reviewer with no clean-signal** (most non-Codex bots). Such a reviewer can only be observed to *post*; "clean" is unprovable (it just stays silent), so this wait must be **timeout-bounded** and the no-review outcome treated as "confirm before merge", never as a silent success (see the RCI degradation rule, §10):

```bash
SINCE="2026-05-22T22:00:00Z"
DEADLINE=$(( $(date +%s) + 1800 ))   # 30-min cap; silence ≠ clean for these bots
until gh pr view "$PR" --repo "$REPO" --json reviews \
  --jq "[.reviews[] | select(.submittedAt > \"$SINCE\")] | length" | grep -qv '^0$'; do
  [ "$(date +%s)" -ge "$DEADLINE" ] && { echo "no review within window — confirm before treating as clean"; break; }
  sleep 30
done
```

## Pattern 2 — watch ongoing PR activity (per-occurrence, indefinite)

Use case: PR is open, you'll be addressing findings as they arrive across multiple reviewer passes. You want a chat notification each time a new comment from CR / Codex lands so you can switch contexts to address it.

```bash
# Emit one line per new comment from the watched reviewers.
PR=8
REPO=loganrooks/tap-n-filter
REVIEWERS='coderabbitai|chatgpt-codex-connector|copilot-pull-request-reviewer\[bot\]'
LAST_SEEN=$(date -u +%Y-%m-%dT%H:%M:%SZ)

while true; do
  gh api "repos/$REPO/pulls/$PR/comments?since=$LAST_SEEN" \
    --jq ".[] | select(.user.login | test(\"^($REVIEWERS)$\")) | \"\(.user.login) commented on \(.path):\(.line // 0): \(.body[0:120])\"" \
    2>/dev/null || true
  LAST_SEEN=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sleep 30
done
```

Run via `Monitor` with `persistent: true`. Each new comment becomes one chat notification. Stop with `TaskStop` when you're done with the PR.

Important: `|| true` keeps a transient `gh` failure from killing the monitor. Network blips happen.

## Pattern 3 — watch CI to completion (per-occurrence, bounded)

Use case: you pushed a fix; want one notification per check as it completes, and the monitor should stop when all checks have terminal state. No polling after CI is done.

```bash
PR=8
REPO=loganrooks/tap-n-filter
prev=""
while true; do
  s=$(gh pr checks "$PR" --repo "$REPO" --json name,bucket 2>/dev/null) || { sleep 30; continue; }
  cur=$(jq -r '.[] | select(.bucket!="pending") | "\(.name): \(.bucket)"' <<<"$s" | sort)
  # Emit only checks new since last poll.
  comm -13 <(echo "$prev") <(echo "$cur")
  prev=$cur
  # Exit when no checks remain pending.
  jq -e 'all(.bucket!="pending")' <<<"$s" >/dev/null && { echo "CI complete on PR $PR"; break; }
  sleep 30
done
```

Run via `Monitor` (non-persistent). Each check completion is one notification; the final "CI complete" line is the last one.

## Coverage — silence is not success

A monitor whose filter matches only the happy path goes silent when the unhappy path happens. Before arming a monitor for any waited-on state, ask: *if the thing crashed right now, would my filter emit anything?* If not, widen it.

Wrong (silent on crash, timeout, or any non-success exit):

```bash
tail -f deploy.log | grep --line-buffered "Deploy succeeded"
```

Right (alternation covering progress + the failure signatures you'd want to act on):

```bash
tail -f deploy.log | grep -E --line-buffered "Deploy succeeded|Deploy failed|Traceback|FATAL|Killed"
```

For a PR-review wait, the failure signatures include:
- **No review lands on the head SHA** — the head advanced past the reviewer's last review (more pushes, a merge commit), or its push-event ingestion drifted and posted nothing (openai/codex#15477). A review-only wait then stays silent forever. **For Codex specifically, "no review object" is NOT the same as "clean"** — a clean pass is a PR issue comment ("…find any major issues"), not a review object, so Pattern 1 polls that channel too (and matches the REST `[bot]` login). Always bound the wait with a timeout-then-verify, and remember "ready to merge" is `unresolvedThreadCount==0`, not a reviewer signal. (A bare 👀-without-review is an outage, not progress — don't wait on it.)
- Codex posts "needs environment setup" instead of a review
- CR's quota is exhausted (the "Review skipped" status check)
- The reviewer's GitHub App was uninstalled mid-review
- A reviewer posts a question rather than findings (a thread that needs your reply before the wait makes sense)

The poll-based monitors above survive these by checking concrete state — a review whose `commit.oid` is the head SHA, its inline-comment count, the list of checks — rather than a review *count* (inflated by thread-reply review objects) or scraped prose.

## Pipe-buffering gotcha

Without `--line-buffered`, grep buffers stdout when output is going to a pipe. Events that look "instant" in interactive mode arrive minutes late through a monitor pipeline.

```bash
# Wrong — buffered
tail -f log | grep "ERROR"

# Right
tail -f log | grep --line-buffered "ERROR"
```

`awk` has `fflush()`, `sed` has `-u`, Python has `python3 -u` or `sys.stdout.flush()` — every tool in the pipe needs explicit flushing.

## Combine with `PushNotification` for high-signal events

`Monitor` events become chat notifications, which the user sees in the transcript. If an event needs the user's *immediate* attention (a critical finding posted, CI failed in a way that blocks merge, a reviewer raised a security concern), `PushNotification` sends a push to the user's device — useful when the user has switched away from the chat.

A reasonable rule of thumb: monitor events are passive (the user sees them next time they check the chat); push notifications are active (the user gets pinged on their phone). Use push for things that change what the user would do next, not for routine status flips.

## Anti-patterns

1. **Unbounded command for single notification.** `Monitor` with `tail -f log | grep -m 1 "Ready"` looks like it should fire once and stop. It doesn't — `tail` keeps running because the log doesn't close, and `grep -m 1` only stops *grep*. The monitor stays armed until timeout. Use Pattern 1 (Bash with `run_in_background` and an `until` loop) instead.

2. **Raw log piping.** `Monitor` with `tail -f huge.log` floods the chat. Monitors that produce too many events are automatically stopped. Filter aggressively at the source.

3. **No transient-failure handling.** `Monitor` with a poll loop that calls `gh api` without `|| true` dies on the first network hiccup. Always swallow transient errors in the poll body.

4. **Too-tight poll interval for remote APIs.** GitHub rate-limits at 5000 req/hr per token. A 1-second poll burns the quota fast. Use 30s+ for remote API polls; 0.5-1s is fine for local checks (file existence, log line presence).

5. **Forgetting to stop.** Persistent monitors keep running until `TaskStop` or session end. If you've moved on from a PR, stop the monitor so the next session doesn't inherit unrelated notifications. Use `TaskList` to see active monitors and `TaskStop` to kill specific ones.

## Quick decision: which tool for the PR-review-triage workflow

| Situation | Use |
|---|---|
| "Tell me when Codex / CR finishes a pass (findings or clean) on PR #N" | Bash `run_in_background` + `until` loop (Pattern 1) |
| "Tell me about new activity on PR #N while I work on other things" | Monitor persistent (Pattern 2) |
| "Tell me as each CI check finishes; stop when CI is done" | Monitor bounded loop (Pattern 3) |
| "Tell me when `unresolvedReviewThreadCount` hits zero" | Bash `run_in_background` + `until` loop, poll via GraphQL |
| "Tell me when the PR's mergeable state changes" | Bash `run_in_background` + `until` loop |

The skill's `pr-review-triage` workflow uses Pattern 1 most often: trigger a review, wait for the single completion notification, switch back to triage when it lands.
