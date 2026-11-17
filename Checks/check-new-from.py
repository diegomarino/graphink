#!/usr/bin/env python3
"""File ▸ New From checks: bundled New From resources and windowless production-source checks.

Compiles the production App sources (all but main.m) with Checks/NewFromChecks.m into a
throwaway bundle with its own identifier and preference domain. Never launches Graphink and
fails if the real app preference domains change.
"""
import argparse
import atexit
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--products", required=True, type=Path, help="Debug products built from this worktree (contains Graphink.app)")
parser.add_argument("--output", required=True, type=Path, help="New evidence directory; existing paths are refused")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
products, output = args.products.resolve(), args.output.resolve()
if output.exists():
    parser.error("--output exists; choose a new directory")
app = products / "Graphink.app"
if not (app / "Contents/Resources/NewFrom").is_dir():
    parser.error("--products must contain a Graphink.app built with Resources/NewFrom")
output.mkdir(parents=True)
assert __debug__, "Assertions must be enabled; do not use Python -O"

sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
source_dir = root / "GraphSketcher/App/Resources/NewFrom"
bundled_dir = app / "Contents/Resources/NewFrom"
receipt = {"products": str(products), "output": str(output), "sourceHEAD": subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True).stdout.strip(), "passed": False}

# 1. Resources: manifest hashes, delivered sources, built bundle bytes, OPC profile, 35 historical samples.
manifest = plistlib.loads((source_dir / "NewFrom.plist").read_bytes())
assert manifest["FormatVersion"] == 1
items = [manifest["InitialExample"]] + [i for g in manifest["Groups"] for i in g["Items"]]
delivered = {"Initial/welcome-to-graphink.graphink": root / "Examples/InitialFTUX/welcome-to-graphink.graphink"}
# Every example catalog item is bundled as a byte copy of its Source (Examples/Tools/sync-new-from.py).
catalog = plistlib.loads((root / "Examples/NewFrom-manifest.plist").read_bytes())
catalog_items = {i["File"]: i for g in catalog["Groups"] for i in g["Items"]}
for rel, entry in catalog_items.items():
    delivered[rel] = root / "Examples" / entry["Source"]
for item in items:
    rel = item["File"]
    assert not rel.startswith("/") and ".." not in Path(rel).parts and rel.endswith(".graphink"), rel
    assert sha(source_dir / rel) == item["SHA256"], f"{rel}: source differs from manifest"
    assert sha(bundled_dir / rel) == item["SHA256"], f"{rel}: built bundle differs from manifest"
    assert rel in delivered, f"{rel}: not a delivered document"
    assert delivered[rel].read_bytes() == (source_dir / rel).read_bytes() == (bundled_dir / rel).read_bytes(), f"{rel}: not a byte copy of {delivered[rel]}"
    if rel in catalog_items:
        assert catalog_items[rel]["SHA256"] == item["SHA256"] and catalog_items[rel]["Title"] == item["Title"], f"{rel}: differs from NewFrom-manifest.plist"
    subprocess.run([sys.executable, root / "docs/format/check-opc.py", source_dir / rel], check=True, capture_output=True)
