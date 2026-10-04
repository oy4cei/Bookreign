#!/usr/bin/env python3
"""Copy unchanged Xcode screenshots into locale/device folders."""
import argparse
import json
import re
import shutil
import struct
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("attachments", type=Path, help="xcresulttool export attachments output directory")
parser.add_argument("device", choices=["iphone-6.9", "ipad-13"])
parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent.parent / "docs/app-store/screenshots")
args = parser.parse_args()
expected = {"iphone-6.9": (1320, 2868), "ipad-13": (2064, 2752)}[args.device]
count = 0
for test in json.loads((args.attachments / "manifest.json").read_text()):
    for item in test["attachments"]:
        match = re.match(r"app-store-(en|uk|ru)-(\d{2}-[a-z-]+)_", item["suggestedHumanReadableName"])
        if not match:
            continue
        locale, name = match.groups()
        source = args.attachments / item["exportedFileName"]
        data = source.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"Not a PNG: {source}")
        size = struct.unpack(">II", data[16:24])
        if size != expected:
            raise ValueError(f"Unexpected screenshot dimensions {size}: {source}")
        if data[25] in (4, 6):
            raise ValueError(f"Screenshot has an alpha channel: {source}")
        destination = args.output / locale / args.device / (name + ".png")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        count += 1
        print(destination)
if count != 12:
    raise ValueError(f"Expected four screenshots in each of three locales, received {count}")
print(f"Copied {count} unchanged screenshots, {expected[0]}×{expected[1]}, without alpha.")
