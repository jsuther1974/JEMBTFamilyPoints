#!/usr/bin/env python3
"""Download verified public-domain MIDI source editions from Mutopia."""

from __future__ import annotations

import html
import re
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Source:
    slug: str
    title: str
    composer: str
    published: int
    search_term: str


SOURCES = (
    Source("store-entertainer", "The Entertainer", "Scott Joplin", 1902, "The Entertainer"),
    Source("rules-easy-winners", "The Easy Winners", "Scott Joplin", 1901, "Easy Winners"),
    Source("ledger-magnetic-rag", "Magnetic Rag", "Scott Joplin", 1914, "Magnetic Rag"),
    Source("stats-liberty-bell", "The Liberty Bell March", "John Philip Sousa", 1893, "Liberty Bell"),
    Source("family-maple-leaf", "Maple Leaf Rag", "Scott Joplin", 1899, "Maple Leaf Rag"),
)

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "SoundtrackSources"
SEARCH_URL = "https://www.mutopiaproject.org/cgibin/make-table.cgi?searchingfor={}"


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "JEMBTFamilyPoints soundtrack preparation"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def midi_url(source: Source) -> str:
    page_url = SEARCH_URL.format(urllib.parse.quote_plus(source.search_term))
    page = fetch(page_url).decode("utf-8", "replace")
    links = [html.unescape(link) for link in re.findall(r'href="([^"]+\.mid)"', page, flags=re.IGNORECASE)]
    if len(links) != 1:
        raise RuntimeError(f"Expected one MIDI result for {source.title}; found {links}")
    return urllib.parse.urljoin(page_url, links[0])


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = [
        "# Public-domain soundtrack sources",
        "",
        "Downloaded from Mutopia Project source editions marked Public Domain.",
        "The app bundles newly rendered performances, not third-party sound recordings.",
        "",
    ]
    for source in SOURCES:
        url = midi_url(source)
        destination = OUTPUT / f"{source.slug}.mid"
        destination.write_bytes(fetch(url))
        manifest.extend(
            [
                f"## {source.title}",
                f"- Composer: {source.composer}",
                f"- Published: {source.published}",
                "- Composition/source edition status: Public Domain (Mutopia listing)",
                f"- MIDI source: {url}",
                "",
            ]
        )
        print(f"Downloaded {destination.name}")
    (OUTPUT / "README.md").write_text("\n".join(manifest), encoding="utf-8")


if __name__ == "__main__":
    main()
