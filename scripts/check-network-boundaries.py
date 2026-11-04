#!/usr/bin/env python3
"""Static tripwire for network APIs and external URL actions; not a Swift security sandbox."""
import argparse
from pathlib import Path
import re
import sys

ROOTS = ("App", "Keyboard", "UITests", "DebugHost", "DebugHostTests", "Packages/CipherCore")
NETWORK = re.compile(
    r"\b(?:URLSession\w*|URLRequest|NSURLConnection|NSURLSession\w*|NSURLRequest|"
    r"NWConnection\w*|NWListener|NWBrowser|NWPathMonitor|NWEndpoint|"
    r"CFNetwork\w*|CFStream\w*|CFSocket\w*|CFHTTP\w*|SCNetwork\w*|"
    r"getaddrinfo|CKContainer|NSUbiquitous\w*|WCSession|WKWebView|SFSafariViewController|"
    r"ASWebAuthenticationSession|MultipeerConnectivity|MCSession)\b"
    r"|\b(?:socket|connect|sendto|recvfrom)\s*\("
    r"|\bimport\s+(?:Network|WebKit|MultipeerConnectivity|CloudKit|WatchConnectivity|"
    r"SafariServices|AuthenticationServices|CFNetwork)\b"
)
EXTERNAL = re.compile(r"\b(?:UIApplication|NSExtensionContext|openURL)\b|\bLink\s*\(")
ALLOW = {
    "DebugHost/TypingHost.swift": {
        "_ application: UIApplication, configurationForConnecting session: UISceneSession,",
    },
    "App/SetupModel.swift": {
        "guard let url = URL(string: UIApplication.openSettingsURLString) else {",
        "openResult && url.absoluteString == UIApplication.openSettingsURLString",
    },
    "App/DecryptView.swift": {
        "UIApplication.shared.sendAction(",
        "self, selector: #selector(hideContent), name: UIApplication.willResignActiveNotification, object: nil)",
        "self, selector: #selector(reveal), name: UIApplication.didBecomeActiveNotification, object: nil)",
    },
}
# Review the complete capability, not just the call line: its URL must never come from user data.
SETTINGS_CODE = """import UIKit
@MainActor enum SystemSettings {
    @discardableResult static func open() async -> Bool {
        guard let settings = URL(string: UIApplication.openSettingsURLString) else { return false }
        return await UIApplication.shared.open(settings)
    }
}
"""


def code_only(source):
    # Preserve offsets/newlines. Block/inline comments remain scanned conservatively.
    return "".join("\n" if line.lstrip().startswith("//") else line for line in source.splitlines(True))


def violations(path, source):
    code = code_only(source)
    errors = []
    for match in NETWORK.finditer(code):
        errors.append(f"{path}:{code[:match.start()].count(chr(10)) + 1}: forbidden network API {match.group()}")
    if path == "App/SystemSettings.swift":
        if code.split() != SETTINGS_CODE.split():
            errors.append(f"{path}: Settings-only capability changed; review the entire destination construction")
        return errors
    used = set()
    for match in EXTERNAL.finditer(code):
        line = code[:match.start()].count("\n")
        text = code.splitlines()[line].strip()
        if text in ALLOW.get(path, set()) and text not in used:
            used.add(text)
        else:
            errors.append(f"{path}:{line + 1}: unapproved external URL capability")
    return errors


def check(root):
    errors = []
    for folder in ROOTS:
        directory = root / folder
        if not directory.is_dir():
            errors.append(f"{folder}: missing source directory")
            continue
        for file in sorted(directory.rglob("*.swift")):
            if {".build", ".swiftpm"}.intersection(file.parts):
                continue
            errors.extend(violations(file.relative_to(root).as_posix(), file.read_text()))
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    errors = check(args.root)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        sys.exit(1)
    print("Сеть и внешние URL: OK")
