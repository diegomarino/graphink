#!/usr/bin/env python3
"""Link exact production app objects into an offscreen Edit > Find fixture.

Checks the main menu's Find submenu and that no two menu items share a shortcut, then drives the
system find bar in a nib-loaded document window: matches across label kinds in reading order,
wraparound, scrolling at 400%, no match, Use Selection for Find, incremental search, Find inside
a label being edited, undo neutrality, and what the find indicator draws at 50%, 400% and in
Chalkboard. The shared find pasteboard is restored afterwards.
Run with host AppKit access. Never shows a window or runs a launch loop.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__, epilog="Example: python3 Checks/check-key-loop.py --products /tmp/own/Debug/Products/Debug --objects /tmp/own/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/Graphink.LinkFileList --output /tmp/find-new")
parser.add_argument("--products", required=True, type=Path, help="Exact current-source Debug products")
parser.add_argument("--objects", required=True, type=Path, help="Matching Graphink.LinkFileList from that build")
parser.add_argument("--output", required=True, type=Path, help="Fresh owned evidence directory; existing paths refused")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
products, output = args.products.resolve(), args.output.resolve()
if output.exists():
    parser.error("Output exists; choose a fresh evidence directory")
if not args.objects.is_file() or not (products / "Graphink.app/Contents/Resources").is_dir():
    parser.error("Missing objects/products; first build this exact candidate")
objects = [Path(line) for line in args.objects.read_text().splitlines() if Path(line).name != "main.o"]
if not objects or not all(path.is_file() for path in objects):
    parser.error("LinkFileList contains missing objects; use matching build products")

# Edit > Find in the main menu: standard titles, tags (NSTextFinderAction) and shortcuts, and no
# shortcut used twice anywhere in the menu bar.
def menu_shortcuts(path):
    found, items = {}, {}
    for item in ET.parse(path).iter("menuItem"):
        key = item.get("keyEquivalent")
        mask = item.find("modifierMask[@key='keyEquivalentModifierMask']")
        modifiers = {name for name in ("shift", "control", "option", "command") if mask is not None and mask.get(name) == "YES"}
        if mask is None:
            modifiers = {"command"}
        if key and key.lower() != key:
            modifiers.add("shift")
        action = item.find("connections/action")
        items[item.get("title")] = (key, modifiers, item.get("tag"), action.get("selector") if action is not None else None)
        if key:
            shortcut = (key.lower(), frozenset(modifiers))
            if shortcut in found:
                raise SystemExit(f"FAIL menu: {item.get('title')!r} and {found[shortcut]!r} share {sorted(modifiers)} {key!r}")
            found[shortcut] = item.get("title")
    return items
items = menu_shortcuts(root / "GraphSketcher/App/English.lproj/MainMenu.xib")
expected = {
    "Find\u2026": ("f", {"command"}, "1", "performGraphFindAction:"),
    "Find Next": ("g", {"command"}, "2", "performGraphFindAction:"),
    "Find Previous": ("G", {"command", "shift"}, "3", "performGraphFindAction:"),
    "Use Selection for Find": ("e", {"command"}, "7", "performGraphFindAction:"),
    "Jump to Selection": ("j", {"command"}, None, "jumpToSelection:"),
    "Group": ("g", {"command", "option"}, None, "groupUngroup:"),
    "Show Grid": ("'", {"command"}, None, "displayGrid:"),
    "Snap to Grid": ("'", {"command", "shift"}, None, "snapToGrid:"),
}
for title, want in expected.items():
    if items.get(title) != want:
        raise SystemExit(f"FAIL menu: {title!r} is {items.get(title)}, expected {want}")
print("PASS menu: Edit > Find items, tags and shortcuts; Group, Show Grid and Snap to Grid moved; no shortcut used twice")
contents = output / "FindChecks.app/Contents"
(contents / "MacOS").mkdir(parents=True)
shutil.copytree(products / "Graphink.app/Contents/Resources", contents / "Resources")
info = plistlib.loads((products / "Graphink.app/Contents/Info.plist").read_bytes())
info.update(CFBundleExecutable="checks", CFBundleIdentifier="com.graphink.findchecks." + uuid.uuid4().hex, OFControllerClass="AppController", NSQuitAlwaysKeepsWindows=False)
for key in ("NSMainNibFile", "CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"):
    info.pop(key, None)
(contents / "Info.plist").write_bytes(plistlib.dumps(info))
(contents / "Frameworks").symlink_to(products)
source = root / "Checks/FindChecks.m"
command = ["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-fblocks", "-DOMNI_BUILDING_FOR_MAC=1", "-include", str(root / "GraphSketcher/App/GraphSketcher_Prefix.h"), "-I", str(root / "GraphSketcher/App"), "-F", str(products), "-Wl,-rpath," + str(products), "-lxml2"]
for framework in ("Cocoa", "SystemConfiguration", "Carbon", "CoreText", "QuartzCore", "OmniAppKit", "OmniBase", "OmniFoundation", "OmniInspector", "OmniUnzip", "OmniQuartz", "LinkBack", "GraphSketcherModel"):
    command += ["-framework", framework]
command += [str(source), *map(str, objects), "-o", str(contents / "MacOS/checks")]
(output / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
receipt = {"bundle_id": info["CFBundleIdentifier"], "source_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(), "inputs": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source, *objects]}}
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
compiled = subprocess.run(command, capture_output=True)
(output / "compile.log").write_bytes(compiled.stdout + compiled.stderr)
if compiled.returncode:
    raise SystemExit("Compilation failed; inspect " + str(output / "compile.log"))
def snapshot():
    result = {}
    for domain in ("com.diegomarino.Graphink", "com.diegomarino.Graphink.MacAppStore"):
        read = subprocess.run(["defaults", "export", domain, "-"], capture_output=True)
        result[domain] = [read.returncode, hashlib.sha256(read.stdout).hexdigest()]
        preference_files = [Path.home() / "Library/Preferences" / (domain + ".plist"), Path.home() / "Library/Containers" / domain / "Data/Library/Preferences" / (domain + ".plist")]
        preference_files += list((Path.home() / "Library/Preferences/ByHost").glob(domain + ".*.plist"))
        result[domain + ":files"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None for path in preference_files}
    return result
receipt["executable_sha256"] = hashlib.sha256((contents / "MacOS/checks").read_bytes()).hexdigest()
receipt["frameworks"] = {path.stem: hashlib.sha256((path / path.stem).read_bytes()).hexdigest() for path in products.glob("*.framework")}
before = snapshot()
run = subprocess.run([str(contents / "MacOS/checks"), "-ApplePersistenceIgnoreState", "YES"], capture_output=True)
log = run.stdout + run.stderr
(output / "checks.log").write_bytes(log)
receipt["returncode"] = run.returncode
print(log.decode(errors="replace"))
required = (b"PASS find checks; offscreen only", b"PASS find pasteboard restored", b"PASS undo neutrality", b"PASS find indicator 50%:", b"PASS find indicator 400%:", b"PASS find indicator 50% Chalkboard:", b"PASS find indicator 400% Chalkboard:")
failed = run.returncode or not all(marker in log for marker in required) or any(marker in log for marker in (b"ASSERT failed", b"PRECONDITION failed", b"Assertion Failed:", b"Exception raised:", b"FAIL ", b"Unable to simultaneously satisfy constraints"))
after = snapshot()
receipt.update(preferences_before=before, preferences_after=after)
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
if failed or before != after:
    raise SystemExit("FAIL find checks; inspect " + str(output))
print("PASS real application preference domains unchanged")
