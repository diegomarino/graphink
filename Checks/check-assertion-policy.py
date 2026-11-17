#!/usr/bin/env python3
"""Link exact production app objects into an offscreen assertion policy fixture.

Checks AppController's handling of NSAssert failures on the main thread: system framework
assertions raise NSInternalInconsistencyException inside accessibility requests (AppKit's entry
points catch it), and are logged where a raise would reach OFController and crash (event dispatch,
run-loop callouts, menu key equivalents). Separate processes prove that raw raises on those paths do crash, and that
Graphink, Omni and our own assertions still crash.
Run with host AppKit access. Never shows a window or runs application startup handlers.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__, epilog="Example: python3 Checks/check-assertion-policy.py --products /tmp/own/Debug/Products/Debug --objects /tmp/own/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/Graphink.LinkFileList --output /tmp/assertion-policy-new")
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
contents = output / "AssertionPolicyChecks.app/Contents"
(contents / "MacOS").mkdir(parents=True)
shutil.copytree(products / "Graphink.app/Contents/Resources", contents / "Resources")
info = plistlib.loads((products / "Graphink.app/Contents/Info.plist").read_bytes())
info.update(CFBundleExecutable="checks", CFBundleIdentifier="com.graphink.assertionpolicychecks." + uuid.uuid4().hex, OFControllerClass="AppController", NSQuitAlwaysKeepsWindows=False)
for key in ("NSMainNibFile", "CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations", "CFBundleURLTypes", "NSServices"):
    info.pop(key, None)
(contents / "Info.plist").write_bytes(plistlib.dumps(info))
(contents / "Frameworks").symlink_to(products)
source = root / "Checks/AssertionPolicyChecks.m"
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
CRASH_EXIT = 77
before = snapshot()
checks = [str(contents / "MacOS/checks"), str(output)]
run = subprocess.run([*checks, "-ApplePersistenceIgnoreState", "YES"], capture_output=True)
log = run.stdout + run.stderr
(output / "checks.log").write_bytes(log)
# Raw raises where OFController is the catcher (what option C would do on those paths), then
# assertions that are ours. Each must reach OFController and crash; OFCrashImmediately exits with CRASH_EXIT.
crash_modes = {
    "event-raw-raise": b"Exception raised:", "run-raw-raise": b"Exception raised:",
    "ax-graphink-object": b"Assertion Failed:", "ax-our-caller": b"Assertion Failed:", "ax-graphink-function": b"Assertion Failed:",
    "event-omni-object": b"Assertion Failed:",
}
crashes = {}
for mode, report in crash_modes.items():
    crash = subprocess.run([*checks, "--crash", mode, "-ApplePersistenceIgnoreState", "YES"], capture_output=True, env=dict(os.environ, OFCrashShouldExitWithCode=str(CRASH_EXIT)))
    crash_log = crash.stdout + crash.stderr
    (output / f"crash-{mode}.log").write_bytes(crash_log)
    crashes[mode] = crash.returncode == CRASH_EXIT and b"Crashing with report" in crash_log and report in crash_log and b"Raising system framework assertion" not in crash_log and b"Ignoring system framework assertion" not in crash_log and b"CRASH MODE DID NOT CRASH" not in crash_log
after = snapshot()
receipt.update(returncode=run.returncode, crashes=crashes, preferences_before=before, preferences_after=after)
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(log.decode(errors="replace"))
required = (b"PASS accessibility requests", b"PASS event dispatch and run-loop callouts", b"PASS assertion policy checks; offscreen only")
failed = run.returncode or not all(marker in log for marker in required) or any(marker in log for marker in (b"Crashing with report", b"Assertion Failed:", b"FAIL ", b"ASSERT failed", b"PRECONDITION failed"))
# 6 request kinds x (method, function) raise; nested loop, 2 key equivalents and 2 run-loop probes are logged; one _simulateClosed ignore.
failed = failed or log.count(b"Raising system framework assertion") != 12 or log.count(b"Ignoring system framework assertion") != 5 or log.count(b"Ignoring AppKit assertion in -[NSMenu _simulateClosed]") != 1
for mode, crashed in crashes.items():
    print(("PASS" if crashed else "FAIL") + f" crash mode {mode} still crashes through OFController")
if failed or not all(crashes.values()) or before != after:
    raise SystemExit("FAIL assertion policy checks; inspect " + str(output))
print("PASS real application preference domains unchanged")
