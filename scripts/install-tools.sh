#!/bin/sh
# Installs the exact SwiftLint and XcodeGen versions pinned in .tool-versions (asdf format:
# `<tool> <version>` per line) into a bin directory, for CI. `brew install` is unpinned: a new
# SwiftLint release that adds a default rule turns `--strict` red on Xcode Cloud with zero
# code changes, and a new XcodeGen can regenerate a different pbxproj than the committed one.
#
#   scripts/install-tools.sh [bin-dir]     default: $HOME/.dagym-tools/bin
#
# Prints the bin directory; callers prepend it to PATH. A tool already on PATH at the pinned
# version is reused. Developers keep `brew install`; the pre-push hook only checks versions.
set -eu
cd "$(dirname "$0")/.."

BIN=${1:-$HOME/.dagym-tools/bin}
mkdir -p "$BIN"
SWIFTLINT_VERSION=$(awk '$1 == "swiftlint" { print $2 }' .tool-versions)
XCODEGEN_VERSION=$(awk '$1 == "xcodegen" { print $2 }' .tool-versions)
[ -n "$SWIFTLINT_VERSION" ] && [ -n "$XCODEGEN_VERSION" ] \
    || { echo "error: .tool-versions must pin swiftlint and xcodegen" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/dagym-tools.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

if [ "$(swiftlint version 2>/dev/null || true)" != "$SWIFTLINT_VERSION" ]; then
    echo "installing SwiftLint $SWIFTLINT_VERSION → $BIN"
    curl -fsSL -o "$TMP/swiftlint.zip" \
        "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip"
    unzip -qo "$TMP/swiftlint.zip" -d "$TMP/swiftlint"
    install -m 755 "$TMP/swiftlint/swiftlint" "$BIN/swiftlint"
fi

if [ "$(xcodegen --version 2>/dev/null | sed 's/^Version: //' || true)" != "$XCODEGEN_VERSION" ]; then
    echo "installing XcodeGen $XCODEGEN_VERSION → $BIN"
    curl -fsSL -o "$TMP/xcodegen.zip" \
        "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
    unzip -qo "$TMP/xcodegen.zip" -d "$TMP/xcodegen"
    # The zip is xcodegen/bin/xcodegen + xcodegen/share (SettingPresets); keep them together.
    rm -rf "$BIN/../xcodegen"
    cp -R "$TMP/xcodegen/xcodegen" "$BIN/../xcodegen"
    # A wrapper, not a symlink: XcodeGen finds share/xcodegen relative to its own executable.
    printf '#!/bin/sh\nexec "%s/../xcodegen/bin/xcodegen" "$@"\n' "$BIN" > "$BIN/xcodegen"
    chmod 755 "$BIN/xcodegen"
fi

echo "$BIN"
