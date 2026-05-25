# pr-review-journal

A per-PR review journal that records every reviewer recommendation and the
project's verdict on it, paired with two Claude Code skills that encode the
reviewer-side and orchestrator-side discipline.

Designed to work with any GitHub-app reviewer — CodeRabbit, Codex (via
`chatgpt-codex-connector`), Claude PR review (via `agentic-ops/review.yml`),
GitHub Copilot review, Greptile, Qodo, or an in-house bot — by treating
reviewer behaviour as **config**, not code.

The tool is Python stdlib + shell, depends only on `python3` and `gh`. Runs in
any repo where `gh` is authenticated; no install required.

---

## What's in the box

| Path | Purpose |
|---|---|
| `tools/review-journal/review_journal.py` | The journal tool (1 Python module, stdlib only) |
| `tools/review-journal/sync-pr.sh`, `extract-pr.sh` | Shell wrappers around the tool |
| `tools/review-journal/install/ci-check.yml` | Drop-in GitHub Actions workflow (warning mode) |
| `tools/review-journal/tests/` | 35 shell tests (captured fixtures + goldens; no network) |
| `skills/pr-review-triage/` | Claude Code skill — orchestrator side (how to dispose of findings) |
| `skills/pr-reviewer/` | Claude Code skill — reviewer side (how to issue findings cleanly) |
| `.claude-plugin/plugin.json` | Claude Code plugin manifest |

---

## Install as a Claude Code plugin

```text
/plugin marketplace add loganrooks/pr-review-journal
/plugin install pr-review-journal@loganrooks/pr-review-journal
```

This installs both skills into your Claude Code setup. The tool itself
(`tools/review-journal/`) is available at `${CLAUDE_PLUGIN_ROOT}/tools/review-journal/`
inside skill instructions; for use outside Claude Code (CI, ad-hoc) you'll also
want a vendored copy in your repo — see below.

---

## Install the tool into a consumer repo

The tool is portable: copy the directory + a config file.

```bash
# 1. Vendor the tool (pin to a tag for reproducibility).
git clone --depth 1 --branch v0.1.0 https://github.com/loganrooks/pr-review-journal.git /tmp/prj
cp -r /tmp/prj/tools/review-journal otherrepo/tools/

# 2. Create a minimal .review-journal.json at the consumer repo's root.
cat > otherrepo/.review-journal.json <<'EOF'
{
  "enforcement_mode": "warning",
  "reviewers": ["coderabbitai", "chatgpt-codex-connector"],
  "journal_dir": ".planning/review-journal"
}
EOF

# 3. (Optional) Install the CI workflow snippet.
cp /tmp/prj/tools/review-journal/install/ci-check.yml otherrepo/.github/workflows/review-journal.yml
```

A submodule, subtree, or one-liner installer would all also work; pick what
fits your repo's vendoring conventions.

---

## The verdict-block discipline

Every reply on a review thread starts with a fenced block:

````markdown
```review-verdict
verdict: ACCEPTED_MODIFIED
commit: 14b240b
finding_category: source-resolution-correctness
reviewer: chatgpt-codex-connector
notes: PID-first match; bundle fallback kept for relaunch-between-pick-and-start.
```
````

Verdict vocabulary (eight values):

- `ACCEPTED`, `ACCEPTED_MODIFIED` — finding accepted; `commit` required
- `DEFERRED` — accept but defer the action; `notes` required
- `REJECTED_FALSE_POSITIVE`, `REJECTED_BAD_FIT`, `REJECTED_REGRESSION` — `notes` required
- `OBSOLETE` — finding no longer applies; `commit` required
- `DUPLICATE` — same as another thread

Full per-verdict semantics and config reference: see
[`tools/review-journal/README.md`](tools/review-journal/README.md).

---

## Quick start

```bash
# Sync the current verdict state (parses existing blocks; does not infer).
bash tools/review-journal/sync-pr.sh 7 --repo owner/repo

# Backfill verdicts for threads that pre-date the discipline.
bash tools/review-journal/extract-pr.sh 7 --repo owner/repo
```

Output lands at `<journal_dir>/pr-7.json` + an `index.json` summary across
all PRs.

---

## Tests

```bash
bash tools/review-journal/tests/run-tests.sh
```

35 tests covering block parsing, sync schema, inference, portability, config,
profile flexibility, extensibility, provenance, and robustness. Tests use
captured fixtures and golden expected outputs; no network.

---

## History

Extracted from [`loganrooks/tap-n-filter`](https://github.com/loganrooks/tap-n-filter),
where it started as a local fix for a workflow problem: rejecting a reviewer's
suggestion (because it conflicts with a local convention CR's training data
doesn't know about) leaves no durable record of *why*. The journal mechanises
the "Reasoning over acceptance" principle.

The standalone-repo extraction (this repo) also fixed several upstream bugs
identified by Codex review on the first port consumer; see the changelog for
v0.1.0.

---

## License

MIT
