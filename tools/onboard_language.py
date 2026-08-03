#!/usr/bin/env python3
"""
onboard_language.py -- Mechanical helper for adding a new language to Dictus.

Built from the friction encountered onboarding German (issue #109) under the
LanguageProfile system (issue #110). Handles the deterministic parts; curated
decisions (display name, layout, accent map content, override population)
stay manual and live in `docs/agents/language-onboarding.md`.

Phases (each is idempotent — re-running on an already-onboarded language
should report "already present" rather than break):

    scaffold <code> --display-name <name> --short-code <XX> [--layout qwerty|azerty]
        Adds the case to SupportedLanguage and LanguageProfile, writes
        Languages/<Lang>.swift skeleton and Tests/.../<Lang>LanguageTests.swift.
        After running, the maintainer must populate accentMap and (if applicable)
        overrides + contractionPrefixes manually — see ADR 0001 for the policy
        on first-ship contents.

    build-dicts <code>
        Runs scripts/curate_<code>_dictionary.py (must already exist),
        then dict_builder.py, then ngram_builder.py. Outputs land in
        DictusKeyboard/Resources/.

    wire-xcode <code>
        Edits Dictus.xcodeproj/project.pbxproj to add three resources
        (de_frequency.json, de_spellcheck.dict, de_ngrams.dict) to the
        DictusKeyboard target's resource build phase.

    verify <code>
        Runs the DictusCore tests on the host Mac and a DictusApp build on
        the iPhone 17 Pro simulator to make sure the keyboard appex still
        links.

Usage examples:

    # First-time onboarding flow for, e.g., Italian:
    python3 tools/onboard_language.py scaffold it \
        --display-name "Italiano" --short-code IT --layout qwerty
    # ... maintainer authors scripts/curate_it_dictionary.py ...
    python3 tools/onboard_language.py build-dicts it
    python3 tools/onboard_language.py wire-xcode it
    python3 tools/onboard_language.py verify it
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

# All paths anchored at repo root regardless of cwd.
REPO_ROOT = Path(__file__).resolve().parent.parent
DICTUS_CORE = REPO_ROOT / "DictusCore" / "Sources" / "DictusCore"
DICTUS_TESTS = REPO_ROOT / "DictusCore" / "Tests" / "DictusCoreTests"
KEYBOARD_RES = REPO_ROOT / "DictusKeyboard" / "Resources"
PBXPROJ = REPO_ROOT / "Dictus.xcodeproj" / "project.pbxproj"
SCRIPTS = REPO_ROOT / "scripts"
TOOLS = REPO_ROOT / "tools"

# Verified during German onboarding 2026-05-05; keep in sync with
# Pierre's local sim setup (see memory: "iPhone 17 Pro simulator").
# Used by the DictusApp build only — the DictusCore suite runs on the host
# Mac via `swift test` (#301).
SIMULATOR_DESTINATION = "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2"


def _capitalize(code: str) -> str:
    """`de` -> `German` style — used for the case name in SupportedLanguage."""
    return {"fr": "french", "en": "english", "es": "spanish", "de": "german"}.get(
        code, code.lower()
    ).capitalize() if code in {"fr", "en", "es", "de"} else code.lower().capitalize()


def _enum_case(code: str, display_name: str) -> str:
    """Convention: enum case is the lowercased English name of the language."""
    # Hardcoded for the four shipped languages; for new languages we derive
    # from the lowercased displayName, stripping diacritics is the maintainer's
    # job during scaffold (they pass --display-name).
    return {
        "fr": "french",
        "en": "english",
        "es": "spanish",
        "de": "german",
    }.get(code, display_name.lower().split()[0])


# ---------- scaffold ----------

PROFILE_TEMPLATE = '''\
// DictusCore/Sources/DictusCore/Languages/{Lang}.swift
// {DisplayName} language profile. Onboarded via tools/onboard_language.py.
// Per ADR 0001, overrides and seed bigrams ship empty on first launch when
// the maintainer is non-native; populated post-launch from real feedback.
import Foundation

/// {DisplayName} (`{code}`).
public let {lang}Profile = LanguageProfile(
    code: "{code}",
    displayName: "{DisplayName}",
    shortCode: "{shortCode}",
    defaultLayout: .{layout},
    spaceName: "TODO_space_label",     // localized convention (e.g. "espace")
    returnName: "TODO_return_label",   // localized convention (e.g. "retour")
    overrides: [:],                     // empty on first ship per ADR 0001
    accentMap: [
        // Populate per language. Generative — list each base letter that has
        // accent variants and the variants the algorithm should try.
        // Example for German: "a": ["\\u{{00E4}}"], "o": ["\\u{{00F6}}"], ...
    ],
    contractionPrefixes: []             // language-dependent; empty if none
)
'''

TESTS_TEMPLATE = '''\
// DictusCore/Tests/DictusCoreTests/Languages/{Lang}LanguageTests.swift
// Per-language test file (locked decision #10 of #110 grilling).
import XCTest
@testable import DictusCore

final class {Lang}LanguageTests: XCTestCase {{

    func test_{lang}Profile_displayFields() {{
        let p = {lang}Profile
        XCTAssertEqual(p.code, "{code}")
        XCTAssertEqual(p.displayName, "{DisplayName}")
        XCTAssertEqual(p.shortCode, "{shortCode}")
        XCTAssertEqual(p.defaultLayout, .{layout})
        // TODO populate spaceName / returnName assertions once filled in
    }}

    func test_supportedLanguage_{lang}_resolvesToProfile() {{
        XCTAssertEqual(SupportedLanguage.{lang}.profile.code, "{code}")
    }}

    func test_{lang}Profile_overridesIsEmptyPerADR0001() {{
        XCTAssertTrue({lang}Profile.overrides.isEmpty)
    }}

    func test_{lang}Profile_hasNoContractionPrefixes() {{
        XCTAssertTrue({lang}Profile.contractionPrefixes.isEmpty)
    }}

    // TODO: add expandAccents tests once accentMap is populated.
}}
'''


def cmd_scaffold(args: argparse.Namespace) -> int:
    code = args.code
    display = args.display_name
    short = args.short_code
    layout = args.layout
    lang = _enum_case(code, display)
    Lang = lang.capitalize()

    profile_path = DICTUS_CORE / "Languages" / f"{Lang}.swift"
    tests_dir = DICTUS_TESTS / "Languages"
    tests_path = tests_dir / f"{Lang}LanguageTests.swift"

    # 1. Languages/<Lang>.swift
    if profile_path.exists():
        print(f"[skip] {profile_path.relative_to(REPO_ROOT)} already exists")
    else:
        profile_path.parent.mkdir(parents=True, exist_ok=True)
        profile_path.write_text(
            PROFILE_TEMPLATE.format(
                Lang=Lang, DisplayName=display, code=code, shortCode=short,
                layout=layout, lang=lang,
            ),
            encoding="utf-8",
        )
        print(f"[wrote] {profile_path.relative_to(REPO_ROOT)}")

    # 2. Tests/Languages/<Lang>LanguageTests.swift
    if tests_path.exists():
        print(f"[skip] {tests_path.relative_to(REPO_ROOT)} already exists")
    else:
        tests_dir.mkdir(parents=True, exist_ok=True)
        tests_path.write_text(
            TESTS_TEMPLATE.format(
                Lang=Lang, DisplayName=display, code=code, shortCode=short,
                layout=layout, lang=lang,
            ),
            encoding="utf-8",
        )
        print(f"[wrote] {tests_path.relative_to(REPO_ROOT)}")

    # 3. SupportedLanguage.swift: add `case <lang> = "<code>"` if missing.
    sl_path = DICTUS_CORE / "SupportedLanguage.swift"
    sl_text = sl_path.read_text(encoding="utf-8")
    if f'case {lang} = "{code}"' in sl_text:
        print(f"[skip] SupportedLanguage already has case {lang}")
    else:
        # Insert after the last existing case in the enum.
        new_sl = re.sub(
            r"(case spanish = \"es\"\n)",
            f'\\1    case {lang} = "{code}"\n',
            sl_text,
        )
        if new_sl == sl_text:
            print("[error] couldn't find case-insertion point in SupportedLanguage.swift")
            return 1
        sl_path.write_text(new_sl, encoding="utf-8")
        print(f"[edited] SupportedLanguage.swift: added case {lang}")
        print("        --> ALSO ADD switch arms in displayName / defaultLayout /"
              " spaceName / returnName by hand — they're per-language constants.")

    # 4. LanguageProfile.swift: add switch arm for the profile.
    lp_path = DICTUS_CORE / "Languages" / "LanguageProfile.swift"
    lp_text = lp_path.read_text(encoding="utf-8")
    if f"case .{lang}: return {lang}Profile" in lp_text:
        print(f"[skip] LanguageProfile.profile switch already maps {lang}")
    else:
        new_lp = re.sub(
            r"(case \.spanish: return spanishProfile\n)",
            f"\\1        case .{lang}: return {lang}Profile\n",
            lp_text,
        )
        if new_lp == lp_text:
            print("[error] couldn't find profile-switch insertion point")
            return 1
        lp_path.write_text(new_lp, encoding="utf-8")
        print(f"[edited] LanguageProfile.swift: mapped .{lang} -> {lang}Profile")

    print()
    print("Next steps (manual):")
    print(f"  1. Fill spaceName / returnName / accentMap in {profile_path.relative_to(REPO_ROOT)}")
    print(f"  2. Add the case to all switches in SupportedLanguage.swift")
    print(f"  3. Author scripts/curate_{code}_dictionary.py for the corpus source")
    print(f"  4. Run: python3 tools/onboard_language.py build-dicts {code}")
    return 0


# ---------- build-dicts ----------

def cmd_build_dicts(args: argparse.Namespace) -> int:
    code = args.code
    curate = SCRIPTS / f"curate_{code}_dictionary.py"
    if not curate.exists():
        print(f"[error] {curate.relative_to(REPO_ROOT)} not found.")
        print(f"        Author it first — see scripts/curate_de_dictionary.py")
        print(f"        for the HermitDave/OpenSubtitles 2018 pattern.")
        return 1

    freq_json = KEYBOARD_RES / f"{code}_frequency.json"
    spellcheck = KEYBOARD_RES / f"{code}_spellcheck.dict"
    ngrams = KEYBOARD_RES / f"{code}_ngrams.dict"

    print(f"=== {curate.name} ===")
    rc = subprocess.call(["python3", str(curate)], cwd=REPO_ROOT)
    if rc != 0:
        return rc

    print(f"\n=== dict_builder.py ===")
    rc = subprocess.call(
        ["python3", str(TOOLS / "dict_builder.py"), str(freq_json), str(spellcheck)],
        cwd=REPO_ROOT,
    )
    if rc != 0:
        return rc

    print(f"\n=== ngram_builder.py ===")
    rc = subprocess.call(
        ["python3", str(TOOLS / "ngram_builder.py"), "--lang", code, "--output", str(ngrams)],
        cwd=REPO_ROOT,
    )
    return rc


# ---------- wire-xcode ----------

def cmd_wire_xcode(args: argparse.Namespace) -> int:
    code = args.code
    code_upper = code.upper()
    text = PBXPROJ.read_text(encoding="utf-8")

    # Convention used during German onboarding (issue #109):
    #   AA0000Dx / AA1000Dx — *_frequency.json build file / file ref
    #   EE0XX001 / EE1XX001 — *_spellcheck.dict build file / file ref
    #   EE0XX002 / EE1XX002 — *_ngrams.dict build file / file ref
    # The `XX` token is the uppercase 2-letter code (DE, IT, ...).
    # We hash from `code` to keep IDs stable per language.

    if f"{code}_frequency.json" in text and f"EE0{code_upper}001" in text:
        print(f"[skip] {code} already wired into project.pbxproj")
        return 0

    # Generate the next free 'AA0000Dx / AA1000Dx' ID for the frequency JSON
    # by scanning existing AA1000D? entries and picking the next letter.
    used = set(re.findall(r"AA1000D([0-9A-Z])", text))
    pool = [c for c in "23456789ABCDEFGH" if c not in used]
    if not pool:
        print("[error] no free AA1000D? slot left — extend the ID scheme.")
        return 1
    slot = pool[0]

    bf_freq_id = f"AA0000D{slot}"
    fr_freq_id = f"AA1000D{slot}"
    bf_spell_id = f"EE0{code_upper}001"
    fr_spell_id = f"EE1{code_upper}001"
    bf_ngrams_id = f"EE0{code_upper}002"
    fr_ngrams_id = f"EE1{code_upper}002"

    # Sanity: any of those collide with existing IDs?
    for tok in [bf_spell_id, fr_spell_id, bf_ngrams_id, fr_ngrams_id]:
        if tok in text:
            print(f"[error] generated ID {tok} already in use — pick a different code-pair.")
            return 1

    # 1. PBXBuildFile section — append after es_frequency.json line.
    text = text.replace(
        "AA0000D5 /* es_frequency.json in Resources */ = {isa = PBXBuildFile; fileRef = AA1000D5 /* es_frequency.json */; };",
        "AA0000D5 /* es_frequency.json in Resources */ = {isa = PBXBuildFile; fileRef = AA1000D5 /* es_frequency.json */; };\n"
        f"\t\t{bf_freq_id} /* {code}_frequency.json in Resources */ = {{isa = PBXBuildFile; fileRef = {fr_freq_id} /* {code}_frequency.json */; }};",
    )
    text = text.replace(
        "EE0ES002 /* es_ngrams.dict in Resources */ = {isa = PBXBuildFile; fileRef = EE1ES002 /* es_ngrams.dict */; };",
        "EE0ES002 /* es_ngrams.dict in Resources */ = {isa = PBXBuildFile; fileRef = EE1ES002 /* es_ngrams.dict */; };\n"
        f"\t\t{bf_spell_id} /* {code}_spellcheck.dict in Resources */ = {{isa = PBXBuildFile; fileRef = {fr_spell_id} /* {code}_spellcheck.dict */; }};\n"
        f"\t\t{bf_ngrams_id} /* {code}_ngrams.dict in Resources */ = {{isa = PBXBuildFile; fileRef = {fr_ngrams_id} /* {code}_ngrams.dict */; }};",
    )

    # 2. PBXFileReference section.
    text = text.replace(
        "AA1000D5 /* es_frequency.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = es_frequency.json; sourceTree = \"<group>\"; };",
        "AA1000D5 /* es_frequency.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = es_frequency.json; sourceTree = \"<group>\"; };\n"
        f"\t\t{fr_freq_id} /* {code}_frequency.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = {code}_frequency.json; sourceTree = \"<group>\"; }};",
    )
    text = text.replace(
        "EE1ES002 /* es_ngrams.dict */ = {isa = PBXFileReference; lastKnownFileType = \"compiled\"; path = es_ngrams.dict; sourceTree = \"<group>\"; };",
        "EE1ES002 /* es_ngrams.dict */ = {isa = PBXFileReference; lastKnownFileType = \"compiled\"; path = es_ngrams.dict; sourceTree = \"<group>\"; };\n"
        f"\t\t{fr_spell_id} /* {code}_spellcheck.dict */ = {{isa = PBXFileReference; lastKnownFileType = \"compiled\"; path = {code}_spellcheck.dict; sourceTree = \"<group>\"; }};\n"
        f"\t\t{fr_ngrams_id} /* {code}_ngrams.dict */ = {{isa = PBXFileReference; lastKnownFileType = \"compiled\"; path = {code}_ngrams.dict; sourceTree = \"<group>\"; }};",
    )

    # 3. PBXGroup Resources children.
    text = text.replace(
        "AA1000D5 /* es_frequency.json */,",
        f"AA1000D5 /* es_frequency.json */,\n\t\t\t\t{fr_freq_id} /* {code}_frequency.json */,",
    )
    text = text.replace(
        "EE1ES001 /* es_spellcheck.dict */,",
        f"EE1ES001 /* es_spellcheck.dict */,\n\t\t\t\t{fr_spell_id} /* {code}_spellcheck.dict */,",
    )
    text = text.replace(
        "EE1ES002 /* es_ngrams.dict */,",
        f"EE1ES002 /* es_ngrams.dict */,\n\t\t\t\t{fr_ngrams_id} /* {code}_ngrams.dict */,",
    )

    # 4. PBXResourcesBuildPhase for DictusKeyboard target.
    text = text.replace(
        "AA0000D5 /* es_frequency.json in Resources */,",
        f"AA0000D5 /* es_frequency.json in Resources */,\n\t\t\t\t{bf_freq_id} /* {code}_frequency.json in Resources */,",
    )
    text = text.replace(
        "EE0ES001 /* es_spellcheck.dict in Resources */,",
        f"EE0ES001 /* es_spellcheck.dict in Resources */,\n\t\t\t\t{bf_spell_id} /* {code}_spellcheck.dict in Resources */,",
    )
    text = text.replace(
        "EE0ES002 /* es_ngrams.dict in Resources */,",
        f"EE0ES002 /* es_ngrams.dict in Resources */,\n\t\t\t\t{bf_ngrams_id} /* {code}_ngrams.dict in Resources */,",
    )

    PBXPROJ.write_text(text, encoding="utf-8")
    print(f"[edited] project.pbxproj: added {code}_frequency.json + "
          f"{code}_spellcheck.dict + {code}_ngrams.dict to DictusKeyboard")
    return 0


# ---------- verify ----------

def cmd_verify(args: argparse.Namespace) -> int:
    """Runs DictusCore tests + a DictusApp Debug build."""
    print(f"=== swift test (DictusCore) ===")
    rc = subprocess.call(
        ["swift", "test"],
        cwd=REPO_ROOT / "DictusCore",
    )
    if rc != 0:
        print(f"[fail] DictusCoreTests failed (exit {rc})")
        return rc

    print(f"\n=== xcodebuild build (DictusApp) ===")
    rc = subprocess.call(
        [
            "xcodebuild", "build",
            "-project", str(PBXPROJ.parent),
            "-scheme", "DictusApp",
            "-destination", SIMULATOR_DESTINATION,
            "-configuration", "Debug",
        ],
        cwd=REPO_ROOT,
    )
    if rc != 0:
        print(f"[fail] DictusApp build failed (exit {rc})")
        return rc

    print(f"\n[ok] verify passed")
    return 0


# ---------- main ----------

def main() -> int:
    parser = argparse.ArgumentParser(
        prog="onboard_language.py",
        description=__doc__.strip().split("\n\n")[0],
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_scaffold = sub.add_parser("scaffold", help="generate Swift skeletons + register the case")
    p_scaffold.add_argument("code", help="BCP-47 code, e.g. 'it'")
    p_scaffold.add_argument("--display-name", required=True, help="e.g. 'Italiano'")
    p_scaffold.add_argument("--short-code", required=True, help="e.g. 'IT'")
    p_scaffold.add_argument("--layout", choices=["qwerty", "azerty"], default="qwerty")
    p_scaffold.set_defaults(func=cmd_scaffold)

    p_build = sub.add_parser("build-dicts", help="run curate + dict_builder + ngram_builder")
    p_build.add_argument("code")
    p_build.set_defaults(func=cmd_build_dicts)

    p_wire = sub.add_parser("wire-xcode", help="add the 3 resources to project.pbxproj")
    p_wire.add_argument("code")
    p_wire.set_defaults(func=cmd_wire_xcode)

    p_verify = sub.add_parser("verify", help="DictusCore tests + DictusApp build")
    p_verify.add_argument("code", nargs="?", default=None,
                          help="(unused but reserved for future per-language checks)")
    p_verify.set_defaults(func=cmd_verify)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
