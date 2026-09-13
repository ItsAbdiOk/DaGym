#!/bin/sh
# Xcode Cloud runs this after cloning, before building. The .xcodeproj is
# committed; this guarantees it matches project.yml even if a stale one slipped in.
set -eu

echo "Installing XcodeGen..."
brew install xcodegen

echo "Generating the Xcode project from project.yml..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "Done."
