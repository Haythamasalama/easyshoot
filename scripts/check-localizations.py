#!/usr/bin/env python3
"""Lists every localizable key in the Swift sources and checks each .lproj has a translation.

  python3 scripts/check-localizations.py           # check (exit 1 on missing keys)
  python3 scripts/check-localizations.py --keys    # print all keys
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
LOC = ROOT / "Resources" / "Localization"

# L("…") calls plus string literals passed straight to SwiftUI views that localize them.
CALL = re.compile(r'\bL\("((?:[^"\\]|\\.)*)"')
SWIFTUI = re.compile(r'\b(?:Text|Button|Label|Toggle|Section|Menu|Picker|ColorPicker|TextField|LabeledContent)\("((?:[^"\\]|\\.)*)"')

def source_keys():
    keys = set()
    for f in SOURCES.rglob("*.swift"):
        text = f.read_text()
        for m in CALL.finditer(text):
            keys.add(m.group(1))
        for m in SWIFTUI.finditer(text):
            k = m.group(1)
            if "\\(" in k or not re.search(r"[A-Za-z]{2}", k):
                continue  # interpolated or symbol-only literals
            keys.add(k)
    return keys

STRINGS = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$', re.M)

def table(lang):
    path = LOC / f"{lang}.lproj" / "Localizable.strings"
    return dict(STRINGS.findall(path.read_text())) if path.exists() else {}

def main():
    keys = source_keys()
    if "--keys" in sys.argv:
        for k in sorted(keys):
            print(k)
        return 0
    ok = True
    for lproj in sorted(LOC.glob("*.lproj")):
        lang = lproj.stem
        t = table(lang)
        missing = sorted(keys - t.keys())
        for m in missing:
            print(f"{lang}: missing \"{m}\"")
        for k, v in t.items():
            if k.count("%@") != v.count("%@") or k.count("%d") != v.count("%d"):
                print(f"{lang}: placeholder mismatch in \"{k}\"")
                ok = False
        ok = ok and not missing
    print("Localizations OK" if ok else "Localization check FAILED")
    return 0 if ok else 1

sys.exit(main())
