#!/usr/bin/env python3
"""Check Polka's handwritten localization tables and literal L(...) calls.

The small Swift lexer handles ordinary/raw strings, escapes, comments, and nested
interpolation expressions. It is not a Swift type checker: messages passed through
variables and system-owned UI still need human review. --review-cyrillic lists
unmatched Cyrillic literals as review hints without treating book data as errors.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {"ru", "uk", "en"}
PLACEHOLDER = re.compile(r"\{\d+\}")
CYRILLIC = re.compile(r"[\u0400-\u04ff]")


@dataclass(frozen=True)
class SwiftString:
    start: int
    end: int
    template: str


class SwiftStrings:
    def __init__(self, source: str):
        self.source = source
        self.strings: list[SwiftString] = []

    def scan(self) -> list[SwiftString]:
        self.code(0)
        return sorted(self.strings, key=lambda item: item.start)

    def code(self, pos: int, depth: int = 0) -> int:
        source = self.source
        while pos < len(source):
            if source.startswith("//", pos):
                end = source.find("\n", pos)
                pos = len(source) if end < 0 else end + 1
            elif source.startswith("/*", pos):
                nested = 1
                pos += 2
                while pos < len(source) and nested:
                    if source.startswith("/*", pos):
                        nested += 1
                        pos += 2
                    elif source.startswith("*/", pos):
                        nested -= 1
                        pos += 2
                    else:
                        pos += 1
            elif source[pos] == '"' or (source[pos] == "#" and re.match(r'#+"', source[pos:])):
                pos = self.string(pos)
            elif depth and source[pos] == "(":
                depth += 1
                pos += 1
            elif depth and source[pos] == ")":
                depth -= 1
                pos += 1
                if not depth:
                    return pos
            else:
                pos += 1
        if depth:
            raise ValueError("Unterminated Swift interpolation")
        return pos

    def string(self, start: int) -> int:
        source = self.source
        pos = start
        while source[pos] == "#":
            pos += 1
        hashes = source[start:pos]
        quotes = '"""' if source.startswith('"""', pos) else '"'
        closing = quotes + hashes
        escape = "\\" + hashes
        pos += len(quotes)
        template: list[str] = []
        interpolation = 0
        while pos < len(source):
            if source.startswith(closing, pos):
                end = pos + len(closing)
                self.strings.append(SwiftString(start, end, "".join(template)))
                return end
            if source.startswith(escape, pos):
                escaped = pos + len(escape)
                if source.startswith("(", escaped):
                    template.append("{" + str(interpolation) + "}")
                    interpolation += 1
                    pos = self.code(escaped + 1, depth=1)
                    continue
                if escaped < len(source):
                    value = source[escaped]
                    if value == "u" and source.startswith("{", escaped + 1):
                        end = source.index("}", escaped + 2)
                        template.append(chr(int(source[escaped + 2:end], 16)))
                        pos = end + 1
                        continue
                    template.append({"n": "\n", "r": "\r", "t": "\t", "0": "\0"}.get(value, value))
                    pos = escaped + 1
                    continue
            template.append(source[pos])
            pos += 1
        raise ValueError(f"Unterminated Swift string at offset {start}")


def read_json(path: Path) -> dict:
    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON key: {key!r}")
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique_pairs)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review-cyrillic", action="store_true")
    args = parser.parse_args()
    issues: list[str] = []
    messages: dict[str, dict[str, str]] = {}
    origins: dict[str, Path] = {}
    files = sorted((ROOT / "App/Localization").glob("*.json"))
    if not files:
        issues.append("No localization JSON resources found")
    for path in files:
        try:
            entries = read_json(path)
        except (ValueError, OSError) as error:
            issues.append(f"{path.relative_to(ROOT)}: {error}")
            continue
        for key, values in entries.items():
            if not isinstance(values, dict) or set(values) != LANGUAGES:
                issues.append(f"{path.name}: {key!r} must have exactly ru/uk/en")
                continue
            expected = Counter(PLACEHOLDER.findall(key))
            for language, translation in values.items():
                if not isinstance(translation, str) or not translation:
                    issues.append(f"{path.name}: empty/non-string {language} for {key!r}")
                elif Counter(PLACEHOLDER.findall(translation)) != expected:
                    issues.append(f"{path.name}: placeholder mismatch in {language} for {key!r}")
            if key in messages and values != messages[key]:
                differing = sorted(language for language in LANGUAGES if values[language] != messages[key][language])
                issues.append(f"{path.name} vs {origins[key].name}: conflicting {','.join(differing)} translation for {key!r}")
            messages[key] = values
            origins[key] = path
    literal_calls = 0
    hints: list[str] = []
    for path in sorted((ROOT / "App").rglob("*.swift")):
        source = path.read_text()
        try:
            strings = SwiftStrings(source).scan()
        except ValueError as error:
            issues.append(f"{path.relative_to(ROOT)}: {error}")
            continue
        for token in strings:
            location = f"{path.relative_to(ROOT)}:{source.count(chr(10), 0, token.start) + 1}"
            is_localized_call = re.search(r"(?<![\w.])L\(\s*$", source[:token.start]) is not None
            if is_localized_call:
                literal_calls += 1
                if token.template and token.template not in messages:
                    issues.append(f"{location}: missing L key {token.template!r}")
            elif args.review_cyrillic and CYRILLIC.search(token.template) and token.template not in messages:
                hints.append(f"{location}: review untranslated literal {token.template!r}")
    for issue in issues:
        print("ERROR:", issue)
    for hint in hints:
        print("REVIEW:", hint)
    print(f"Checked {len(messages)} unique keys across {len(files)} resources and {literal_calls} literal L calls: {len(issues)} errors.")
    if args.review_cyrillic:
        print(f"{len(hints)} Cyrillic literals need human review (may be book data, fixtures, or sentinels).")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
