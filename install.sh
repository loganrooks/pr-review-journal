#!/usr/bin/env bash
# Installer for pr-review-journal — drops the tool directory into a consumer
# repo's tools/review-journal/ and (optionally) installs the CI workflow.
#
# Skills are NOT installed by this script — for skills, install the Claude
# Code plugin:
#
#   /plugin marketplace add loganrooks/pr-review-journal
#   /plugin install pr-review-journal@pr-review-journal
#
# Usage (run from the consumer repo's root):
#
#   # Install pinned to a tag:
#   curl -fsSL https://raw.githubusercontent.com/loganrooks/pr-review-journal/v0.1.0/install.sh \
#     | VERSION=v0.1.0 bash
#
#   # Also drop the CI workflow snippet:
#   curl -fsSL https://raw.githubusercontent.com/loganrooks/pr-review-journal/v0.1.0/install.sh \
#     | VERSION=v0.1.0 INSTALL_CI=yes bash
#
#   # Custom install path:
#   curl -fsSL https://raw.githubusercontent.com/loganrooks/pr-review-journal/v0.1.0/install.sh \
#     | VERSION=v0.1.0 TARGET=vendor/review-journal bash
#
# Env vars:
#   VERSION     — git tag/branch to install (required; pin to a tag like v0.1.0)
#   TARGET      — consumer-side install path (default: tools/review-journal)
#   INSTALL_CI  — set to "yes" to also drop install/ci-check.yml into
#                 .github/workflows/review-journal.yml

set -euo pipefail

VERSION="${VERSION:-}"
TARGET="${TARGET:-tools/review-journal}"
INSTALL_CI="${INSTALL_CI:-no}"

if [ -z "$VERSION" ]; then
  echo "error: VERSION env var is required (e.g., VERSION=v0.1.0)" >&2
  echo "       pinning to a tag means you choose when to upgrade." >&2
  exit 2
fi

REPO_URL="https://github.com/loganrooks/pr-review-journal.git"

TMPDIR="$(mktemp -d -t pr-review-journal-install.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Cloning $REPO_URL @ $VERSION ..."
git clone --quiet --depth 1 --branch "$VERSION" "$REPO_URL" "$TMPDIR/prj"

src="$TMPDIR/prj/tools/review-journal"
if [ ! -d "$src" ]; then
  echo "error: $src does not exist in the cloned repo (bad VERSION?)" >&2
  exit 2
fi

mkdir -p "$(dirname "$TARGET")"
if [ -d "$TARGET" ]; then
  echo "Replacing existing $TARGET ..."
  rm -rf "$TARGET"
fi
cp -r "$src" "$TARGET"

# Pin marker — consumers can check which version they're on.
echo "$VERSION" > "$TARGET/.version"

if [ "$INSTALL_CI" = "yes" ]; then
  mkdir -p .github/workflows
  cp "$TMPDIR/prj/tools/review-journal/install/ci-check.yml" .github/workflows/review-journal.yml
  echo "Installed CI workflow at .github/workflows/review-journal.yml"
fi

echo
echo "Installed pr-review-journal $VERSION into $TARGET"
echo
echo "Next steps:"
echo "  1. Create .review-journal.json at your repo root (see $TARGET/README.md)"
echo "  2. (Optional) Add skills via Claude Code plugin:"
echo "       /plugin marketplace add loganrooks/pr-review-journal"
echo "       /plugin install pr-review-journal@pr-review-journal"
echo "  3. To upgrade later, re-run this installer with a new VERSION."
