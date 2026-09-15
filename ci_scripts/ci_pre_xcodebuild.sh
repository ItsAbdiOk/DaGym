#!/bin/sh
# Xcode Cloud runs this before every build phase — including the per-simulator
# test phases, which restore prebuilt artifacts and have NO source checkout.
# Guard on the checkout variable and exit cleanly when it is absent.
set -eu

echo "Phase: ${CI_XCODEBUILD_ACTION:-unknown}"

if [ -z "${CI_PRIMARY_REPOSITORY_PATH:-}" ] || [ ! -d "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
    echo "No source checkout in this phase; nothing to check. Exiting cleanly."
    exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "Checking for committed credentials and non-code files..."
if [ -f Configs/Secrets.xcconfig ]; then
    echo "error: Configs/Secrets.xcconfig is present in the repository." >&2
    exit 1
fi
for f in plan.md design-brief.md CLAUDE.md; do
    if [ -f "$f" ]; then
        echo "error: $f is present in the repository. This repo is code only." >&2
        exit 1
    fi
done
echo "  clean."

# Apple Wallet pass signing identity: gitignored, bundled as an optional resource. Written from
# the DAGYM_WALLET_P12_BASE64 environment secret when set; without it the app builds and the
# "Add to Apple Wallet" button hides itself. Never echo the value.
if [ -n "${DAGYM_WALLET_P12_BASE64:-}" ]; then
    echo "Writing Configs/wallet/pass.p12 from DAGYM_WALLET_P12_BASE64..."
    mkdir -p Configs/wallet
    printf '%s' "$DAGYM_WALLET_P12_BASE64" | base64 -d > Configs/wallet/pass.p12
else
    echo "DAGYM_WALLET_P12_BASE64 not set; building without the Wallet pass identity."
fi

# Installing the linter is infrastructure; finding a violation is a real gate.
# An install hiccup warns, a lint violation fails the build. Pinned via .tool-versions
# (ci_post_clone.sh already installed them; this is a no-op when the versions match).
PATH="$HOME/.dagym-tools/bin:$PATH"
export PATH
echo "Ensuring pinned SwiftLint and XcodeGen (.tool-versions)..."
scripts/install-tools.sh >/dev/null || echo "warning: could not install pinned tools; lint may be skipped." >&2
if command -v swiftlint >/dev/null 2>&1; then
    echo "Linting..."
    swiftlint lint --strict
else
    echo "warning: SwiftLint unavailable; lint skipped in this phase." >&2
fi

# App Store Connect refuses a build number it has already seen, so every archive
# needs a unique one. project.yml is the source of truth, so patch it and
# regenerate rather than touching the pbxproj.
if [ -n "${CI_BUILD_NUMBER:-}" ] && [ -f project.yml ]; then
    echo "Setting build number to $CI_BUILD_NUMBER..."
    sed -i "" "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$CI_BUILD_NUMBER\"/" project.yml
    if command -v xcodegen >/dev/null 2>&1; then
        xcodegen generate
    else
        echo "warning: xcodegen unavailable; build number not applied to the project." >&2
    fi
    grep CURRENT_PROJECT_VERSION project.yml
fi

echo "Pre-build checks passed."
