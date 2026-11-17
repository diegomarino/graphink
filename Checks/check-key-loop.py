#!/usr/bin/env python3
"""Link exact production app objects into an offscreen key view loop fixture.

Presses Tab and Shift-Tab in a nib-loaded document window for every sidebar section, with
Keyboard navigation on and off (emulated inside the fixture; the user's setting is untouched), and checks
that the loop walks the sidebar in reading order, reaches the canvas and the zoom popup, and
never traps focus. Run with host AppKit access. Never shows a window or runs a launch loop.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__, epilog="Example: python3 Checks/check-key-loop.py --products /tmp/own/Debug/Products/Debug --objects /tmp/own/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/Graphink.LinkFileList --output /tmp/key-loop-new")
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
contents = output / "KeyLoopChecks.app/Contents"
(contents / "MacOS").mkdir(parents=True)
shutil.copytree(products / "Graphink.app/Contents/Resources", contents / "Resources")
info = plistlib.loads((products / "Graphink.app/Contents/Info.plist").read_bytes())
info.update(CFBundleExecutable="checks", CFBundleIdentifier="com.graphink.keyloopchecks." + uuid.uuid4().hex, OFControllerClass="AppController", NSQuitAlwaysKeepsWindows=False)
for key in ("NSMainNibFile", "CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"):
    info.pop(key, None)
(contents / "Info.plist").write_bytes(plistlib.dumps(info))
(contents / "Frameworks").symlink_to(products)
source = root / "Checks/KeyLoopChecks.m"
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
failed = False
for mode in ("on", "off"):
    run = subprocess.run([str(contents / "MacOS/checks"), mode, "-ApplePersistenceIgnoreState", "YES"], capture_output=True)
    log = run.stdout + run.stderr
    (output / f"checks-keyboard-navigation-{mode}.log").write_bytes(log)
    receipt[f"returncode_{mode}"] = run.returncode
    print(log.decode(errors="replace"))
    required = (f"PASS key view loops with keyboard navigation {mode}".encode(), b"PASS key loop checks; offscreen only")
    failed = failed or run.returncode or not all(marker in log for marker in required) or any(marker in log for marker in (b"ASSERT failed", b"PRECONDITION failed", b"Assertion Failed:", b"Exception raised:", b"FAIL ", b"Unable to simultaneously satisfy constraints"))
after = snapshot()
receipt.update(preferences_before=before, preferences_after=after)
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
if failed or before != after:
    raise SystemExit("FAIL key loop checks; inspect " + str(output))
print("PASS real application preference domains unchanged")
