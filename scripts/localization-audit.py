#!/usr/bin/env python3
"""Full localization picture: every key-producing mechanism vs both catalogs."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATS = {"en": "EzSwitch/en.lproj/Localizable.strings",
        "ru": "EzSwitch/ru.lproj/Localizable.strings"}

# Every construct that yields a localization lookup.
PATTERNS = {
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

    en, ru = cats["en"], cats["ru"]
    print(f"\n=== catalogs ===\n  en {len(en)}   ru {len(ru)}")

    missing_en = sorted(k for k in all_keys if k not in en)
    missing_ru = sorted(k for k in all_keys if k not in ru)
    print(f"\n=== MISSING from catalog ===")
    print(f"  en: {len(missing_en)}   ru: {len(missing_ru)}")

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

    only_en = sorted(set(en) - set(ru))
    only_ru = sorted(set(ru) - set(en))
    print(f"\n=== en/ru asymmetry: en-only={len(only_en)} ru-only={len(only_ru)} ===")
    for k in only_en:
        print(f"  en-only: {k}")
    for k in only_ru:
        print(f"  ru-only: {k}")

    untranslated = sorted(k for k in en if k in ru and en[k] == ru[k]
                          and not re.fullmatch(r"[%@\d\s\p{P}]*", en[k], re.UNICODE)
                          and en[k].strip() and any(c.isalpha() for c in en[k]))
    print(f"\n=== identical en/ru values (candidates for untranslated): {len(untranslated)} ===")
    for k in untranslated[:40]:
        print(f"  {k}  =  {en[k]}")


if __name__ == "__main__":
    sys.exit(main())
