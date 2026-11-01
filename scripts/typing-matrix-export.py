#!/usr/bin/env python3
"""Export exact screenshot/geometry pairs; reject missing/duplicate frames in the 186-frame matrix."""
import argparse
import json
import pathlib
import re
import struct
import subprocess

def displayed_pixels(png):
    width, height = struct.unpack(">II", png[16:24])
    orientation = 1
    offset = 8
    while offset < len(png):
        length = struct.unpack(">I", png[offset:offset + 4])[0]
        if png[offset + 4:offset + 8] == b"eXIf":
            tiff = png[offset + 8:offset + 8 + length]
            endian = ">" if tiff[:2] == b"MM" else "<"
            directory = struct.unpack(endian + "I", tiff[4:8])[0]
            count = struct.unpack(endian + "H", tiff[directory:directory + 2])[0]
            for index in range(count):
                entry = directory + 2 + index * 12
                tag, kind, items = struct.unpack(endian + "HHI", tiff[entry:entry + 8])
                if tag == 274 and kind == 3 and items == 1:
                    orientation = struct.unpack(endian + "H", tiff[entry + 8:entry + 10])[0]
        offset += length + 12
    # XCTest's full-display PNG keeps portrait raster storage and EXIF orientation 8 in landscape.
    return ((height, width) if orientation in [5, 6, 7, 8] else (width, height)), orientation


p = argparse.ArgumentParser()
p.add_argument("output", type=pathlib.Path)
p.add_argument("results", nargs="+", type=pathlib.Path)
p.add_argument("--complete", action="store_true")
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
frames, geometries = {}, {}
pattern = re.compile(r"(typing|smoke)-(frame|geometry)--(extension|preview)--(375|402|440)--(portrait|landscape)--(light|dark)--([a-z-]+)")
for index, result in enumerate(a.results):
    dest = a.output / ("raw-" + str(index))
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", str(dest)], check=True, stdout=subprocess.DEVNULL)
    for test in json.loads((dest / "manifest.json").read_text()):
        for attachment in test["attachments"]:
            match = pattern.search(attachment["suggestedHumanReadableName"])
            if not match:
                continue
            prefix, artifact, kind, width, orientation, theme, state = match.groups()
            if a.complete and prefix != "typing":
                continue
            key = (kind, int(width), orientation, theme, state)
            path = dest / attachment["exportedFileName"]
            if artifact == "geometry":
                if key in geometries: raise SystemExit("Duplicate geometry: " + str(key))
                geometries[key] = json.loads(path.read_text())
            else:
                if key in frames: raise SystemExit("Duplicate frame: " + str(key))
                png = path.read_bytes()
                pixels, exif_orientation = displayed_pixels(png)
                if (pixels[0] > pixels[1]) != (orientation == "landscape"):
                    raise SystemExit("Screenshot orientation differs from frame metadata: " + str(key))
                frames[key] = {"kind": kind, "width": int(width), "orientation": orientation, "theme": theme, "state": state,
                    "file": str(path.resolve()), "pixels": list(pixels), "exifOrientation": exif_orientation, "result": str(result.resolve()),
                    "referenceAnchor": "state-" + state, "geometry": None}
for key, frame in frames.items():
    if key not in geometries: raise SystemExit("Missing geometry: " + str(key))
    frame["geometry"] = geometries[key]
    if "build=" not in frame["geometry"]["build"]: raise SystemExit("Missing loaded revision: " + str(key))
states = ["ru-empty", "ru-text", "shift", "caps", "en", "numbers", "symbols", "alternate-e", "alternate-softsign", "multiline", "limit", "no-access", "no-key", "key-error", "contacts-error"]
expected = {("extension", width, orientation, theme, state) for width in [375, 402, 440] for orientation in ["portrait", "landscape"] for theme in ["light", "dark"] for state in states}
expected |= {("preview", width, "portrait", theme, "preview") for width in [375, 402, 440] for theme in ["light", "dark"]}
missing = sorted(expected - frames.keys())
manifest = {"complete": not missing, "count": len(frames), "expected": 186, "missing": missing,
            "comparison": "Geometry assertions executed in Simulator; every frame maps to the corresponding mockup anchor for independent visual review.",
            "frames": [frames[key] for key in sorted(frames)]}
(a.output / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
print("Captured %d/186 corresponding frames; complete=%s" % (len(frames), not missing))
if a.complete and (missing or len(frames) != 186): raise SystemExit(1)
