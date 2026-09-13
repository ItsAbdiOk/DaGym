#!/usr/bin/env python3
"""Static "is anything calling this?" check for DaGym (X9 in docs/reviews/SUMMARY.md §2).

Finds two shapes of dead code that compile cleanly and pass every test, because nothing in the
gate checks that a *producer* (a screen, a store method) has a *consumer* (a route, a caller):

  1. `struct Foo: View` (anywhere under DaGym/) whose name is never written anywhere else in the
     app target outside a `#Preview` block or a `#if DEBUG` region — i.e. it has no real
     constructor call, so nothing ever puts it on screen.
  2. `func foo(...)` declared on `WorkoutStore` (in DaGym/Data/WorkoutStore*.swift) that is never
     called from anywhere outside its own declaration line and outside DaGymTests/DaGymUITests —
     a method only its own unit test calls is exactly as dead as one nothing calls at all.

This is a heuristic text scan, not a type checker: it can't see dynamic dispatch, SwiftUI
`@ViewBuilder` composition tricks, or Selector/KeyPath-based calls, and it strips `#Preview` /
`#if DEBUG` blocks with simple brace/line matching, not a real preprocessor. Treat every hit as
"worth a human look", not "definitely dead". Exit code is always 0 unless --strict is passed and
findings exist — this is not wired into scripts/verify.sh or the pre-push hook (see SUMMARY.md
X9: "then one wiring batch for the four dead features" comes first).

Usage:
    python3 scripts/reachability.py [--strict] [--root PATH]
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

VIEW_STRUCT_RE = re.compile(r"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*:\s*([^{]*)\{")
FUNC_DECL_RE = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s*)*"
    r"(?P<modifiers>(?:(?:public|internal|open|final|mutating|async|throws|nonisolated)\s+)*)"
    r"func\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*\("
)
TEST_DIR_NAMES = {"DaGymTests", "DaGymUITests"}
PREVIEW_MACRO_RE = re.compile(r"#Preview\b[^{]*\{")


@dataclass
class Declaration:
    name: str
    path: Path
    line: int


@dataclass
class Report:
    unreferenced_views: list[Declaration] = field(default_factory=list)
    unreferenced_store_methods: list[Declaration] = field(default_factory=list)


def strip_non_reachable_regions(text: str) -> str:
    """Removes `#Preview { ... }` bodies and `#if DEBUG ... #endif` regions, so a reference that
    only exists in a preview or a debug-only build never counts as a real caller."""
    text = strip_preview_blocks(text)
    text = strip_debug_blocks(text)
    return text


def strip_preview_blocks(text: str) -> str:
    out = []
    i = 0
    for match in PREVIEW_MACRO_RE.finditer(text):
        out.append(text[i:match.start()])
        depth = 0
        j = match.end() - 1  # position of the opening brace
        while j < len(text):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            j += 1
        i = j
    out.append(text[i:])
    return "".join(out)


def strip_debug_blocks(text: str) -> str:
    lines = text.splitlines(keepends=True)
    stack: list[bool] = []  # True = this #if level is DEBUG-conditioned
    kept: list[str] = []
    for line in lines:
        stripped = line.strip()
        if re.match(r"#if\s+DEBUG\b", stripped):
            stack.append(True)
            kept.append("\n")
            continue
        if stripped.startswith("#if"):
            stack.append(False)
            kept.append("\n")
            continue
        if stripped.startswith("#endif"):
            if stack:
                stack.pop()
            kept.append("\n")
            continue
        if stripped.startswith("#else") or stripped.startswith("#elseif"):
            kept.append("\n")
            continue
        if any(stack):
            kept.append("\n")
        else:
            kept.append(line)
    return "".join(kept)


def iter_swift_files(root: Path, *, exclude_tests: bool) -> list[Path]:
    files = []
    for path in root.rglob("*.swift"):
        if exclude_tests and any(part in TEST_DIR_NAMES for part in path.parts):
            continue
        files.append(path)
    return sorted(files)


def find_view_declarations(app_files: list[Path]) -> list[Declaration]:
    declarations = []
    for path in app_files:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            match = VIEW_STRUCT_RE.search(line)
            if not match:
                continue
            name, conformances = match.group(1), match.group(2)
            if re.search(r"\bView\b", conformances):
                declarations.append(Declaration(name=name, path=path, line=lineno))
    return declarations


def count_word(text: str, word: str) -> int:
    return len(re.findall(r"\b" + re.escape(word) + r"\b", text))


def find_unreferenced_views(app_files: list[Path]) -> list[Declaration]:
    declarations = find_view_declarations(app_files)
    if not declarations:
        return []

    # One combined, stripped corpus (minus each file's own preview/debug regions) is enough:
    # constructor calls from *other* files always count; the only thing we must not count is a
    # reference that lives solely in a stripped region.
    corpus_by_file: dict[Path, str] = {}
    for path in app_files:
        try:
            raw = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        corpus_by_file[path] = strip_non_reachable_regions(raw)

    unreferenced = []
    for decl in declarations:
        total = 0
        for path, stripped in corpus_by_file.items():
            occurrences = count_word(stripped, decl.name)
            if path == decl.path:
                # Subtract the declaration's own `struct Foo` occurrence.
                occurrences = max(0, occurrences - 1)
            total += occurrences
        if total == 0:
            unreferenced.append(decl)
    return unreferenced


def find_store_method_declarations(store_files: list[Path]) -> list[Declaration]:
    declarations = []
    for path in store_files:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            match = FUNC_DECL_RE.match(line)
            if not match:
                continue
            if "private" in match.group("modifiers") or "fileprivate" in line[: match.start("modifiers")]:
                continue
            if re.match(r"^\s*(private|fileprivate)\b", line):
                continue
            declarations.append(Declaration(name=match.group("name"), path=path, line=lineno))
    return declarations


def find_unreferenced_store_methods(store_files: list[Path], non_test_files: list[Path]) -> list[Declaration]:
    declarations = find_store_method_declarations(store_files)
    if not declarations:
        return []

    corpus_by_file: dict[Path, str] = {}
    for path in non_test_files:
        try:
            corpus_by_file[path] = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

    unreferenced = []
    for decl in declarations:
        call_pattern = re.compile(r"\b" + re.escape(decl.name) + r"\s*\(")
        total = 0
        for path, text in corpus_by_file.items():
            for lineno, line in enumerate(text.splitlines(), start=1):
                if not call_pattern.search(line):
                    continue
                if path == decl.path and lineno == decl.line:
                    continue  # the declaration line itself
                total += 1
        if total == 0:
            unreferenced.append(decl)
    return unreferenced


def build_report(root: Path) -> Report:
    dagym_root = root / "DaGym"
    app_files = iter_swift_files(dagym_root, exclude_tests=True)
    all_files = iter_swift_files(dagym_root, exclude_tests=False)
    store_files = [
        path for path in app_files
        if path.parent.name == "Data" and path.name.startswith("WorkoutStore")
    ]

    report = Report()
    report.unreferenced_views = find_unreferenced_views(app_files)
    report.unreferenced_store_methods = find_unreferenced_store_methods(store_files, all_files)
    return report


def rel(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def print_report(report: Report, root: Path) -> None:
    print("Reachability report (heuristic — see the script's docstring for caveats)\n")

    print(f"Unreferenced `View` structs ({len(report.unreferenced_views)}):")
    if report.unreferenced_views:
        for decl in sorted(report.unreferenced_views, key=lambda d: (str(d.path), d.line)):
            print(f"  {rel(decl.path, root)}:{decl.line}  struct {decl.name}")
    else:
        print("  none")
    print()

    print(f"WorkoutStore methods never called outside DaGymTests/DaGymUITests ({len(report.unreferenced_store_methods)}):")
    if report.unreferenced_store_methods:
        for decl in sorted(report.unreferenced_store_methods, key=lambda d: (str(d.path), d.line)):
            print(f"  {rel(decl.path, root)}:{decl.line}  func {decl.name}(...)")
    else:
        print("  none")
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parent.parent,
        help="repo root (default: the parent of scripts/)"
    )
    parser.add_argument(
        "--strict", action="store_true",
        help="exit 1 if anything is found (opt-in; not used by verify.sh or pre-push today)"
    )
    args = parser.parse_args()

    root = args.root.resolve()
    if not (root / "DaGym").is_dir():
        print(f"error: {root}/DaGym not found — pass --root or run from the repo root", file=sys.stderr)
        return 2

    report = build_report(root)
    print_report(report, root)

    total = len(report.unreferenced_views) + len(report.unreferenced_store_methods)
    if args.strict and total > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
