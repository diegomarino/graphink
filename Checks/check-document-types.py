#!/usr/bin/env python3
"""Document-type checks: .graphink is Graphink's exported UTI, .ograph the imported GraphSketcher UTI.

Checks the built Graphink.app's declarations, then compiles the production App sources (all but
main.m) with Checks/DocumentTypeChecks.m into a throwaway bundle that keeps the real document
types. It opens each extension, saves in place and Save As. Never launches Graphink and fails if
the real app preference domains change.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import time
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--products", required=True, type=Path, help="Debug or Release products built from this worktree (contains Graphink.app)")
parser.add_argument("--output", required=True, type=Path, help="New evidence directory; existing paths are refused")
parser.add_argument("--declarations-only", action="store_true", help="Check the built Info.plist only (e.g. Release products)")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
products, output = args.products.resolve(), args.output.resolve()
if output.exists():
    parser.error("--output exists; choose a new directory")
app = products / "Graphink.app"
if not (app / "Contents/Info.plist").is_file():
    parser.error("--products must contain Graphink.app")
output.mkdir(parents=True)
assert __debug__, "Assertions must be enabled; do not use Python -O"
NEW, LEGACY = "com.diegomarino.graphink.document", "com.graphsketcher.graphdocument"

# 1. Built declarations, as Launch Services will read them.
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
docs = {d["LSItemContentTypes"][0]: d for d in info["CFBundleDocumentTypes"]}
assert list(docs) == [NEW, LEGACY], list(docs)
assert docs[NEW]["CFBundleTypeRole"] == "Editor" and docs[NEW]["LSHandlerRank"] == "Owner" and docs[NEW]["CFBundleTypeExtensions"] == ["graphink"]
assert docs[LEGACY]["CFBundleTypeRole"] == "Editor" and docs[LEGACY]["LSHandlerRank"] == "Alternate" and docs[LEGACY]["CFBundleTypeExtensions"] == ["ograph"]
exported, = info["UTExportedTypeDeclarations"]
imported, = info["UTImportedTypeDeclarations"]
assert exported["UTTypeIdentifier"] == NEW and exported["UTTypeDescription"] == "Graphink Document"
assert exported["UTTypeConformsTo"] == ["public.data", "public.composite-content"]
assert exported["UTTypeTagSpecification"] == {"public.filename-extension": ["graphink"]}
assert imported == {"UTTypeConformsTo": ["public.data"], "UTTypeDescription": "GraphSketcher Document", "UTTypeIdentifier": LEGACY,
                    "UTTypeTagSpecification": {"public.filename-extension": ["ograph"]}}, imported
(output / "declarations.json").write_text(json.dumps({k: info[k] for k in ("CFBundleIdentifier", "CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations")}, indent=2) + "\n")
print(f"PASS built declarations {info['CFBundleIdentifier']}: {NEW} exported/Owner (.graphink), {LEGACY} imported/Alternate (.ograph)")
if args.declarations_only:
    raise SystemExit(0)

# 2. Windowless production-source checks in a throwaway bundle and preference domain.
real_domains = ["com.diegomarino.Graphink", "com.diegomarino.Graphink.MacAppStore"]
def preference_snapshot():
    result = {}
    for domain in real_domains:
        exported_defaults = subprocess.run(["defaults", "export", domain, "-"], capture_output=True)
        files = [Path.home() / "Library/Preferences" / (domain + ".plist"), Path.home() / "Library/Containers" / domain / "Data/Library/Preferences" / (domain + ".plist")]
        result[domain] = {"export_status": exported_defaults.returncode, "sha256": hashlib.sha256(exported_defaults.stdout).hexdigest(),
                          "files": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None for p in files}}
    return result
before = preference_snapshot()
sample = root / "GraphSketcher/App/Documentation/UserDocs/Very small graph.ograph"
sample_sha = hashlib.sha256(sample.read_bytes()).hexdigest()
contents = output / "DocumentTypeChecks.app/Contents"
(contents / "MacOS").mkdir(parents=True)
(contents / "Resources").mkdir()
fixture = plistlib.loads((root / "GraphSketcher/App/Info.plist").read_bytes())
fixture.update(CFBundleIdentifier="com.graphink.documenttypechecks." + uuid.uuid4().hex, CFBundleExecutable="checks", CFBundleName="DocumentTypeChecks",
               CFBundleVersion="11.0", CFBundleShortVersionString="1.0", NSHumanReadableCopyright="Copyright 2026 Graphink contributors", LSMinimumSystemVersion="12.0")
fixture.pop("NSMainNibFile", None)
# The fixture keeps the app's document types and UTIs because they are what it checks. Running it
# registers it with Launch Services: rank None so it is never offered as a handler, no URL schemes
# or services, and unregistered after the run (Checks/check-fixture-bundles.py).
for key in ("CFBundleURLTypes", "NSServices"):
    fixture.pop(key, None)
for document_type in fixture["CFBundleDocumentTypes"]:
    document_type["LSHandlerRank"] = "None"
(contents / "Info.plist").write_bytes(plistlib.dumps(fixture))
app_sources = sorted(p for p in (root / "GraphSketcher/App").glob("*.m") if p.name != "main.m") + sorted((root / "GraphSketcher/App/Inspectors").glob("*.m"))
command = ["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-fblocks", "-DOMNI_BUILDING_FOR_MAC=1", "-DDEBUG=1",
           "-Wno-deprecated-declarations", "-Wno-nullability-completeness", "-include", str(root / "GraphSketcher/App/GraphSketcher_Prefix.h"),
           "-I", str(root / "GraphSketcher/App"), "-I", str(root / "GraphSketcher/App/Inspectors"), "-I", str(root / "GraphSketcher"), "-I", str(root / "GraphSketcher/Model"), f"-F{products}"]
for fw in ["Cocoa", "Carbon", "QuartzCore", "SystemConfiguration", "UniformTypeIdentifiers", "GraphSketcherModel", "LinkBack", "OmniAppKit", "OmniBase", "OmniFoundation", "OmniInspector", "OmniQuartz", "OmniUnzip"]:
    command += ["-framework", fw]
command += [f"-Wl,-rpath,{products}"] + [str(p) for p in app_sources] + [str(root / "Checks/DocumentTypeChecks.m"), "-o", str(contents / "MacOS/checks")]
compiled = subprocess.run(command, capture_output=True, text=True)
(output / "compile.log").write_text(compiled.stdout + compiled.stderr)
assert compiled.returncode == 0, "Compile failed; inspect " + str(output / "compile.log")
scratch = output / "scratch"
scratch.mkdir()
try:
    result = subprocess.run([str(contents / "MacOS/checks"), str(sample), str(scratch)], capture_output=True, text=True, timeout=120)
finally:
    # Launch Services can register a fixture that just ran again after a first -u (seen on GitHub's
    # macOS runners), so unregister until its dump no longer lists the bundle.
    lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    for _ in range(10):
        subprocess.run([lsregister, "-u", str(contents.parent)], check=True)
        dump = subprocess.run([lsregister, "-dump"], capture_output=True, text=True, check=True).stdout
        if str(contents.parent.resolve()) not in {line.split(":", 1)[1].strip().rsplit(" (0x", 1)[0] for line in dump.splitlines() if line.startswith("path:")}:
            break
        time.sleep(1)
(output / "checks.log").write_text(result.stdout + result.stderr)
print(result.stdout, end="")
after = preference_snapshot()
receipt = {"sourceHEAD": subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True).stdout.strip(), "products": str(products),
           "returncode": result.returncode, "preferences_before": before, "preferences_after": after, "compileCommand": command}
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
assert result.returncode == 0 and "COMPLETE failures=0" in result.stdout and "PASS document types" in result.stdout, "Checks failed; inspect " + str(output / "checks.log")
assert not re.search(r"FATAL ASSERTION|ASSERT failed|Assertion Failed|Exception raised", result.stdout + result.stderr), "Assertions found; inspect checks.log"
assert hashlib.sha256(sample.read_bytes()).hexdigest() == sample_sha, "Original sample changed"
assert before == after, "Real app preference domains changed; inspect receipt.json"
print("PASS real application preference domains unchanged; evidence: " + str(output))
