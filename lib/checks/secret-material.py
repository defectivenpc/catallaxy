"""Fail if a rendered manifest carries generated secret material.

Rendering happens at build time here, so a chart that mints its own credential
with Helm's `randAlphaNum` puts that credential in the manifest, in the digest
that pins the manifest, and in the Nix store. Worse, the value changes on every
re-render, so applying the lab again silently rotates it — a rotating
REGISTRY_HTTP_SECRET invalidates in-flight uploads, and a rotating Grafana
admin password locks the operator out of the account they were told about.

Grafana's `admin-password` and four of Harbor's internal secrets were exactly
this. Every chart involved takes an `existingSecret`, and `secrets.generate`
mints one in the cluster, which is where a credential belongs.

The test is entropy-shaped because the problem is: a base64 value that decodes
to a long mixed-case alphanumeric run with no structure is what a generator
emits, and is not what anyone writes by hand. A real configuration value has
punctuation, or a word in it, or is short.
"""

import base64
import os
import re
import sys

# `  key: value` at the indent Secret data sits at.
ENTRY = re.compile(r"^\s{2}([A-Za-z0-9_.-]+):\s*([A-Za-z0-9+/=]{16,})\s*$")

MIN_LENGTH = 12


def generated_value(encoded: str) -> str | None:
    """The decoded value, if it looks like something a generator emitted."""
    try:
        decoded = base64.b64decode(encoded, validate=True).decode()
    except Exception:
        return None
    if len(decoded) < MIN_LENGTH or not decoded.isalnum():
        return None
    # All three classes present is what `randAlphaNum` produces and what a
    # hand-written value almost never is.
    has = lambda pred: any(pred(c) for c in decoded)  # noqa: E731
    if not (has(str.islower) and has(str.isupper) and has(str.isdigit)):
        return None
    return decoded


def main() -> int:
    root = os.path.join(sys.argv[1], "manifests")
    findings = []

    for dirpath, _dirnames, filenames in os.walk(root, followlinks=True):
        for filename in sorted(filenames):
            if not filename.endswith(".yaml"):
                continue
            path = os.path.join(dirpath, filename)
            with open(path, errors="replace") as handle:
                for number, line in enumerate(handle.read().splitlines(), 1):
                    match = ENTRY.match(line)
                    if not match:
                        continue
                    if generated_value(match.group(2)):
                        findings.append(
                            (os.path.relpath(path, root), number, match.group(1))
                        )

    if not findings:
        return 0

    print("a rendered manifest carries generated secret material:", file=sys.stderr)
    for path, number, key in findings:
        print(f"  {path}:{number}: {key}", file=sys.stderr)
    print(
        "\nThe chart minted this while rendering, so it is in the manifest, in "
        "the digest\nthat pins it and in the Nix store, and it changes on every "
        "re-render.\n\nPoint the chart at an `existingSecret` and mint the value "
        "with `secrets.generate`,\nthe way harbor and grafana do. The value is "
        "not printed here on purpose.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
