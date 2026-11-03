#!/usr/bin/env python3
"""Guard the extension's narrow host, storage, log and clipboard boundaries."""
import argparse
from bisect import bisect_right
from pathlib import Path
import re
import sys

PACKAGE = "Packages/CipherCore/Sources/KeyboardTyping"
ROOTS = ("Keyboard", PACKAGE)
# Exact lines, with count, permit the current capabilities without granting an entire source file.
ALLOW = {
    f"{PACKAGE}/KeyboardInput.swift": {
        "public mutating func deleteBackward() {",
        "input.deleteBackward()",
        "self.input.deleteBackward()",
    },
    f"{PACKAGE}/KeyboardExtensionController.swift": {
        "(textDocumentProxy as? NSObject)?.value(forKey: #keyPath(UITextDocumentProxy.documentIdentifier)) as? UUID",
        'public var hasSelection: Bool { !(textDocumentProxy.selectedText ?? "").isEmpty }',
        "public func insertCiphertext(_ ciphertext: String) { textDocumentProxy.insertText(ciphertext) }",
        "KeyboardAccessRecorder.record(hasFullAccess: permitted) { FileKeyboardSetupStorage.appGroup }",
    },
    f"{PACKAGE}/EncryptInsert.swift": {
        "private let defaults: () -> UserDefaults",
        "public init(defaults: @escaping () -> UserDefaults = { .standard }) { self.defaults = defaults }",
        "get { defaults().string(forKey: key).flatMap(UUID.init(uuidString:)) }",
        "defaults().set(newValue.uuidString, forKey: key)",
        "defaults().removeObject(forKey: key)",
    },
    f"{PACKAGE}/DecryptUIKit.swift": {
        "let board = UIPasteboard.general",
        "guard board.hasStrings else { return .empty }",
        "guard let value = board.string else { return .denied }",
    },
}
BOUNDARY = re.compile(
    r"\b(?:textDocumentProxy|UITextDocumentProxy|insertText|deleteBackward|setMarkedText|unmarkText|"
    r"adjustTextPosition|documentContextBeforeInput|"
    r"documentContextAfterInput|UIPasteboard|NSPasteboard|UIPasteControl|UserDefaults|NSUserDefaults|board|defaults|"
    r"Logger|OSLog|os_log|os_signpost|NSLog|FileManager|FileHandle|SecItemAdd|SecItemUpdate|SecItemDelete)\b"
    r"|\b(?:print|debugPrint|dump|fopen|fwrite)\s*\("
    r"|\bKeyboardAccessRecorder\s*\."
    r"|\.write\s*\(\s*(?:to|toFile)\s*:"
)


def check(root):
    violations = []
    used = set()
    for directory in ROOTS:
        folder = root / directory
        if not folder.is_dir():
            violations.append(f"{directory}: missing source directory")
            continue
        for file in sorted(folder.rglob("*.swift")):
            path = file.relative_to(root).as_posix()
            lines = file.read_text().splitlines(keepends=True)
            offsets = []
            offset = 0
            code = []
            for line in lines:
                offsets.append(offset)
                offset += len(line)
                code.append(re.sub(r"[^\r\n]", " ", line) if line.lstrip().startswith("//") else line)
            # Scan the whole source so a newline after e.g. .write( cannot hide the call.
            matched_lines = {}
            for match in BOUNDARY.finditer("".join(code)):
                index = bisect_right(offsets, match.start()) - 1
                matched_lines.setdefault(index, match.group().strip().splitlines()[0])
            for index, boundary in sorted(matched_lines.items()):
                line = lines[index].strip()
                entry = (path, line)
                if line in ALLOW.get(path, set()) and entry not in used:
                    used.add(entry)
                else:
                    violations.append(f"{path}:{index + 1}: unapproved extension boundary ({boundary})")
    for path, lines in ALLOW.items():
        if any((path, line) not in used for line in lines):
            violations.append(f"{path}: stale boundary allowance; review and update the exact list")
    return violations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    violations = check(args.root)
    for violation in violations:
        print(violation, file=sys.stderr)
    if violations:
        return 1
    print("Границы расширения: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
