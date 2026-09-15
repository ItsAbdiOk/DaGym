#!/bin/sh
# Xcode Cloud runs this after cloning, before building. The .xcodeproj is
# committed; this guarantees it matches project.yml even if a stale one slipped in.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Exact versions from .tool-versions, not `brew install` (unpinned: a new SwiftLint default
# rule would turn --strict red here with no code change). ci_pre_xcodebuild.sh reuses them.
echo "Installing pinned SwiftLint and XcodeGen (.tool-versions)..."
PATH="$(scripts/install-tools.sh | tail -1):$PATH"
export PATH

echo "Generating the Xcode project from project.yml..."
xcodegen generate

echo "Done."
