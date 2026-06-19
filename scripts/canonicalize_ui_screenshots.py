#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
from pathlib import Path


def _sanitize(s: str) -> str:
    # Keep filenames stable across shells/filesystems.
    s = s.strip()
    s = re.sub(r"\s+", "_", s)
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", s)
    s = re.sub(r"_+", "_", s)
    return s.strip("_")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--attachments-dir", required=True)
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()

    manifest_path = Path(args.manifest)
    attachments_dir = Path(args.attachments_dir)
    out_dir = Path(args.out_dir)

    out_dir.mkdir(parents=True, exist_ok=True)

    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise SystemExit(f"unexpected manifest format: expected list, got {type(data).__name__}")

    copied = 0

    for entry in data:
        test_id = entry.get("testIdentifier") or "unknown_test"
        attachments = entry.get("attachments") or []
        for att in attachments:
            exported = att.get("exportedFileName")
            human = att.get("suggestedHumanReadableName") or "attachment"
            if not exported:
                continue

            src = attachments_dir / exported
            if not src.exists():
                continue

            # We only treat image screenshots as visual regression inputs.
            ext = src.suffix.lower()
            if ext not in (".png", ".jpg", ".jpeg"):
                continue

            base = f"{_sanitize(test_id)}__{_sanitize(human)}"
            dst = out_dir / f"{base}{ext}"

            # Avoid collisions (rare, but possible if multiple attachments share name).
            if dst.exists():
                for i in range(2, 1000):
                    cand = out_dir / f"{base}__{i}{ext}"
                    if not cand.exists():
                        dst = cand
                        break

            shutil.copy2(src, dst)
            copied += 1

    print(f"Copied {copied} screenshot(s) to {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

