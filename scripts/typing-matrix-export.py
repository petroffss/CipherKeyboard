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
p.add_argument("--encrypt", action="store_true", help="Export the separate 126-frame encrypt-insert contract")
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
frames, geometries = {}, {}
loaded_builds = set()
pattern = re.compile(r"(typing|smoke|encrypt)-(frame|geometry)--(extension|preview)--(375|402|440)--(portrait|landscape)--(light|dark)--([a-z-]+)")
for index, result in enumerate(a.results):
    dest = a.output / ("raw-" + str(index))
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", str(dest)], check=True, stdout=subprocess.DEVNULL)
    for test in json.loads((dest / "manifest.json").read_text()):
        for attachment in test["attachments"]:
            match = pattern.search(attachment["suggestedHumanReadableName"])
            if not match:
                continue
            prefix, artifact, kind, width, orientation, theme, state = match.groups()
            if (a.encrypt and prefix != "encrypt") or (not a.encrypt and a.complete and prefix != "typing"):
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
                    "referenceAnchor": "state-" + state, "geometry": None, "visualReview": "pending"}
for key, frame in frames.items():
    if key not in geometries: raise SystemExit("Missing geometry: " + str(key))
    frame["geometry"] = geometries[key]
    geometry = frame["geometry"]
    build = re.search(r"build=(\d+);", geometry["build"])
    if not build: raise SystemExit("Missing loaded revision: " + str(key))
    loaded_builds.add(build.group(1))
    if tuple(geometry[field] for field in ["kind", "width", "orientation", "theme", "state"]) != key:
        raise SystemExit("Attachment/geometry identity mismatch: " + str(key))
    rendered = geometry.get("rendered", {})
    if rendered.get("resolvedTheme") != key[3]: raise SystemExit("Actual rendered theme mismatch: " + str(key))
    if not a.encrypt and rendered.get("caretVisible") is not True: raise SystemExit("Caret is not visible: " + str(key))
    if key[0] == "extension":
        field = geometry.get("hostField", {})
        rect, visible = field.get("frame", {}), field.get("visibleIntersection", {})
        if not field.get("hittable") or rect.get("height", 0) < 48:
            raise SystemExit("Actual host field not usable: " + str(key))
        if any(abs(rect.get(part, -1) - visible.get(part, -2)) > 0.5 for part in ["x", "y", "width", "height"]):
            raise SystemExit("Actual host field clipped: " + str(key))
        if rect["y"] + rect["height"] > geometry["panel"]["y"] + 0.5:
            raise SystemExit("Actual host field overlaps panel: " + str(key))
    landscape = key[2] == "landscape"
    if not a.encrypt:
        warning = key[4] in ["no-access", "no-key", "key-error", "contacts-error"]
        landscape = key[2] == "landscape"
        if rendered.get("warning") != warning or rendered.get("statusFont") != (10 if landscape else (12 if warning else 11)):
            raise SystemExit("Status emphasis differs from anchor: " + str(key))
        if warning:
            primary = [1, 1, 1, 1] if key[3] == "dark" else [0, 0, 0, 1]
            color = rendered.get("statusColor", [])
            # Match the UI assertion's sub-quantization tolerance for UIColor color-space conversion.
            if (rendered.get("statusLineHeight") != (12 if landscape else 15) or len(color) != 4 or
                    any(abs(actual - expected) > 0.000001 for actual, expected in zip(color, primary))):
                raise SystemExit("Warning text style differs from anchor: " + str(key))
        if key[4] in ["multiline", "limit"] and rendered.get("cursor") != 0:
            raise SystemExit("Reference excerpt start caret changed: " + str(key))
        if key[4] in ["multiline", "limit"]:
            letters = {item["id"]: item["label"] for item in geometry["keys"]}
            if letters.get("keyboard.key.й") != "й": raise SystemExit("Reference lowercase state changed: " + str(key))
        if key[4] == "limit" and rendered.get("byteCount") != 4096:
            raise SystemExit("Limit fixture is not 4096 bytes: " + str(key))
    point_size = (int(key[1]), {375: 667, 402: 874, 440: 956}[key[1]])
    if landscape: point_size = point_size[::-1]
    if frame["pixels"] != [round(value * geometry["scale"]) for value in point_size]:
        raise SystemExit("Screenshot is not the native profile resolution: " + str(key))
if len(loaded_builds) > 1: raise SystemExit("Mixed loaded source revisions: " + str(loaded_builds))
states = ["ru-empty", "ru-text", "shift", "caps", "en", "numbers", "symbols", "alternate-e", "alternate-softsign", "multiline", "limit", "no-access", "no-key", "key-error", "contacts-error"]
expected = {("extension", width, orientation, theme, state) for width in [375, 402, 440] for orientation in ["portrait", "landscape"] for theme in ["light", "dark"] for state in states}
expected |= {("preview", width, "portrait", theme, "preview") for width in [375, 402, 440] for theme in ["light", "dark"]}
if a.encrypt:
    states = ["unselected", "empty", "ready", "picker", "no-contacts", "sending", "success", "limit", "no-key", "key-error", "contacts-error", "no-access", "changed", "selection", "failure", "document-changed", "long-name"]
    expected = {("extension", width, "portrait", theme, state) for width in [375, 402, 440] for theme in ["light", "dark"] for state in states}
    expected |= {("extension", width, "landscape", theme, state) for width in [375, 402, 440] for theme in ["light", "dark"] for state in ["ready", "picker", "limit", "long-name"]}
expected_count = 126 if a.encrypt else 186
missing = sorted(expected - frames.keys())
unexpected = sorted(frames.keys() - expected)
if unexpected: raise SystemExit("Unexpected matrix frames: " + str(unexpected))
manifest = {"complete": not missing, "count": len(frames), "expected": expected_count, "missing": missing,
            "comparison": "Geometry assertions executed in Simulator; every frame maps to the corresponding mockup anchor for independent visual review.",
            "frames": [frames[key] for key in sorted(frames)]}
(a.output / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
print("Captured %d/%d corresponding frames; complete=%s" % (len(frames), expected_count, not missing))
if a.complete and (missing or len(frames) != expected_count): raise SystemExit(1)
