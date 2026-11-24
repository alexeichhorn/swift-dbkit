"""Reports the rust-dbkit tests and compile-fail fixtures that have no Swift counterpart.

Usage: python3 scripts/check-rust-parity.py <path to rust-dbkit>

A Rust test counts as ported when the Swift test file named after its Rust file has a `func` of the
same name, and as listed when `docs/rust-parity.md` names it in the table under
"Rust Tests Without A Swift Counterpart". Exits 1 when a test is neither or a listed row is stale.
"""

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TESTS = REPO / "Tests"
FIXTURES = TESTS / "CompileFail" / "Sources" / "Fixtures"
PARITY_DOC = REPO / "docs" / "rust-parity.md"
EXCEPTIONS_HEADING = "## Rust Tests Without A Swift Counterpart"

# `#[test]` or `#[tokio::test…]`, any further stacked attributes, then the function name.
RUST_TEST = re.compile(
    r"^[ \t]*#\[(?:tokio::)?test\b[^\]]*\]\s*(?:#\[[^\]]*\]\s*)*(?:pub\s+)?(?:async\s+)?fn\s+(\$?\w+)",
    re.MULTILINE,
)
MACRO_RULES = re.compile(r"macro_rules!\s*(\w+)\s*\{\s*\(\s*\$(\w+):ident")
SWIFT_FUNC = re.compile(r"\bfunc\s+(\w+)")


def normalized(name: str) -> str:
    return name.replace("_", "").lower()


def rust_test_names(path: Path) -> list[str]:
    source = path.read_text()
    names = []
    for match in RUST_TEST.finditer(source):
        name = match.group(1)
        if not name.startswith("$"):
            names.append(name)
            continue
        # A test written inside `macro_rules!` takes its name from the first argument of each invocation.
        macros = list(MACRO_RULES.finditer(source, 0, match.start()))
        if not macros or macros[-1].group(2) != name[1:]:
            sys.exit(f"{path}: cannot resolve the macro-generated test `{name}`")
        macro = macros[-1].group(1)
        names += re.findall(rf"\b{macro}!\s*\(\s*(\w+)", source)
    return names


def swift_funcs_by_file() -> dict[str, set[str]]:
    """Normalized Swift file stem to the normalized names of the functions in it."""
    funcs = defaultdict(set)
    for path in TESTS.rglob("*.swift"):
        if any(part.startswith(".") for part in path.relative_to(TESTS).parts):
            continue
        funcs[normalized(path.stem)] |= {normalized(name) for name in SWIFT_FUNC.findall(path.read_text())}
    return funcs


def listed_rows() -> list[str]:
    rows = []
    in_section = False
    for line in PARITY_DOC.read_text().splitlines():
        if line.startswith("#"):
            in_section = line.strip() == EXCEPTIONS_HEADING
        elif in_section and (cell := re.match(r"\|\s*`([^`]+)`\s*\|", line)):
            rows.append(cell.group(1))
    return rows


def main():
    if len(sys.argv) != 2:
        print(f"usage: python3 {sys.argv[0]} <path to rust-dbkit>", file=sys.stderr)
        sys.exit(2)
    rust = Path(sys.argv[1])
    rust_files = sorted(
        path for path in rust.glob("crates/*/tests/*.rs") if path.name != "derive_ui.rs"
    )
    if not rust_files:
        sys.exit(f"no Rust test files under {rust / 'crates'}")

    # A file stem that exists in several crates is told apart by the crate, e.g. `dbkit-core` -> `Core`.
    stem_counts = Counter(path.stem for path in rust_files)
    swift_funcs = swift_funcs_by_file()
    fixture_names = {normalized(path.stem) for path in FIXTURES.glob("*.swift")}
    listed = set(listed_rows())

    # Rust file to (name, row key, ported) for each of its tests or fixtures.
    items: dict[str, list[tuple[str, str, bool]]] = {}
    test_count = 0
    for path in rust_files:
        crate = path.parent.parent.name
        if stem_counts[path.stem] > 1:
            label = f"{crate}/{path.name}"
            swift_stem = crate.removeprefix("dbkit") + path.stem + "Tests"
        else:
            label = path.name
            swift_stem = path.stem + "Tests"
        ported_names = swift_funcs.get(normalized(swift_stem.replace("-", "")), set())
        names = rust_test_names(path)
        test_count += len(names)
        items[str(path.relative_to(rust))] = [
            (name, f"{label}::{name}", normalized(name) in ported_names) for name in names
        ]

    fixtures = sorted((rust / "crates" / "dbkit" / "tests" / "ui").glob("*.rs"))
    items["crates/dbkit/tests/ui"] = [
        (path.name, f"ui/{path.name}", normalized(path.stem) in fixture_names) for path in fixtures
    ]

    ported = listed_count = 0
    missing: dict[str, list[str]] = {}
    for rust_file, entries in items.items():
        for name, key, is_ported in entries:
            if is_ported:
                ported += 1
            elif key in listed:
                listed_count += 1
            else:
                missing.setdefault(rust_file, []).append(name)

    # A row is stale when it names no Rust test or one that is ported by now.
    unported_keys = {key for entries in items.values() for _, key, is_ported in entries if not is_ported}
    stale = sorted(listed - unported_keys)

    for rust_file, names in missing.items():
        print(f"{rust_file}:")
        for name in names:
            print(f"  {name}")
    if stale:
        print(f"Rows in {PARITY_DOC.relative_to(REPO)} that name no unported Rust test:")
        for key in stale:
            print(f"  {key}")
    missing_count = sum(len(names) for names in missing.values())
    print(
        f"{test_count} tests, {len(fixtures)} fixtures: "
        f"{ported} ported, {listed_count} listed, {missing_count} missing"
    )
    sys.exit(1 if missing or stale else 0)


main()
