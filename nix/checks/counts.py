"""Check every "<N> floes" and "<N> example labs" in prose against the tree.

See `counts.nix` for why this exists. The short version: the floe count was
stated in four places with four different values, none of them right.

Numbers are matched as digits and as words, because prose prefers words and
"thirty-three floes" goes stale exactly the way "33" does. A word outside the
table below is not matched at all — failing open rather than guessing, since
the alternative is inventing a number nobody wrote.

Only *total* claims count. "Two floes providing `X509_ISSUANCE` in one
cluster is a question only you can answer" is about two floes, not about the
set, and a check that read it as a count of the catalogue would be demanding
the sentence be wrong. The rule separating them is grammatical: a partitive
takes a participle or a relative pronoun after the noun ("floes providing…",
"floes that…"), a total does not. That is not airtight, and it does not need
to be — the failure this exists for is a number in a summary sentence going
stale, and a sentence that survives the rule wrongly costs a reword.
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

# Longest-first, so "thirty-three" is not matched as "thirty".
NUMBER = "|".join([r"\d+"] + sorted(WORDS, key=len, reverse=True))


def value(token: str) -> int:
    return int(token) if token.isdigit() else WORDS[token.lower()]


# A word that turns "N floes" into "N floes of a particular sort" rather than
# "the N floes there are".
RELATIVES = {"that", "which", "who", "whose", "providing", "with", "in", "of"}


def is_partitive(tail: str | None) -> bool:
    if not tail:
        return False
    word = tail.strip().strip(",.;:").lower()
    return word.endswith("ing") or word in RELATIVES


def main(expected_path: str, root: str) -> int:
    expected = json.loads(pathlib.Path(expected_path).read_text())
    root = pathlib.Path(root)

    # "<N> floes", and "<N> built-in floes" / "<N> example labs" — an
    # adjective may sit between the number and the noun, which is how
    # "27 built-in floes" was written.
    patterns = {
        subject: re.compile(
            # An adjective or two may sit between: "27 built-in floes".
            rf"\b({NUMBER})\b(?:\s+[a-z-]+){{0,2}}?\s+{re.escape(subject)}\b"
            # …and what follows decides total vs partitive.
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
                    got = value(match.group(1))
                    if got != expected[subject]:
                        wrong.append(
                            f"  {rel}:{lineno}: says {match.group(0).strip()!r}, "
                            f"but there are {expected[subject]}"
                        )

    if wrong:
        print(f"{len(wrong)} stale count(s) in prose:", file=sys.stderr)
        for line in wrong:
            print(line, file=sys.stderr)
        print(
            "\nThe number is in the tree; prose that repeats it goes stale "
            "silently,\nwhich is why this check exists. Update the sentence, "
            "or reword it so it\ndoes not carry a count at all — the second is "
            "usually the better fix.",
            file=sys.stderr,
        )
        return 1

    if checked == 0:
        print(
            "no counts found in prose at all — either every sentence was "
            "reworded\n(fine, but then remove this check) or the source list "
            "in counts.nix is\nno longer pointing at the files that make "
            "claims.",
            file=sys.stderr,
        )
        return 1

    summary = ", ".join(f"{v} {k}" for k, v in sorted(expected.items()))
    print(f"{checked} count(s) in prose, all agreeing: {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
