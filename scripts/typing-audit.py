#!/usr/bin/env python3
"""Read-only before/after audit of the disposable simulator; never dumps key material."""
import os
import uuid
import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import sqlite3
import subprocess
import sys

ENCRYPT = os.environ.get("CIPHER_AUDIT_FEATURE") == "06"
CANARY = "EncryptCanary06-Ж-20261102" if ENCRYPT else "TypingCanary05-Ж-20261101"
SENTINEL = "TypingClipboardSentinel05-20261101"


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def device_guard(udid):
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "-j"))["devices"]
    device = next(d for group in devices.values() for d in group if d["udid"] == udid)
    if not device["name"].startswith("CipherKeyboard-Typing-"):
        raise SystemExit("Audit is restricted to explicitly disposable CipherKeyboard-Typing-* simulators")
    return device


def container(udid, bundle, kind):
    return pathlib.Path(run("xcrun", "simctl", "get_app_container", udid, bundle, kind).decode().strip())


def extension_container(udid):
    root = pathlib.Path.home() / "Library/Developer/CoreSimulator/Devices" / udid / "data/Containers/Data/PluginKitPlugin"
    matches = []
    for metadata in root.glob("*/.com.apple.mobile_container_manager.metadata.plist"):
        if plistlib.loads(metadata.read_bytes()).get("MCMMetadataIdentifier") == "dev.cipherkeyboard.app.keyboard":
            matches.append(metadata.parent)
    if len(matches) != 1:
        raise SystemExit("Expected exactly one extension data container, found " + str(len(matches)))
    return matches[0]


def snapshot(udid, output):
    device = device_guard(udid)
    roots = {
        "app": container(udid, "dev.cipherkeyboard.app", "data"),
        "extension": extension_container(udid),
        "group": container(udid, "dev.cipherkeyboard.app", "group.dev.cipherkeyboard"),
    }
    files, matches, defaults = {}, [], {}
    recipient_preferences = {}
    defaults_without_recipient = {}
    patterns = [CANARY.encode(), CANARY.encode("utf-16le"), CANARY.encode("utf-16be")]
    if ENCRYPT: patterns += [b"ckmsg1:", "ckmsg1:".encode("utf-16le"), "ckmsg1:".encode("utf-16be")]
    for label, root in roots.items():
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path.is_symlink():
                continue
            key = label + "/" + str(path.relative_to(root))
            data = path.read_bytes()
            files[key] = {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
            if any(p in data for p in patterns):
                matches.append(key)
            if "/Preferences/" in key and path.suffix == ".plist":
                try:
                    values = plistlib.loads(data)
                    if key == "extension/Library/Preferences/dev.cipherkeyboard.app.keyboard.plist":
                        recipient_preferences = {k: v for k, v in values.items() if k == "keyboard.lastRecipientID"}
                        values_without = {k: v for k, v in values.items() if k != "keyboard.lastRecipientID"}
                        defaults_without_recipient[key] = hashlib.sha256(plistlib.dumps(values_without, sort_keys=True)).hexdigest()
                    canonical = plistlib.dumps(values, sort_keys=True)
                    defaults[key] = hashlib.sha256(canonical).hexdigest()
                except plistlib.InvalidFileException:
                    defaults[key] = "unreadable"
    keychain = pathlib.Path.home() / "Library/Developer/CoreSimulator/Devices" / udid / "data/Library/Keychains/keychain-2.db"
    if not keychain.exists():
        keychain = keychain.with_name("keychain-2-debug.db")
    metadata = []
    with sqlite3.connect("file:" + str(keychain) + "?mode=ro", uri=True) as db:
        columns = {r[1] for r in db.execute("PRAGMA table_info(genp)")}
        selected = [name for name in ["agrp", "svce", "acct", "cdat", "mdat", "UUID", "persistref"] if name in columns]
        if not {"agrp", "svce", "acct"}.issubset(columns):
            raise SystemExit("Unexpected Keychain schema; do not silently skip metadata audit")
        # Only identifying metadata is selected. Secret/value columns are never queried.
        # Simulator indexes svce/acct as opaque 20-byte blobs: casting them to TEXT
        # silently matched zero rows. The real identity uses this explicit access group.
        for row in db.execute("SELECT " + ",".join(selected) + " FROM genp WHERE agrp = ? ORDER BY rowid", ("group.dev.cipherkeyboard",)):
            metadata.append({name: hashlib.sha256(str(value).encode()).hexdigest() for name, value in zip(selected, row)})
    clipboard = run("xcrun", "simctl", "pbpaste", udid)
    result = {
        "timestamp": datetime.datetime.now().astimezone().isoformat(), "udid": udid, "device": device["name"],
        "roots": {key: str(value) for key, value in roots.items()}, "files": files,
        "defaults": defaults, "recipientPreference": recipient_preferences, "defaultsWithoutRecipient": defaults_without_recipient, "keychainMetadataHashes": metadata, "canaryMatches": matches,
        "clipboardSha256": hashlib.sha256(clipboard).hexdigest(),
        "clipboardIsSentinel": clipboard == SENTINEL.encode(),
    }
    result["setupFailures"] = []
    if not result["clipboardIsSentinel"]: result["setupFailures"].append("clipboard sentinel not installed")
    if len(metadata) != 1: result["setupFailures"].append("expected one real identity metadata entry, got " + str(len(metadata)))
    if matches: result["setupFailures"].append("canary already present in baseline files")
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False))
    print(json.dumps({"snapshot": str(output), "identityMetadataRows": len(metadata), "setupFailures": result["setupFailures"]}))
    return bool(result["setupFailures"])


