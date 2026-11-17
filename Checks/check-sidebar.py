#!/usr/bin/env python3
"""Compile production sidebar logic and run offscreen AppKit lifecycle checks."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import uuid
import atexit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--products", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path, help="New evidence directory; existing paths are refused")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
products = args.products.resolve()
output = args.output.resolve()
if output.exists():
    parser.error("--output exists; choose a new directory")
if not (products / "OmniInspector.framework").is_dir():
    parser.error("--products must contain built OmniInspector and its dependencies")
test_domain = "com.graphsketcher.SidebarChecks." + uuid.uuid4().hex
contents = output / "SidebarChecks.app/Contents"
(contents / "MacOS").mkdir(parents=True)
(contents / "Resources/English.lproj").mkdir(parents=True)
config = {"OIInspectorWidth": 280, "OIInspectors": [{"class": "RSInspectorSidebar", "identifier": "sidebar", "preferredInterfaceType": 1, "wantsHeader": False, "isCollapsible": False, "visible": True, "tabs": [{"image": "NSActionTemplate", "inspector": {"class": "CheckInspector", "identifier": name, "image": "NSActionTemplate"}} for name in ("style", "axis", "document", "data")]}]}
(contents / "Resources/Inspectors.plist").write_bytes(plistlib.dumps(config))
(contents / "Resources/English.lproj/OIInspectors.strings").write_text('\n'.join(f'"{key}" = "Check {key}";' for key in ("sidebar", "style", "axis", "document", "data", "action-checks")))
(contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "checks", "CFBundleIdentifier": test_domain, "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "NSHumanReadableCopyright": "Copyright 2026"}))
real_domains = {"com.diegomarino.Graphink", "com.diegomarino.Graphink.MacAppStore"}
app_info = products / "Graphink.app/Contents/Info.plist"
if app_info.exists():
    real_domains.add(plistlib.loads(app_info.read_bytes())["CFBundleIdentifier"])

def preference_snapshot():
    result = {}
    for domain in sorted(real_domains):
        exported = subprocess.run(["defaults", "export", domain, "-"], capture_output=True)
        result[domain] = {"export_status": exported.returncode, "sha256": hashlib.sha256(exported.stdout).hexdigest()}
        preference_files = [Path.home() / "Library/Preferences" / (domain + ".plist"), Path.home() / "Library/Containers" / domain / "Data/Library/Preferences" / (domain + ".plist")]
        preference_files += list((Path.home() / "Library/Preferences/ByHost").glob(domain + ".*.plist"))
        result[domain + ":files"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None for path in preference_files}
    return result

before = preference_snapshot()
(output / "preferences-before.json").write_text(json.dumps(before, indent=2) + "\n")
def verify_preferences():
    after = preference_snapshot()
    (output / "preferences-after.json").write_text(json.dumps(after, indent=2) + "\n")
    if before != after:
        raise RuntimeError("Real app preference domains changed during fixture; inspect evidence")
atexit.register(verify_preferences)
(output / "test-domain.txt").write_text(test_domain + "\n")
command = ["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-fblocks", "-fmodules", f"-fmodules-cache-path={output / 'ModuleCache'}", "-DOMNI_BUILDING_FOR_MAC=1", "-Wall", "-Werror", "-Wno-error=deprecated-declarations", "-Wno-error=nullability-completeness", "-include", str(root / "GraphSketcher/App/GraphSketcher_Prefix.h"), f"-F{products}", "-framework", "AppKit", "-framework", "GraphSketcherModel", "-framework", "OmniInspector", "-framework", "OmniAppKit", "-framework", "OmniFoundation", "-framework", "OmniBase", f"-Wl,-rpath,{products}"]
source = root / "GraphSketcher/App/RSInspectorSidebar.m"
if source.exists():
    command += [str(source)]
command += [str(root / "GraphSketcher/App/GraphWindowController.m"), str(root / "GraphSketcher/App/RSLabelFinder.m"), str(root / "GraphSketcher/App/ButtonRibbonCell.m"), str(root / "GraphSketcher/App/RSBoxSeparator.m")]
command += [str(root / "Checks/SidebarChecks.m"), "-o", str(contents / "MacOS/checks")]
(output / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
sources = [path for directory in (root / "GraphSketcher/App", root / "Checks") for path in directory.rglob("*") if path.suffix in (".m", ".h", ".xib", ".plist", ".py")]
(output / "source-sha256.json").write_text(json.dumps({str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}, indent=2) + "\n")
compiled = subprocess.run(command, capture_output=True)
(output / "compile.log").write_bytes(compiled.stdout + compiled.stderr)
if compiled.returncode:
    print((compiled.stdout + compiled.stderr).decode(errors="replace"))
compiled.check_returncode()
result = subprocess.run([str(contents / "MacOS/checks")], capture_output=True)
log = result.stdout + result.stderr
(output / "checks.log").write_bytes(log)
print(log.decode(errors="replace"))
assert result.returncode == 0 and b"PASS sidebar:" in log and not any(marker in log for marker in (b"ASSERT failed", b"Assertion Failed:", b"Exception raised:", b"Unable to simultaneously satisfy constraints")), "Sidebar checks failed; see checks.log"
color_command = command[:command.index(str(source))] + [f"-I{root / 'GraphSketcher/App'}"]
color_command += ["-framework", "CoreText"]
color_command += [str(root / name) for name in ("GraphSketcher/App/RSStylePresets.m", "GraphSketcher/App/RSPageGeometry.m", "GraphSketcher/App/Inspectors/DocumentInspector.m", "GraphSketcher/App/Inspectors/AxisInspector.m", "GraphSketcher/App/Inspectors/StyleInspector.m", "GraphSketcher/App/OIInspector-RSExtensions.m", "Checks/InspectorActionChecks.m")]
color_command += ["-o", str(contents / "MacOS/action-checks")]
(output / "action-compile-command.json").write_text(json.dumps(color_command, indent=2) + "\n")
compiled = subprocess.run(color_command, capture_output=True)
(output / "action-compile.log").write_bytes(compiled.stdout + compiled.stderr)
if compiled.returncode:
    print((compiled.stdout + compiled.stderr).decode(errors="replace"))
compiled.check_returncode()
result = subprocess.run([str(contents / "MacOS/action-checks")], capture_output=True)
log = result.stdout + result.stderr
(output / "action-checks.log").write_bytes(log)
print(log.decode(errors="replace"))
assert result.returncode == 0 and b"PASS inspector actions:" in log and not any(marker in log for marker in (b"ASSERT failed", b"Assertion Failed:", b"Exception raised:", b"Unable to simultaneously satisfy constraints")), "Inspector action checks failed; see action-checks.log"

verify_preferences()
atexit.unregister(verify_preferences)
print("PASS real application preference domains unchanged")