assert set(delivered) == {i["File"] for i in items}, "Every delivered document is listed, and nothing else"
assert {p.relative_to(source_dir).as_posix() for p in source_dir.rglob("*.graphink")} == set(delivered), "No unlisted bundled documents"
assert {p.relative_to(bundled_dir).as_posix() for p in bundled_dir.rglob("*.graphink")} == set(delivered), "No unlisted documents in the built bundle"
subprocess.run([sys.executable, root / "Examples/Tools/sync-new-from.py"], check=True, capture_output=True)
assert sha(bundled_dir / "NewFrom.plist") == sha(source_dir / "NewFrom.plist")
assert not list((app / "Contents/Resources").rglob("Getting Started.ograph")), "Historical Getting Started is no longer bundled (D2)"
notes = (app / "Contents/Resources/MessageOfTheDay.html").read_bytes()
generated = output / "MessageOfTheDay-expected.html"
subprocess.run([sys.executable, root / "scripts/release/notes.py", "html", "--output", generated], check=True, capture_output=True)
assert notes == generated.read_bytes(), "Bundled release notes are the build-time notes.py output for this checkout's published tags"
assert b"<title>Graphink Release Notes</title>" in notes and b"GraphSketcher" not in notes.split(b"-->")[-1], "Release notes window is titled Graphink"
assert b"DRAFT" not in notes, "Unpublished (draft) notes are never bundled"
assert notes != (root / "GraphSketcher/App/MessageOfTheDay.html").read_bytes(), "The 2014 GraphSketcher notes stay in the repository only"
assert re.search(r'<menuItem title="Release Notes"[^>]*>\s*<connections>\s*<action selector="showMessageOfTheDay:"', (root / "GraphSketcher/App/English.lproj/MainMenu.xib").read_text()), "Help > Release Notes shows them on demand"
report = (root / "Checks/historical-samples.sha256").read_text()
historical = {p: h for h, p in re.findall(r"^([a-f0-9]{64})  (GraphSketcher/.+\.ograph)$", report, re.M)}
assert len(historical) == 35 and all(sha(root / p) == h for p, h in historical.items()), "35 historical samples unchanged"
receipt["resources"] = {i["File"]: i["SHA256"] for i in items}
print(f"PASS resources items={len(items)} historical=35")

