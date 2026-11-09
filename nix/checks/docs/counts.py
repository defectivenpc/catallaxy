"""Check "<N> floes" and "<N> example labs" in prose against the tree.

Numbers are matched as digits or as words. Only total claims count: a
partitive takes a participle or a relative after the noun ("floes
providing…"), and is skipped.
"""

import json
import pathlib
import re
import sys

WORDS = {
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
    "thirteen": 13,
    "fourteen": 14,
    "fifteen": 15,
    "twenty": 20,
    "twenty-five": 25,
    "twenty-six": 26,
    "twenty-seven": 27,
    "twenty-eight": 28,
    "twenty-nine": 29,
    "thirty": 30,
    "thirty-one": 31,
    "thirty-two": 32,
    "thirty-three": 33,
    "thirty-four": 34,
    "thirty-five": 35,
    "thirty-six": 36,
    "thirty-seven": 37,
    "thirty-eight": 38,
    "thirty-nine": 39,
    "forty": 40,
}

NUMBER = "|".join([r"\d+"] + sorted(WORDS, key=len, reverse=True))

RELATIVES = {"that", "which", "who", "whose", "providing", "with", "in", "of"}


def value(token: str) -> int:
    """Token -> Int"""
    return int(token) if token.isdigit() else WORDS[token.lower()]


def is_partitive(tail: str | None) -> bool:
    """The word after the noun -> whether the claim is about a subset."""
    if not tail:
        return False
    word = tail.strip().strip(",.;:").lower()
    return word.endswith("ing") or word in RELATIVES


def main(expected_path: str, root: str) -> int:
    expected = json.loads(pathlib.Path(expected_path).read_text())
    root = pathlib.Path(root)

    patterns = {
        subject: re.compile(
            rf"\b({NUMBER})\b(?:\s+[a-z-]+){{0,2}}?\s+{re.escape(subject)}\b"
            rf"(?P<tail>\s+\S+)?",
            re.IGNORECASE,
        )
        for subject in expected
    }

    wrong = []
    checked = 0
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root)
        for lineno, line in enumerate(
            path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
        ):
            for subject, pattern in patterns.items():
                for match in pattern.finditer(line):
                    if is_partitive(match.group("tail")):
                        continue
                    checked += 1
                    if value(match.group(1)) != expected[subject]:
                        wrong.append(
                            f"  {rel}:{lineno}: says {match.group(0).strip()!r}, "
                            f"but there are {expected[subject]}"
                        )

    if wrong:
        print(f"{len(wrong)} stale count(s) in prose:", file=sys.stderr)
        for line in wrong:
            print(line, file=sys.stderr)
        print("\nUpdate the sentence, or reword it to carry no count.", file=sys.stderr)
        return 1

    if checked == 0:
        print("no counts matched — the source list in counts.nix is stale.", file=sys.stderr)
        return 1

    summary = ", ".join(f"{v} {k}" for k, v in sorted(expected.items()))
    print(f"{checked} count(s) in prose, all agreeing: {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
