"""Every internal link in the built book resolves to a page that exists.

mdbook rewrites `./foo.md` to `foo.html` when it renders, so a link to a page
that was renamed or moved becomes a 404 rather than a build error. That is the
gap this closes, and it is not hypothetical: the book carried links to
`reference/options/lab.md` and `reference/options/floes/index.md` for as long
as the generator that produced those pages had been parked.

Only same-document and relative links are checked. An `http(s)` link is a claim
about somebody else's server, which cannot be verified without a network and
should not be verified in a build.

Anchors are checked too, because a link to `#the-scope-rule` on a page that no
longer has that heading is the same defect one level down, and renaming a
heading is exactly how it happens.
"""

import html.parser
import pathlib
import re
import sys
import urllib.parse


class Links(html.parser.HTMLParser):
    """Hrefs and anchor ids from one rendered page."""

    def __init__(self):
        super().__init__()
        self.hrefs = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        # mdbook puts an `id` on every heading it renders, which is what a
        # `#fragment` link resolves against.
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "a" and "href" in attrs:
            self.hrefs.append(attrs["href"])


def main(root: str) -> int:
    root = pathlib.Path(root)
    pages = sorted(root.rglob("*.html"))
    if not pages:
        print(f"no HTML under {root} — the book did not build", file=sys.stderr)
        return 1

    ids = {}
    hrefs = {}
    for page in pages:
        parser = Links()
        parser.feed(page.read_text(encoding="utf-8", errors="replace"))
        ids[page] = parser.ids
        hrefs[page] = parser.hrefs

    broken = []
    checked = 0
    for page in pages:
        for href in hrefs[page]:
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", href) or href.startswith("//"):
                continue  # someone else's server, or mailto:
            target, _, fragment = href.partition("#")
            target = urllib.parse.unquote(target)
            checked += 1

            if not target:
                dest = page  # same-document anchor
            else:
                dest = (page.parent / target).resolve()
                if dest.is_dir():
                    dest = dest / "index.html"
                if not dest.is_file():
                    broken.append(
                        f"  {page.relative_to(root)} -> {href} (no such page)"
                    )
                    continue

            if fragment and fragment not in ids.get(dest, set()):
                broken.append(
                    f"  {page.relative_to(root)} -> {href} "
                    f"(page exists; no heading '{fragment}')"
                )

    if broken:
        print(
            f"{len(broken)} broken link(s) in the book:", file=sys.stderr
        )
        for line in sorted(broken):
            print(line, file=sys.stderr)
        print(
            "\nA link that 404s is worse than no link: it tells the reader the "
            "page exists.\nEither fix the path, or say in prose what the page "
            "would have said.",
            file=sys.stderr,
        )
        return 1

    print(f"{len(pages)} pages, {checked} internal links, all resolving")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
