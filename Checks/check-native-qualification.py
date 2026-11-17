#!/usr/bin/env python3
"""Link exact production app objects into an offscreen fixture for native qualification.

Nib-loaded document windows (never shown) exercise:
- legacy style adoption: Arrange > Apply Style Preset on a legacy .ograph (ZIP and plain XML) and a
  phase-1 .graphink copy offers Save As first; Cancel leaves model, editor, selection, undo, dirty
  state and the original bytes unchanged; the Save panel proposes (and, for .ograph, shows) the
  .graphink extension; Save As writes OPC and keeps the editor; ordinary Save keeps the legacy format;
- autosave and recovery: the AppKit autosave entry points write no preview and never end editing,
  autosaved contents reopen as the edited document, an unsupported package is refused without
  replacing the open editor; AppKit's own timer autosaves a new untitled label within 30 s and
  reopening those contents as state restoration does brings the label back;
- the shared font and color panels with two documents and distinct selections;
- full screen: the full-screen frame is never saved as the default frame for new windows.
AppKit's key and main window are emulated (the windows stay offscreen and the process is never
activated); the shared panels are never shown. Run with host AppKit access.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import uuid

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter, epilog="Example: python3 Checks/check-native-qualification.py --products /tmp/own/Debug/Products/Debug --objects /tmp/own/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/Graphink.LinkFileList --output /tmp/native-qualification-new")
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
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()

# The fixture opens copies only. Text.ograph is a historical legacy-ZIP sample with labels.
report = (root / "Checks/historical-samples.sha256").read_text()
historical = {line.split("  ", 1)[1]: line.split("  ", 1)[0] for line in report.splitlines() if len(line) > 66 and line[64:66] == "  " and line.endswith(".ograph")}
assert len(historical) == 35, "35 historical samples listed"
sample = root / "GraphSketcher/iPad/MoreSamples/Text.ograph"
assert sha(sample) == historical["GraphSketcher/iPad/MoreSamples/Text.ograph"], "Historical sample unchanged"
inputs = output / "inputs"
inputs.mkdir(parents=True)
shutil.copyfile(sample, inputs / "Text.ograph")

contents = output / "NativeQualificationChecks.app/Contents"
(contents / "MacOS").mkdir(parents=True)
shutil.copytree(products / "Graphink.app/Contents/Resources", contents / "Resources")
info = plistlib.loads((products / "Graphink.app/Contents/Info.plist").read_bytes())
# Window restoration stays on (retest v5 Z5): the app itself never sets NSQuitAlwaysKeepsWindows;
# only this fixture turns it off, so it leaves no saved state behind.
assert "NSQuitAlwaysKeepsWindows" not in info and "NSQuitAlwaysKeepsWindows" not in info["OFRegistrations"]["NSUserDefaults"]["defaultsDictionary"], "Graphink.app must not override NSQuitAlwaysKeepsWindows"
info.update(CFBundleExecutable="checks", CFBundleIdentifier="com.graphink.nativequalificationchecks." + uuid.uuid4().hex, OFControllerClass="AppController", NSQuitAlwaysKeepsWindows=False)
# No document types or UTIs (Checks/check-fixture-bundles.py): documents are opened and saved
# with explicit types, never through Launch Services or NSDocumentController's type table.
editor_types = sorted(t for d in info["CFBundleDocumentTypes"] if d.get("CFBundleTypeRole") == "Editor" and d.get("NSDocumentClass") == "GraphDocument" for t in d["LSItemContentTypes"])
assert editor_types == ["com.diegomarino.graphink.document", "com.graphsketcher.graphdocument"], editor_types
info["NativeQualificationEditorTypes"] = editor_types
for key in ("NSMainNibFile", "CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations", "CFBundleURLTypes", "NSServices"):
    info.pop(key, None)
(contents / "Info.plist").write_bytes(plistlib.dumps(info))
(contents / "Frameworks").symlink_to(products)
source = root / "Checks/NativeQualificationChecks.m"
command = ["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-fblocks", "-DOMNI_BUILDING_FOR_MAC=1", "-Wno-deprecated-declarations", "-include", str(root / "GraphSketcher/App/GraphSketcher_Prefix.h"),
           "-I", str(root / "GraphSketcher/App"), "-I", str(root / "GraphSketcher/App/Inspectors"), "-F", str(products), "-Wl,-rpath," + str(products), "-lxml2"]
for framework in ("Cocoa", "SystemConfiguration", "Carbon", "CoreText", "QuartzCore", "OmniAppKit", "OmniBase", "OmniFoundation", "OmniInspector", "OmniUnzip", "OmniQuartz", "LinkBack", "GraphSketcherModel"):
    command += ["-framework", framework]
command += [str(source), *map(str, objects), "-o", str(contents / "MacOS/checks")]
(output / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
receipt = {"bundle_id": info["CFBundleIdentifier"], "source_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(), "inputs": {str(p): sha(p) for p in [source, sample, *objects]}}
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
        result[domain + ":files"] = {str(path): sha(path) if path.exists() else None for path in preference_files}
    # Autosave elsewhere is only ever pointed at the evidence directory, never at the user's folder.
    autosave = Path.home() / "Library/Autosave Information"
    result["autosave-information"] = sorted(p.name for p in autosave.iterdir()) if autosave.is_dir() else None
    return result

receipt["executable_sha256"] = sha(contents / "MacOS/checks")
receipt["frameworks"] = {path.stem: sha(path / path.stem) for path in products.glob("*.framework")}
scratch = output / "scratch"
scratch.mkdir()
before = snapshot()
run = subprocess.run([str(contents / "MacOS/checks"), str(inputs / "Text.ograph"), str(scratch), "-ApplePersistenceIgnoreState", "YES"], capture_output=True, timeout=300)
log = run.stdout + run.stderr
(output / "checks.log").write_bytes(log)
receipt["returncode"] = run.returncode
print(log.decode(errors="replace"))
after = snapshot()
# The fixture never gets a saved-state folder: it shows no window and keeps none on quit.
saved_state = Path.home() / "Library/Saved Application State" / (info["CFBundleIdentifier"] + ".savedState")
shutil.rmtree(saved_state, ignore_errors=True)
subprocess.run(["defaults", "delete", info["CFBundleIdentifier"]], capture_output=True)
(Path.home() / "Library/Preferences" / (info["CFBundleIdentifier"] + ".plist")).unlink(missing_ok=True)

required = [b"PASS legacy adoption", b"PASS legacy save routing", b"PASS autosave", b"PASS recovery", b"PASS crash recovery", b"PASS unsupported package", b"PASS font panel", b"PASS color panel", b"PASS full screen", b"PASS native qualification checks; offscreen only"]
failed = bool(run.returncode) or not all(marker in log for marker in required) or any(marker in log for marker in (b"ASSERT failed", b"PRECONDITION failed", b"Assertion Failed:", b"Exception raised:", b"FAIL ", b"Unable to simultaneously satisfy constraints"))
# Every package the fixture wrote must pass the independent OPC checker; legacy saves must not be OPC.
opc = sorted(scratch.glob("opc-*.graphink"))
receipt["opc_packages"] = {}
for package in opc:
    checked = subprocess.run([sys.executable, str(root / "docs/format/check-opc.py"), str(package)], capture_output=True, text=True)
    receipt["opc_packages"][package.name] = checked.returncode
    failed = failed or checked.returncode != 0
    print(("PASS" if checked.returncode == 0 else "FAIL") + " check-opc.py " + package.name)
failed = failed or not opc
assert sha(sample) == historical["GraphSketcher/iPad/MoreSamples/Text.ograph"], "Historical sample unchanged"
assert all(sha(root / p) == h for p, h in historical.items()), "35 historical samples unchanged"
receipt.update(preferences_before=before, preferences_after=after)
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
if failed or before != after:
    raise SystemExit("FAIL native qualification checks; inspect " + str(output))
print("PASS real application preference domains and Autosave Information unchanged; 35 historical samples unchanged")