# 2. Windowless production-source checks in a throwaway bundle and preference domain.
test_domain = "com.graphsketcher.NewFromChecks." + uuid.uuid4().hex
real_domains = {"com.diegomarino.Graphink", "com.diegomarino.Graphink.MacAppStore", plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"]}
def preference_snapshot():
    result = {}
    for domain in sorted(real_domains):
        exported = subprocess.run(["defaults", "export", domain, "-"], capture_output=True)
        result[domain] = {"export_status": exported.returncode, "sha256": hashlib.sha256(exported.stdout).hexdigest()}
        files = [Path.home() / "Library/Preferences" / (domain + ".plist"), Path.home() / "Library/Containers" / domain / "Data/Library/Preferences" / (domain + ".plist")]
        result[domain + ":files"] = {str(p): sha(p) if p.exists() else None for p in files}
    return result
before = preference_snapshot()
originals_before = {str(p): sha(p) for p in sorted(source_dir.rglob("*.graphink")) + sorted(bundled_dir.rglob("*.graphink"))}
def finish():
    subprocess.run(["defaults", "delete", test_domain], capture_output=True)
    for leftover in [Path.home() / "Library/Preferences" / (test_domain + ".plist")] + list((Path.home() / "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments").glob(test_domain.lower() + "*")):
        leftover.unlink(missing_ok=True)
    after = preference_snapshot()
    (output / "preferences.json").write_text(json.dumps({"before": before, "after": after}, indent=2) + "\n")
    if before != after:
        raise RuntimeError("Real app preference domains changed during checks; inspect evidence")
atexit.register(finish)

contents = output / "NewFromChecks.app/Contents"
(contents / "MacOS").mkdir(parents=True)
(contents / "Resources").mkdir()
subprocess.run(["ditto", bundled_dir, contents / "Resources/NewFrom"], check=True)
subprocess.run(["ditto", app / "Contents/Resources/MessageOfTheDay.html", contents / "Resources/MessageOfTheDay.html"], check=True)
info = plistlib.loads((root / "GraphSketcher/App/Info.plist").read_bytes())
info.update(CFBundleIdentifier=test_domain, CFBundleExecutable="checks", CFBundleName="NewFromChecks", CFBundleVersion="11.0", CFBundleShortVersionString="1.0", NSHumanReadableCopyright="Copyright 2026 Graphink contributors", LSMinimumSystemVersion="12.0")
# Fixtures never declare UTIs, URL schemes or services: running one registers it with Launch
# Services (Checks/check-fixture-bundles.py). NSDocumentController maps the graph types to
# GraphDocument only through CFBundleDocumentTypes, so those stay, ranked None so Launch Services
# never offers the fixture as a handler; the bundle is unregistered after the run.
for key in ("NSMainNibFile", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations", "CFBundleURLTypes", "NSServices"):
    info.pop(key, None)
for document_type in info["CFBundleDocumentTypes"]:
    document_type["LSHandlerRank"] = "None"
(contents / "Info.plist").write_bytes(plistlib.dumps(info))
(output / "test-domain.txt").write_text(test_domain + "\n")
app_sources = sorted(p for p in (root / "GraphSketcher/App").glob("*.m") if p.name != "main.m") + sorted((root / "GraphSketcher/App/Inspectors").glob("*.m"))
command = ["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-fblocks", "-DOMNI_BUILDING_FOR_MAC=1", "-DDEBUG=1",
           "-Wno-deprecated-declarations", "-Wno-nullability-completeness", "-include", str(root / "GraphSketcher/App/GraphSketcher_Prefix.h"),
           "-I", str(root / "GraphSketcher/App"), "-I", str(root / "GraphSketcher/App/Inspectors"), "-I", str(root / "GraphSketcher"), "-I", str(root / "GraphSketcher/Model"), f"-F{products}"]
for fw in ["Cocoa", "Carbon", "QuartzCore", "SystemConfiguration", "UniformTypeIdentifiers", "GraphSketcherModel", "LinkBack", "OmniAppKit", "OmniBase", "OmniFoundation", "OmniInspector", "OmniQuartz", "OmniUnzip", "WebKit"]:
    command += ["-framework", fw]
command += [f"-Wl,-rpath,{products}"] + [str(p) for p in app_sources] + [str(root / "Checks/NewFromChecks.m"), "-o", str(contents / "MacOS/checks")]
receipt["compileCommand"] = command
compiled = subprocess.run(command, capture_output=True, text=True)
(output / "compile.log").write_text(compiled.stdout + compiled.stderr)
assert compiled.returncode == 0, "Compile failed; inspect compile.log"
scratch = output / "scratch"
scratch.mkdir()
try:
    result = subprocess.run([str(contents / "MacOS/checks"), str(contents / "Resources/NewFrom"), str(scratch)], capture_output=True, text=True, timeout=120)
finally:
    # Once it has run, the fixture stops declaring document types and is unregistered: Launch Services
    # can register a bundle on disk again on its own (GitHub's macOS runners do), and then it must
    # claim nothing (Checks/check-fixture-bundles.py).
    fixture_plist = plistlib.loads((contents / "Info.plist").read_bytes())
    for key in ("CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"):
        fixture_plist.pop(key, None)
    (contents / "Info.plist").write_bytes(plistlib.dumps(fixture_plist))
    subprocess.run(["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-u", str(contents.parent)], check=True)
(output / "checks.log").write_text(result.stdout + result.stderr)
print(result.stdout, end="")
assert result.returncode == 0 and "COMPLETE failures=0" in result.stdout, "Checks failed; inspect checks.log"
for marker in ("PASS message-of-the-day", "PASS release notes follow Light/Dark", "PASS policy", "PASS catalog-and-menu", f"PASS ownership items={len(items)}", "PASS installed-menu", "PASS first-launch"):
    assert marker in result.stdout, "Missing " + marker
assert not re.search(r"FATAL ASSERTION|ASSERT failed|Assertion Failed", result.stdout + result.stderr), "Assertions found; inspect checks.log"

originals_after = {str(p): sha(p) for p in sorted(source_dir.rglob("*.graphink")) + sorted(bundled_dir.rglob("*.graphink"))}
assert originals_before == originals_after, "Bundled originals changed"
assert all(sha(root / p) == h for p, h in historical.items()), "Historical samples changed"
receipt["originals"] = originals_after
receipt["passed"] = True
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print("PASS New From checks; evidence: " + str(output))
