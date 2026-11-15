#!/usr/bin/env bash
# Tag and release a new version of RailDock
# Usage: ./scripts/release.sh 1.0.0

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.0"
  exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
  echo "Error: version must be semver (e.g. 1.0.0 or 1.0.0-beta.1)"
  exit 1
fi

TAG="v$VERSION"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Commit tracked changes before releasing."
  exit 1
fi
if [ ! -f "docs/release-notes/$TAG.md" ]; then
  echo "Warning: docs/release-notes/$TAG.md is missing."
  echo "         The release falls back to GitHub's generated notes, which only list"
  echo "         merged pull requests — usually nothing in this repo, leaving the"
  echo "         release page with no description of what changed."
fi
echo "==> Tagging $TAG..."
git tag -a "$TAG" -m "Release RailDock $VERSION"
echo "==> Pushing tag..."
git push origin "$TAG"
echo "==> Done. GitHub Actions will:"
echo "   1. Run CI (tests + build)"
echo "   2. Build + push Docker images to GHCR"
echo "   3. Create GitHub Release"
echo ""
echo "To manually deploy after images are built:"
echo "   gh workflow run deploy.yml -f version=$VERSION"