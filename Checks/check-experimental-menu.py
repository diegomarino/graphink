#!/usr/bin/env python3
"""The Experimental menu is built into Debug products only.

Reads the menu's titles from the production builder in AppController.m (`#ifdef DEBUG`), then
scans the built Graphink.app. Debug: the main executable carries every title and the builder's
selector, and the menu icon is bundled. Release: no file in the bundle carries any title, the
builder's selector or the icon, and no ShowExperimentalFeaturesMenu default exists. The two
Debug-only canvas keyboard hacks in RSGraphView.m follow the same rule: the Debug executable
implements deleteWordBackward: and moveToBeginningOfDocumentAndModifySelection:, the Release
executable names neither (nothing else in Graphink's own code uses them). Reads files only; never
launches Graphink.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--products", required=True, type=Path, help="Debug or Release products directory (contains Graphink.app)")
parser.add_argument("--configuration", required=True, choices=("Debug", "Release"))
parser.add_argument("--output", required=True, type=Path, help="New evidence directory; existing paths are refused")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
app, output = (args.products / "Graphink.app").resolve(), args.output.resolve()
if output.exists():
    parser.error("--output exists; choose a new directory")
if not (app / "Contents/Info.plist").is_file():
    parser.error("--products must contain Graphink.app")
assert __debug__, "Assertions must be enabled; do not use Python -O"
output.mkdir(parents=True)

controller = (root / "GraphSketcher/App/AppController.m").read_text()
builder = controller[controller.index("#ifdef DEBUG\n- (void)_installExperimentalMenu;"):]
builder = builder[:builder.index("\n#endif\n")]
titles = sorted(set(re.findall(r'NSLocalizedString\(@"([^"]+)", @"Experimental menu item"\)', builder)))
assert len(titles) == 13, titles  # the menu title and its 12 commands
# Null-delimited, as the compiler stores C and CFString literals and the method name.
needles = {t: b"\0" + t.encode() + b"\0" for t in titles + ["_installExperimentalMenu"]}
view = (root / "GraphSketcher/App/RSGraphView.m").read_text()
hack_selectors = ["deleteWordBackward:", "moveToBeginningOfDocumentAndModifySelection:"]
assert all(view.count(f"- (void){s}(id)sender") == 1 for s in hack_selectors), "RSGraphView keyboard hacks moved"
hack_needles = {s: b"\0" + s.encode() + b"\0" for s in hack_selectors}

info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert "ShowExperimentalFeaturesMenu" not in json.dumps(info, default=str), "Stale ShowExperimentalFeaturesMenu key"
executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
icon = app / "Contents/Resources/experimental.png"
report = {"configuration": args.configuration, "app": str(app), "titles": titles}

if args.configuration == "Debug":
    data = executable.read_bytes()
    missing = [name for name, needle in needles.items() if needle not in data]
    assert not missing, f"Debug executable lacks {missing}"
    assert icon.is_file(), "Debug bundle lacks the Experimental menu icon"
    missing = [name for name, needle in hack_needles.items() if needle not in data]
    assert not missing, f"Debug executable lacks the keyboard hacks {missing}"
    report["executable"] = "carries every title, _installExperimentalMenu and both keyboard hacks"
else:
    hits = {}
    for path in sorted(p for p in app.rglob("*") if p.is_file() and not p.is_symlink()):
        data = path.read_bytes()
        found = [name for name, needle in needles.items() if needle in data]
        if found:
            hits[str(path.relative_to(app))] = found
    assert not hits, f"Release bundle carries Experimental menu traces: {hits}"
    assert not list(app.rglob("experimental.png")), "Release bundle carries the Experimental menu icon"
    # Only the main executable: AppKit and bundled frameworks may legitimately name these selectors.
    data = executable.read_bytes()
    found = [name for name, needle in hack_needles.items() if needle in data]
    assert not found, f"Release executable carries the keyboard hacks {found}"
    report["scanned"] = "every file in the bundle: no title, no _installExperimentalMenu, no experimental.png; the executable has neither keyboard hack"

(output / "experimental-menu.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: Experimental menu and keyboard hacks {'present in' if args.configuration == 'Debug' else 'absent from'} the {args.configuration} product ({len(titles)} titles, {len(hack_selectors)} selectors checked)")