def compare(before_path, after_path, output):
    before, after = json.loads(before_path.read_text()), json.loads(after_path.read_text())
    if before["udid"] != after["udid"]:
        raise SystemExit("Snapshot devices differ")
    changes = [key for key in sorted(before["files"].keys() | after["files"].keys()) if before["files"].get(key) != after["files"].get(key)]
    allowed, unexpected = [], []
    for path in changes:
        if path == "group/keyboard-access.v1.json":
            record = json.loads((pathlib.Path(after["roots"]["group"]) / "keyboard-access.v1.json").read_text())
            if set(record) == {"version", "date"} and record["version"] == 1 and isinstance(record["date"], (int, float)):
                allowed.append(path)
                continue
        if ENCRYPT and path == "extension/Library/Preferences/dev.cipherkeyboard.app.keyboard.plist":
            values = after.get("recipientPreference", {})
            valid = set(values).issubset({"keyboard.lastRecipientID"})
            if values:
                try: uuid.UUID(values["keyboard.lastRecipientID"])
                except (ValueError, TypeError): valid = False
            empty_hash = hashlib.sha256(plistlib.dumps({}, sort_keys=True)).hexdigest()
            unchanged_others = before.get("defaultsWithoutRecipient", {}).get(path, empty_hash) == after.get("defaultsWithoutRecipient", {}).get(path, empty_hash)
            if valid and unchanged_others:
                allowed.append(path); continue
        unexpected.append(path)
    logs = subprocess.run(["xcrun", "simctl", "spawn", before["udid"], "log", "show", "--style", "compact", "--start", datetime.datetime.fromisoformat(before["timestamp"]).strftime("%Y-%m-%d %H:%M:%S"), "--predicate", 'process == "CipherKeyboard" OR process == "CipherKeyboardExtension" OR process == "TypingHost"'], capture_output=True)
    logs_path = output.with_suffix(".log")
    logs_path.write_bytes(logs.stdout + logs.stderr)
    failures = []
    if before.get("setupFailures"): failures.append("invalid before setup: " + "; ".join(before["setupFailures"]))
    if not before["keychainMetadataHashes"] or not after["keychainMetadataHashes"]:
        failures.append("empty identity metadata coverage")
    if logs.returncode: failures.append("log capture failed")
    if CANARY.encode() in logs.stdout: failures.append("canary found in scoped logs")
    if after["canaryMatches"]: failures.append("canary found in files")
    if not before["clipboardIsSentinel"]: failures.append("clipboard sentinel missing before test")
    if before["clipboardSha256"] != after["clipboardSha256"] or not after["clipboardIsSentinel"]:
        failures.append("clipboard sentinel changed during test")
    if before["keychainMetadataHashes"] != after["keychainMetadataHashes"]: failures.append("keychain metadata changed")
    changed_defaults = {key for key in before["defaults"].keys() | after["defaults"].keys() if before["defaults"].get(key) != after["defaults"].get(key)}
    if changed_defaults - set(allowed): failures.append("defaults changed outside the permitted recipient UUID")
    if unexpected: failures.append("unexpected file changes require investigation")
    result = {"result": "pass" if not failures else "fail", "failures": failures, "allowedReceiptChanges": allowed,
              "unexpectedChanges": unexpected, "canaryMatches": after["canaryMatches"], "logs": str(logs_path),
              "before": str(before_path), "after": str(after_path)}
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False))
    print(json.dumps(result, ensure_ascii=False))
    return bool(failures)


parser = argparse.ArgumentParser()
sub = parser.add_subparsers(dest="action", required=True)
s = sub.add_parser("snapshot"); s.add_argument("udid"); s.add_argument("output", type=pathlib.Path)
t = sub.add_parser("set-sentinel"); t.add_argument("udid"); t.add_argument("output", type=pathlib.Path)
c = sub.add_parser("compare"); c.add_argument("before", type=pathlib.Path); c.add_argument("after", type=pathlib.Path); c.add_argument("output", type=pathlib.Path)
a = parser.parse_args()
if a.action == "snapshot": sys.exit(snapshot(a.udid, a.output))
elif a.action == "set-sentinel":
    device_guard(a.udid)
    subprocess.run(["xcrun", "simctl", "pbcopy", a.udid], input=SENTINEL.encode(), check=True)
    actual = run("xcrun", "simctl", "pbpaste", a.udid)
    result = {"udid": a.udid, "clipboardIsSentinel": actual == SENTINEL.encode(),
              "clipboardSha256": hashlib.sha256(actual).hexdigest(), "size": len(actual)}
    a.output.write_text(json.dumps(result, indent=2))
    print(json.dumps(result))
    sys.exit(0 if result["clipboardIsSentinel"] else "Sentinel setup invalid; preserve evidence and do not run audit UI")
else: sys.exit(compare(a.before, a.after, a.output))
