#!/usr/bin/env python3
"""Check relative Markdown links without requiring a network service."""

from __future__ import annotations

import pathlib
import re
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def main() -> int:
    failures: list[str] = []
    for path in sorted(ROOT.rglob("*.md")):
        if "artifacts" in path.parts or "distfiles" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        for raw in LINK.findall(text):
            target = raw.strip().split("#", 1)[0]
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            if target.startswith("<") and target.endswith(">"):
                target = target[1:-1]
            target = urllib.parse.unquote(target)
            candidate = (path.parent / target).resolve()
            try:
                candidate.relative_to(ROOT)
            except ValueError:
                failures.append(f"{path.relative_to(ROOT)}: link escapes repo: {raw}")
                continue
            if not candidate.exists():
                failures.append(f"{path.relative_to(ROOT)}: missing target: {raw}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("documentation links passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
