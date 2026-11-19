#!/usr/bin/env python3
"""Link exact production app objects into an offscreen fixture that checks the app side of `graphink`.

- File ▸ Export and `graphink render` produce the same output: for every example, the fixture opens the
  document the app's way, draws it in an offscreen window and takes the export panel's data (PNG at 72 and
  144 DPI, PDF); the tool in Graphink.app/Contents/Helpers renders the same document. The PNGs must be
  byte-identical and the PDFs, rasterized, identical pixel for pixel.
- Graphink ▸ Install Command-Line Tool…: the menu item exists in MainMenu.xib, the window's command names
  the running bundle's own helper, Copy puts exactly that command on a (private) pasteboard, and a bundle
  path with shell-special characters is quoted so the shell reads it back unchanged.

Run with host AppKit access. Never runs application startup handlers or a launch loop.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="Example: python3 Checks/check-cli-app.py --products /tmp/own/Debug/Products/Debug --objects /tmp/own/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/Graphink.LinkFileList --output /tmp/cli-app-new")
parser.add_argument("--products", required=True, type=Path, help="Exact current-source Debug products")
parser.add_argument("--objects", required=True, type=Path, help="Matching Graphink.LinkFileList from that build")
parser.add_argument("--output", required=True, type=Path, help="Fresh owned evidence directory; existing paths refused")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
products, output = args.products.resolve(), args.output.resolve()
if output.exists():
    parser.error("Output exists; choose a fresh evidence directory")
helper = products / "Graphink.app/Contents/Helpers/graphink"
if not args.objects.is_file() or not helper.is_file():
    parser.error("Missing objects/products; first build this exact candidate")
objects = [Path(line) for line in args.objects.read_text().splitlines() if Path(line).name != "main.o"]
if not objects or not all(path.is_file() for path in objects):
    parser.error("LinkFileList contains missing objects; use matching build products")


def fail(message):
    raise SystemExit("FAIL " + message)


def run(command, log):
    proc = subprocess.run([str(c) for c in command], capture_output=True, text=True, timeout=600)
    Path(log).write_text("$ " + " ".join(map(str, command)) + "\n" + proc.stdout + proc.stderr)
    if proc.returncode:
        fail(f"exit {proc.returncode}; see {log}")
    return proc


# The menu item, in the source the app's MainMenu.nib is compiled from.
xib = (root / "GraphSketcher/App/English.lproj/MainMenu.xib").read_text()
item = re.search(r'<menuItem title="Install Command-Line Tool…" id="[^"]+">.*?</menuItem>', xib, re.S)
if not item or 'selector="showCommandLineToolInstaller:" target="205"' not in item.group(0):
    fail("MainMenu.xib has no Install Command-Line Tool… item sending showCommandLineToolInstaller: to AppController")
if xib.index(item.group(0)) > xib.index('<menuItem title="Services"'):
    fail("Install Command-Line Tool… is not in the Graphink menu before Services")

contents = output / "CLIAppChecks.app/Contents"
(contents / "MacOS").mkdir(parents=True)
shutil.copytree(products / "Graphink.app/Contents/Resources", contents / "Resources")
info = plistlib.loads((products / "Graphink.app/Contents/Info.plist").read_bytes())
info.update(CFBundleExecutable="checks", CFBundleIdentifier="com.graphink.cliappchecks." + uuid.uuid4().hex, OFControllerClass="AppController", NSQuitAlwaysKeepsWindows=False)
for key in ("NSMainNibFile", "CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"):
    info.pop(key, None)
(contents / "Info.plist").write_bytes(plistlib.dumps(info))
(contents / "Frameworks").symlink_to(products)
source = root / "Checks/CLIAppChecks.m"
command = ["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-fblocks", "-DOMNI_BUILDING_FOR_MAC=1", "-include", str(root / "GraphSketcher/App/GraphSketcher_Prefix.h"), "-I", str(root / "GraphSketcher/App"), "-F", str(products), "-Wl,-rpath," + str(products), "-lxml2"]
for framework in ("Cocoa", "SystemConfiguration", "Carbon", "CoreText", "QuartzCore", "ImageIO", "OmniAppKit", "OmniBase", "OmniFoundation", "OmniInspector", "OmniUnzip", "OmniQuartz", "LinkBack", "GraphSketcherModel"):
    command += ["-framework", framework]
command += [str(source), *map(str, objects), "-o", str(contents / "MacOS/checks")]
(output / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
receipt = {"bundle_id": info["CFBundleIdentifier"], "source_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(), "inputs": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source, *objects]}}
compiled = subprocess.run(command, capture_output=True)
(output / "compile.log").write_bytes(compiled.stdout + compiled.stderr)
if compiled.returncode:
    fail("compilation failed; inspect " + str(output / "compile.log"))
imagediff = output / "ImageDiff"
run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Werror", "-framework", "Foundation", "-framework", "CoreGraphics", "-framework", "ImageIO", root / "tools/cli/ImageDiff.m", "-o", imagediff], output / "imagediff-build.log")

examples = sorted((root / "Examples").rglob("*.graphink"))
before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in examples}
(output / "documents.txt").write_text("".join(f"{p}\n" for p in examples))
exports = output / "exports"
exports.mkdir()
run_log = output / "checks.log"
proc = subprocess.run([str(contents / "MacOS/checks"), str(exports), str(output / "documents.txt"), "-ApplePersistenceIgnoreState", "YES"], capture_output=True, timeout=900)
run_log.write_bytes(proc.stdout + proc.stderr)
log = proc.stdout + proc.stderr
receipt["returncode"] = proc.returncode
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(log.decode(errors="replace")[-2000:])
if proc.returncode or b"PASS File" not in log or any(marker in log for marker in (b"ASSERT failed", b"PRECONDITION failed", b"Assertion Failed:", b"Exception raised:", b"FAIL ")):
    fail("CLI app fixture; inspect " + str(output))
report = json.loads((exports / "fixture-report.json").read_text())

# The command reads back, through the shell itself, as the running bundle's helper, even for a path the
# shell would otherwise expand. Only printf runs: the command's own words are matched, not executed.
for bundle, command_line in ((contents.parent, report["installCommand"]), (Path(report["oddBundle"]), report["oddCommand"])):
    match = re.fullmatch(r'sudo mkdir -p /usr/local/bin && sudo ln -sf (".*") /usr/local/bin/graphink', command_line, re.S)
    if not match:
        fail(f"unexpected install command {command_line}")
    target = subprocess.run(["/bin/sh", "-c", "printf %s " + match.group(1)], capture_output=True, text=True, check=True).stdout
    if Path(target).resolve() != (bundle / "Contents/Helpers/graphink").resolve():
        fail(f"{command_line} links {target}, not {bundle}/Contents/Helpers/graphink")

# File ▸ Export and graphink render: same PNG bytes, same PDF pixels.
renders = output / "renders"
renders.mkdir()
for entry in report["exports"]:
    document, base = Path(entry["document"]), Path(entry["export"])
    name = base.name
    for suffix, options in ((".png", []), ("@144.png", ["--dpi", "144"]), (".pdf", [])):
        run([helper, "render", document, "-o", renders / (name + suffix), *options], output / f"render-{name}{suffix}.log")
    for suffix in (".png", "@144.png"):
        if (renders / (name + suffix)).read_bytes() != Path(str(base) + suffix).read_bytes():
            fail(f"{document}: graphink render {suffix} differs from File > Export")
    for which, pdf in (("app", Path(str(base) + ".pdf")), ("cli", renders / (name + ".pdf"))):
        run([imagediff, "--rasterize-pdf", pdf, output / f"{name}-{which}-pdf.png", "2"], output / f"rasterize-{name}-{which}.log")
    diff = json.loads(run([imagediff, output / f"{name}-app-pdf.png", output / f"{name}-cli-pdf.png"], output / f"pdf-diff-{name}.log").stdout)
    if not diff["sameSize"] or diff["differing"]:
        fail(f"{document}: graphink render's PDF differs from File > Export's: {diff}")
after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in examples}
if after != before:
    fail("an example changed")
print(f"PASS File > Export and graphink render agree for {len(report['exports'])} documents (PNG at 72 and 144 DPI byte for byte, "
      f"PDF pixel for pixel); Install Command-Line Tool… names {contents.parent}")
