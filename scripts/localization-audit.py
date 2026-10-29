#!/usr/bin/env python3
"""Full localization picture: every key-producing mechanism vs all supported catalogs."""
import os
import re
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATS = {code: f"EzSwitch/{code}.lproj/Localizable.strings"
        for code in ("en", "ru", "uk", "he", "de", "fr", "es", "pl")}

# Every construct that yields a localization lookup.
PATTERNS = {
    "String(appLocalized:)": re.compile(r'String\(appLocalized:\s*"((?:[^"\\]|\\.)*)"'),
    "Sheet localization value": re.compile(r'(?:title|actionName):\s*"((?:[^"\\]|\\.)*)"'),
    "String(localized:)": re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"'),
    "Text(literal)":      re.compile(r'\bText\(\s*"((?:[^"\\]|\\.)*)"\s*\)'),
    "NSLocalizedString":  re.compile(r'NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)"'),
    "LocalizedStringKey": re.compile(r'LocalizedStringKey\(\s*"((?:[^"\\]|\\.)*)"'),
}


def swift_files():
    for dirpath, _d, files in os.walk(os.path.join(ROOT, "EzSwitch")):
        for fn in files:
            if fn.endswith(".swift"):
                yield os.path.join(dirpath, fn)


def normalize(lit):
    """Literal -> .strings key. Interpolations become specifiers; Int -> %lld,
    String -> %@ (confirmed empirically against Foundation)."""
    out, i, depth = [], 0, 0
    while i < len(lit):
        if lit[i] == "\\" and i + 1 < len(lit) and lit[i + 1] == "(":
            start = i + 2
            depth, j = 1, start
            while j < len(lit) and depth:
                if lit[j] == "(":
                    depth += 1
                elif lit[j] == ")":
                    depth -= 1
                j += 1
            expr = lit[start:j - 1]
            out.append(interp_specifier(expr))
            i = j
            continue
        out.append(lit[i])
        i += 1
    s = "".join(out)
    return s.replace('\\"', '"').replace("\\\\", "\\")


def interp_specifier(expr):
    """Int expressions -> %lld, everything else -> %@."""
    e = expr.strip()
    # Trailing .count / .hash / arithmetic on collections implies Int.
    if re.search(r"\.(count|hashValue|utf16\.count|characters\.count)$", e):
        return "%lld"
    # Explicit Int-typed members seen in this codebase.
    if e in {"preset.mappingCount", "mappingCount", "preset.mapping.count", "count"}:
        return "%lld"
    # Bare integer literal.
    if re.fullmatch(r"-?\d+", e):
        return "%lld"
    return "%@"


def parse_catalog(path):
    keys = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', line)
            if m:
                keys[m.group(1)] = m.group(2)
    return keys


def placeholder_only(value):
    """True when a value is nothing but format placeholders, digits, spaces or
    punctuation (e.g. "%@", "⌘⇧M", "—") — en == ru is then expected, not a gap.

    Python's `re` has no \\p{P}, so Unicode punctuation is tested via
    `unicodedata` instead of a regex class.
    """
    return all(c in "%@" or c.isspace() or c.isdigit()
               or unicodedata.category(c).startswith("P")
               for c in value)


def main():
    cats = {k: parse_catalog(os.path.join(ROOT, v)) for k, v in CATS.items()}
    texts = {k: set() for k in PATTERNS}

    for path in swift_files():
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        for name, pat in PATTERNS.items():
            for m in pat.finditer(src):
                lit = m.group(1)
                # Text(var) and Text(verbatim:) are not localized and are not
                # matched by these patterns. Text("literal") localizes via
                # LocalizedStringKey; interpolated Text("...\(...)...") does too,
                # so normalize both the same way as String(localized:).
                if name == "Text(literal)" and "$" in lit:
                    continue
                texts[name].add(normalize(lit))

    print("=== keys by mechanism ===")
    all_keys = set()
    for name, keys in texts.items():
        print(f"  {name:<22} {len(keys):>4}")
        all_keys |= keys
    print(f"  {'TOTAL unique':<22} {len(all_keys):>4}")

    en = cats["en"]
    print("\n=== catalogs ===")
    for code, cat in cats.items():
        print(f"  {code} {len(cat)}")

    missing_en = sorted(k for k in all_keys if k not in en)
    print(f"\n=== MISSING from catalog ===")
    for code, cat in cats.items():
        missing = sorted(k for k in all_keys if k not in cat)
        print(f"  {code}: {len(missing)}")

    print("\n--- missing, grouped by mechanism ---")
    for name, keys in texts.items():
        gap = sorted(k for k in keys if k not in en)
        if gap:
            print(f"  [{name}] {len(gap)}")
            for k in gap:
                print(f"     {k}")

    orphans = sorted(k for k in en if k not in all_keys)
    print(f"\n=== ORPHANED (in en catalog, never referenced): {len(orphans)} ===")
    for k in orphans[:60]:
        print(f"     {k}")

    print("\n=== catalog asymmetry vs en ===")
    for code, cat in cats.items():
        if code == "en":
            continue
        only_en = sorted(set(en) - set(cat))
        only_lang = sorted(set(cat) - set(en))
        print(f"  {code}: en-only={len(only_en)} {code}-only={len(only_lang)}")
        for k in only_en:
            print(f"    en-only: {k}")
        for k in only_lang:
            print(f"    {code}-only: {k}")

    print("\n=== identical en/<lang> values (candidates for untranslated) ===")
    for code, cat in cats.items():
        if code == "en":
            continue
        untranslated = sorted(k for k in en if k in cat and en[k] == cat[k]
                              and not placeholder_only(en[k])
                              and en[k].strip() and any(c.isalpha() for c in en[k]))
        print(f"  {code}: {len(untranslated)}")
        for k in untranslated[:40]:
            print(f"    {k}  =  {en[k]}")


if __name__ == "__main__":
    sys.exit(main())
