#!/usr/bin/env python3
"""Link exact production app objects into an offscreen snap and hit distance fixture.

At 25%, 100%, 400% and Fit (and after direct magnification changes) the selection, snap-to-object
and snap-to-grid distances must be 6 screen points: probes on a line, an axis, an axis end and a
margin guide, and Draw clicks 5 and 7 screen points from a level or a tick line. With
--baseline-products/--baseline-objects the same fixture is also linked against another build
(for example the one before this change) and its 100% transcript must be byte-identical.
Run with host AppKit access. Never runs application startup handlers or a launch loop.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__, epilog="Example: python3 Checks/check-snap-distance.py --products /tmp/own/Debug/Products/Debug --objects /tmp/own/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/Graphink.LinkFileList --output /tmp/snap-distance-new")
parser.add_argument("--products", required=True, type=Path, help="Exact current-source Debug products")
parser.add_argument("--objects", required=True, type=Path, help="Matching Graphink.LinkFileList from that build")
parser.add_argument("--output", required=True, type=Path, help="Fresh owned evidence directory; existing paths refused")
parser.add_argument("--baseline-products", type=Path, help="Optional Debug products of a build to compare 100%% results with")
parser.add_argument("--baseline-objects", type=Path, help="Matching Graphink.LinkFileList of that build")
args = parser.parse_args()
if (args.baseline_products is None) != (args.baseline_objects is None):
    parser.error("Pass both --baseline-products and --baseline-objects, or neither")
root = Path(__file__).resolve().parents[1]
output = args.output.resolve()
if output.exists():
    parser.error("Output exists; choose a fresh evidence directory")
source = root / "Checks/SnapDistanceChecks.m"

def objects_of(products, link_file_list):
    if not link_file_list.is_file() or not (products / "Graphink.app/Contents/Resources").is_dir():
        parser.error("Missing objects/products; first build this exact candidate")
    objects = [Path(line) for line in link_file_list.read_text().splitlines() if Path(line).name != "main.o"]
    if not objects or not all(path.is_file() for path in objects):
        parser.error("LinkFileList contains missing objects; use matching build products")
    return objects

def snapshot():
    result = {}
    for domain in ("com.diegomarino.Graphink", "com.diegomarino.Graphink.MacAppStore"):
        read = subprocess.run(["defaults", "export", domain, "-"], capture_output=True)
        result[domain] = [read.returncode, hashlib.sha256(read.stdout).hexdigest()]
        preference_files = [Path.home() / "Library/Preferences" / (domain + ".plist"), Path.home() / "Library/Containers" / domain / "Data/Library/Preferences" / (domain + ".plist")]
        preference_files += list((Path.home() / "Library/Preferences/ByHost").glob(domain + ".*.plist"))
        result[domain + ":files"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None for path in preference_files}
    return result

def build_and_run(products, link_file_list, directory):
    products = products.resolve()
    objects = objects_of(products, link_file_list)
    contents = directory / "SnapDistanceChecks.app/Contents"
    (contents / "MacOS").mkdir(parents=True)
    shutil.copytree(products / "Graphink.app/Contents/Resources", contents / "Resources")
    info = plistlib.loads((products / "Graphink.app/Contents/Info.plist").read_bytes())
    info.update(CFBundleExecutable="checks", CFBundleIdentifier="com.graphink.snapdistancechecks." + uuid.uuid4().hex, OFControllerClass="AppController", NSQuitAlwaysKeepsWindows=False)
    for key in ("NSMainNibFile", "CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"):
        info.pop(key, None)
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    (contents / "Frameworks").symlink_to(products)
    command = ["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-fblocks", "-DOMNI_BUILDING_FOR_MAC=1", "-include", str(root / "GraphSketcher/App/GraphSketcher_Prefix.h"), "-I", str(root / "GraphSketcher/App"), "-F", str(products), "-Wl,-rpath," + str(products), "-lxml2"]
    for framework in ("Cocoa", "SystemConfiguration", "Carbon", "CoreText", "QuartzCore", "OmniAppKit", "OmniBase", "OmniFoundation", "OmniInspector", "OmniUnzip", "OmniQuartz", "LinkBack", "GraphSketcherModel"):
        command += ["-framework", framework]
    command += [str(source), *map(str, objects), "-o", str(contents / "MacOS/checks")]
    (directory / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
    receipt = {"bundle_id": info["CFBundleIdentifier"], "source_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(), "inputs": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source, *objects]}}
    compiled = subprocess.run(command, capture_output=True)
    (directory / "compile.log").write_bytes(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        raise SystemExit("Compilation failed; inspect " + str(directory / "compile.log"))
    receipt["executable_sha256"] = hashlib.sha256((contents / "MacOS/checks").read_bytes()).hexdigest()
    receipt["frameworks"] = {path.stem: hashlib.sha256((path / path.stem).read_bytes()).hexdigest() for path in products.glob("*.framework")}
    before = snapshot()
    run = subprocess.run([str(contents / "MacOS/checks"), str(directory), "-ApplePersistenceIgnoreState", "YES"], capture_output=True)
    after = snapshot()
    log = run.stdout + run.stderr
    (directory / "checks.log").write_bytes(log)
    receipt.update(returncode=run.returncode, preferences_before=before, preferences_after=after)
    (directory / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return run.returncode, log, before == after

output.mkdir(parents=True)
returncode, log, preferences_unchanged = build_and_run(args.products, args.objects, output)
print(log.decode(errors="replace"))
required = (b"PASS 100% transcript written", b"PASS live magnification changes", b"PASS snap distance checks: 6 screen points at 25%, 100%, 400% and Fit; offscreen only")
failed = returncode or not all(marker in log for marker in required) or any(marker in log for marker in (b"ASSERT failed", b"PRECONDITION failed", b"Assertion Failed:", b"Exception raised:", b"FAIL ", b"Unable to simultaneously satisfy constraints"))
if failed or not preferences_unchanged:
    raise SystemExit("FAIL snap distance checks; inspect " + str(output))
print("PASS real application preference domains unchanged")
if args.baseline_products:
    baseline = output / "baseline"
    baseline.mkdir()
    _, baseline_log, baseline_preferences_unchanged = build_and_run(args.baseline_products, args.baseline_objects, baseline)
    # The baseline's other zooms are expected to fail before this change; only 100% is compared.
    ours, theirs = output / "transcript-100.txt", baseline / "transcript-100.txt"
    if b"PASS 100% transcript written" not in baseline_log or not theirs.is_file():
        raise SystemExit("FAIL baseline wrote no 100% transcript; inspect " + str(baseline))
    if ours.read_bytes() != theirs.read_bytes() or not baseline_preferences_unchanged:
        raise SystemExit("FAIL 100% results differ from the baseline build; compare " + str(ours) + " with " + str(theirs))
    print("PASS 100% results byte-identical to the baseline build (" + str(len(ours.read_bytes().splitlines())) + " lines, SHA-256 " + hashlib.sha256(ours.read_bytes()).hexdigest() + ")")
