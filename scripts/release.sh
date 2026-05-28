#!/usr/bin/env bash
# Tag and release a new version of RailDock
# Usage: ./scripts/release.sh 1.0.0

set -e

VERSION="$1"
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
echo "   gh workflow run deploy.yml -f version=$TAG"