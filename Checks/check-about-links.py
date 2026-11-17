#!/usr/bin/env python3
"""Check packaged notices and native TextKit dispatch without launching any GUI."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__, epilog="Example: python3 Checks/check-about-links.py --products /own/Products/Debug --output /own/new-checks")
parser.add_argument("--products", required=True, type=Path, help="Independently built products directory containing Graphink.app")
parser.add_argument("--output", required=True, type=Path, help="New output directory; existing paths are refused")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
products = args.products.resolve()
output = args.output.resolve()
app = products / "Graphink.app/Contents"
if not (app / "Info.plist").is_file():
    parser.error("--products must contain a built Graphink.app")
if output.exists():
    parser.error("--output already exists; choose a new directory to preserve prior evidence")

notices = root / "GraphSketcher/App/English.lproj/ThirdPartyNotices.html"
# Pinned copy of 2b5ab59:GraphSketcher/App/English.lproj/ThirdPartyNotices.html, the notices before the 2026 changes.
pinned = root / "Checks/reference/ThirdPartyNotices-2b5ab59.html"
pinned_bytes = pinned.read_bytes()
assert hashlib.sha1(b"blob %d\0" % len(pinned_bytes) + pinned_bytes).hexdigest() == "2a21324863d8a2d766657a14752456cefb27da74", "Pinned 2b5ab59 notices changed"
base = pinned_bytes.decode()
current = notices.read_text()
def blocks(text):
    return [html.unescape(block) for block in re.findall(r"<pre>(.*?)</pre>", text, re.S)]
assert len(blocks(current)) == 8 and blocks(current)[:7] == blocks(base), "Original notice blocks changed"
assert blocks(current)[7] == (root / "GraphSketcher/App/Resources/StyleFonts/OFL.txt").read_text(), "Bundled Kalam license changed"
legal = r"<h3>Omni Source License 2007</h3>(.*?)<h2"
assert re.search(legal, current, re.S)[1] == re.search(legal, base, re.S)[1], "Omni license text changed"
assert hashlib.sha256((root / "OmniSourceLicense.html").read_bytes()).hexdigest() == "b811c202aef202a2b495279424ddc647f46a0faf2e1d2cf2e766a28a67bafc1a"
for anchor in re.findall(r'href="#([^"]+)"', current):
    assert f'id="{anchor}"' in current, f"Missing anchor: {anchor}"
resources = {"English.lproj/Credits.html": root / "GraphSketcher/App/English.lproj/Credits.html", "English.lproj/ThirdPartyNotices.html": notices, "OmniSourceLicense.html": root / "OmniSourceLicense.html"}
for name, source in resources.items():
    assert (app / "Resources" / name).read_bytes() == source.read_bytes(), f"Packaged bytes differ: {name}"
info = plistlib.loads((app / "Info.plist").read_bytes())
assert info["OAAboutPanelControllerClass"] == "RSAboutPanelController"
symbols = subprocess.check_output(["nm", "-gj", str(app / "MacOS" / info["CFBundleExecutable"])])
assert b"_OBJC_CLASS_$_RSAboutPanelController" in symbols, "Controller absent from emitted executable"
output.mkdir(parents=True)
fixture = output / "Initial/AboutChecks.app/Contents"
(fixture / "MacOS").mkdir(parents=True)
for name, source in resources.items():
    dest = fixture / "Resources" / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
fixture_info = {key: info[key] for key in ("CFBundleVersion", "CFBundleShortVersionString", "NSHumanReadableCopyright", "OAAboutPanelControllerClass")}
fixture_info.update(CFBundleExecutable="checks", CFBundleIdentifier="com.graphsketcher.AboutChecks", CFBundlePackageType="APPL")
(fixture / "Info.plist").write_bytes(plistlib.dumps(fixture_info))
command = ["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=12.0", "-fobjc-arc", "-fblocks", "-Wall", "-Werror", f"-F{products}", "-framework", "AppKit", "-framework", "OmniAppKit", "-framework", "OmniFoundation", "-framework", "OmniBase", f"-Wl,-rpath,{products}", str(root / "GraphSketcher/App/RSAboutPanelController.m"), str(root / "Checks/AboutLinkChecks.m"), "-o", str(fixture / "MacOS/checks")]
(output / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
subprocess.run(command, check=True)
relocated = output / "Relocated With Spaces ü/AboutChecks.app"
shutil.copytree(fixture.parent, relocated)
for label, bundle in (("initial", fixture.parent), ("relocated", relocated)):
    result = subprocess.run([str(bundle / "Contents/MacOS/checks")], capture_output=True)
    log = result.stdout + result.stderr
    (output / f"{label}.log").write_bytes(log)
    assert result.returncode == 0 and b"PASS About link contract" in log and b"ASSERT failed" not in log, log.decode(errors="replace")
print("PASS packaged bytes, original legal blocks, navigation, emitted class, native TextKit dispatch and relocated fixture; browser acceptance remains untested")
