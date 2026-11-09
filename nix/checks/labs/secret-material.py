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

Three shapes are refused: a mixed-case alphanumeric run (`randAlphaNum`), a
PEM private key (`genSelfSignedCert`), and an htpasswd line (`htpasswd`). The
first is entropy-shaped; the other two are structural, and were missed for as
long as the test assumed a generated value is alphanumeric — harbor's chart
minted a token-signing keypair on every render and this said nothing.
"""

import base64
import os
import re
import sys

# `  key: value` at the indent Secret data sits at.
ENTRY = re.compile(r"^\s{2}([A-Za-z0-9_.-]+):\s*\"?([A-Za-z0-9+/=]{16,})\"?\s*$")

MIN_LENGTH = 12

PEM_PRIVATE_KEY = re.compile(r"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----")

# `user:$2a$10$…` — bcrypt is the only hash htpasswd accepts here.
HTPASSWD = re.compile(r"^[^:\s]+:\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$")


def generated_value(encoded: str) -> str | None:
    """The decoded value, if it looks like something a generator emitted."""
    try:
        decoded = base64.b64decode(encoded, validate=True).decode()
    except Exception:
        return None

    if PEM_PRIVATE_KEY.search(decoded):
        return decoded
    if HTPASSWD.match(decoded.strip()):
        return decoded

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
