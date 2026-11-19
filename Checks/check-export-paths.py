#!/usr/bin/env python3
"""Check the app's view-based drawing paths: raster export, the view's PDF, Copy as Image and the saved preview.

Checks/ExportPathChecks.m is linked from the exact production app objects into an offscreen fixture. For every
example it opens the document the app's way, selects everything, and writes the graph view's PNG export (72 and
144 DPI), the view's PDF, Copy as Image's PDF, PNG and TIFF (private pasteboard) and the document saved, whose
preview.pdf the view draws. Since RSGraphView -drawRect: hands every drawing that is not on screen to
RSDrawGraphForExport, these must equal `graphink render`:
- every PDF (view, copy, preview), rasterized at 2x, pixel for pixel equal to `graphink render`'s PDF: so no
  selection, handle or other screen-only state reaches a copy or a preview;
- the view's PNGs pixel for pixel equal to `graphink render`'s at the same DPI;
- Copy's PNG and TIFF (captured from the view at the window's backing scale) within the color-rounding bound
  tools/cli/check-cli.py allows the shipped previews, when there are any: -initWithFocusedViewRect: captures
  nothing from a window that is not on screen, so offscreen only their absence is recorded (and, with a
  base, must match the base's).

With --base-root/--base-products/--base-objects (a build of another revision, such as main before a change to
the drawing code; not in CI), the same fixture source is also linked from that revision's objects and run on
the same documents, and each output is compared with the base's: rasters directly, PDFs rasterized, all within
that same bound (an exact match is reported as 0 differing pixels). The base references are made at check time;
nothing is committed. Never runs application startup handlers or a launch loop.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid
import zipfile

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="Example: python3 Checks/check-export-paths.py --products /tmp/own/Debug/Products/Debug --objects /tmp/own/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/Graphink.LinkFileList --output /tmp/export-paths-new")
parser.add_argument("--products", required=True, type=Path, help="Exact current-source Debug products")
parser.add_argument("--objects", required=True, type=Path, help="Matching Graphink.LinkFileList from that build")
parser.add_argument("--output", required=True, type=Path, help="Fresh owned evidence directory; existing paths refused")
parser.add_argument("--base-root", type=Path, help="Source tree of the base revision (its headers)")
parser.add_argument("--base-products", type=Path, help="Debug products built from --base-root")
parser.add_argument("--base-objects", type=Path, help="Graphink.LinkFileList of that build")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = args.output.resolve()
if output.exists():
    parser.error("Output exists; choose a fresh evidence directory")
base = (args.base_root, args.base_products, args.base_objects)
if any(base) and not all(base):
    parser.error("--base-root, --base-products and --base-objects go together")
helper = args.products.resolve() / "Graphink.app/Contents/Helpers/graphink"
if not helper.is_file():
    parser.error("No graphink helper in --products; build this exact candidate first")
FRAMEWORKS = ("Cocoa", "SystemConfiguration", "Carbon", "CoreText", "QuartzCore", "ImageIO", "OmniAppKit", "OmniBase", "OmniFoundation", "OmniInspector", "OmniUnzip", "OmniQuartz", "LinkBack", "GraphSketcherModel")


def fail(message):
    raise SystemExit("FAIL " + message)


def run(command, log):
    proc = subprocess.run([str(c) for c in command], capture_output=True, text=True, timeout=600)
    Path(log).write_text("$ " + " ".join(map(str, command)) + "\n" + proc.stdout + proc.stderr)
    if proc.returncode:
        fail(f"{command[0]} exited {proc.returncode}; see {log}")
    return proc


def fixture(name, tree, products, objects_list, documents):
    """Link ExportPathChecks.m from tree's headers and products' objects, run it, return its report."""
    products = products.resolve()
    objects = [Path(line) for line in objects_list.read_text().splitlines() if Path(line).name != "main.o"]
    if not objects or not all(path.is_file() for path in objects):
        fail(f"{objects_list} lists missing objects; use matching build products")
    work = output / name
    contents = work / "ExportPathChecks.app/Contents"
    (contents / "MacOS").mkdir(parents=True)
    shutil.copytree(products / "Graphink.app/Contents/Resources", contents / "Resources")
    info = plistlib.loads((products / "Graphink.app/Contents/Info.plist").read_bytes())
    info.update(CFBundleExecutable="checks", CFBundleIdentifier="com.graphink.exportpathchecks." + uuid.uuid4().hex, OFControllerClass="AppController", NSQuitAlwaysKeepsWindows=False)
    for key in ("NSMainNibFile", "CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"):
        info.pop(key, None)
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    (contents / "Frameworks").symlink_to(products)
    source = root / "Checks/ExportPathChecks.m"
    command = ["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-fblocks", "-DOMNI_BUILDING_FOR_MAC=1",
               "-include", str(tree / "GraphSketcher/App/GraphSketcher_Prefix.h"), "-I", str(tree / "GraphSketcher/App"), "-F", str(products), "-Wl,-rpath," + str(products), "-lxml2"]
    for framework in FRAMEWORKS:
        command += ["-framework", framework]
    command += [str(source), *map(str, objects), "-o", str(contents / "MacOS/checks")]
    (work / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=tree, text=True).strip()
    receipt = {"bundle_id": info["CFBundleIdentifier"], "source_sha": revision, "inputs": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source, *objects]}}
    compiled = subprocess.run(command, capture_output=True)
    (work / "compile.log").write_bytes(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        fail(f"{name}: compilation failed; inspect {work / 'compile.log'}")
    exports = work / "exports"
    exports.mkdir()
    (work / "documents.txt").write_text("".join(f"{p}\n" for p in documents))
    proc = subprocess.run([str(contents / "MacOS/checks"), str(exports), str(work / "documents.txt"), "-ApplePersistenceIgnoreState", "YES"], capture_output=True, timeout=900)
    log = proc.stdout + proc.stderr
    (work / "checks.log").write_bytes(log)
    receipt["returncode"] = proc.returncode
    (work / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if proc.returncode or b"PASS export paths" not in log or any(marker in log for marker in (b"ASSERT failed", b"PRECONDITION failed", b"Assertion Failed:", b"Exception raised:", b"FAIL ")):
        fail(f"{name}: fixture failed; inspect {work}")
    report = json.loads((exports / "fixture-report.json").read_text())
    for entry in report["documents"]:
        with zipfile.ZipFile(entry["base"] + ".saved.graphink") as package:
            if "preview.pdf" not in package.namelist():
                fail(f"{entry['document']}: the saved document has no preview.pdf")
            Path(entry["base"] + ".preview.pdf").write_bytes(package.read("preview.pdf"))
    return report, revision


imagediff = output / "ImageDiff"
output.mkdir(parents=True)
run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Werror", "-framework", "Foundation", "-framework", "CoreGraphics", "-framework", "ImageIO", root / "tools/cli/ImageDiff.m", "-o", imagediff], output / "imagediff-build.log")


def diff(a, b, log):
    result = json.loads(run([imagediff, a, b], log).stdout)
    if not result["sameSize"]:
        fail(f"{a} and {b} differ in size: {result}")
    return result


def within_bound(result):
    # The bound tools/cli/check-cli.py allows between direct rasters and the shipped previews: color rounding and
    # antialiasing only; a moved label or a cropped page exceeds it.
    return result["over64"] <= result["pixels"] // 1000 and result["meanChannelDiff"] < 2


def raster(pdf):
    png = Path(str(pdf) + ".png")
    if not png.exists():
        run([imagediff, "--rasterize-pdf", pdf, png, "2"], Path(str(pdf) + ".rasterize.log"))
    return png


examples = sorted((root / "Examples").rglob("*.graphink"))
before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in examples}
head, head_revision = fixture("head", root, args.products, args.objects, examples)
renders = output / "renders"
renders.mkdir()
summary = {"documents": len(head["documents"]), "pdfs": 0, "pngs": 0, "copyRasters": [], "base": None}
for entry in head["documents"]:
    document, out = Path(entry["document"]), Path(entry["base"])
    name = out.name
    for suffix, options in ((".png", []), ("@144.png", ["--dpi", "144"]), (".pdf", [])):
        run([helper, "render", document, "-o", renders / (name + suffix), *options], renders / f"{name}{suffix}.log")
    reference = raster(renders / (name + ".pdf"))
    for kind in ("view", "copy", "preview"):
        result = diff(raster(Path(f"{out}.{kind}.pdf")), reference, output / f"{name}.{kind}-pdf.diff.log")
        if result["differing"]:
            fail(f"{document}: the {kind} PDF differs from graphink render's: {result}")
        summary["pdfs"] += 1
    for suffix in (".png", "@144.png"):
        result = diff(Path(str(out) + suffix), renders / (name + suffix), output / f"{name}{suffix}.diff.log")
        if result["differing"]:
            fail(f"{document}: the view's {suffix} export differs from graphink render's: {result}")
        summary["pngs"] += 1
    width = entry["canvas"][0]
    for kind in ("png", "tiff"):
        summary["copyRasters"].append({"document": str(document), "kind": kind, "written": entry["copyRasters"][kind]})
        if not entry["copyRasters"][kind]:
            continue
        copy = Path(f"{out}.copy.{kind}")
        scale = int(json.loads(run([imagediff, copy, copy], output / f"{name}.copy-{kind}.size.log").stdout)["size"][0]) / width
        if scale not in (1, 2):
            fail(f"{copy}: unexpected scale {scale}")
        render = renders / f"{name}@{scale:g}x.png"
        if not render.exists():
            run([helper, "render", document, "-o", render, "--scale", f"{scale:g}"], renders / f"{name}@{scale:g}x.log")
        result = diff(copy, render, output / f"{name}.copy-{kind}.diff.log")
        if not within_bound(result):
            fail(f"{document}: Copy as Image's {kind.upper()} differs from graphink render's beyond color rounding: {result}")
        summary["copyRasters"][-1].update(scale=scale, **{k: result[k] for k in ("differing", "over64", "meanChannelDiff")})

if all(base):
    base_report, base_revision = fixture("base", args.base_root.resolve(), args.base_products, args.base_objects, examples)
    if [e["document"] for e in base_report["documents"]] != [e["document"] for e in head["documents"]]:
        fail("the base fixture did not write the same documents")
    comparisons = []
    for ours, theirs in zip(head["documents"], base_report["documents"]):
        a, b = ours["base"], theirs["base"]
        if ours["copyRasters"] != theirs["copyRasters"]:
            fail(f"{ours['document']}: Copy as Image's rasters {ours['copyRasters']}, the base revision's {theirs['copyRasters']}")
        rasters = [f".copy.{kind}" for kind, written in ours["copyRasters"].items() if written]
        pairs = [(Path(a + s), Path(b + s), s) for s in (".png", "@144.png", *rasters)]
        pairs += [(raster(Path(f"{a}.{k}.pdf")), raster(Path(f"{b}.{k}.pdf")), f".{k}.pdf") for k in ("view", "copy", "preview")]
        for mine, reference, what in pairs:
            result = diff(mine, reference, output / f"{Path(a).name}{what}.base-diff.log")
            comparisons.append({"document": ours["document"], "output": what, **{k: result[k] for k in ("differing", "over64", "meanChannelDiff")}})
            if not within_bound(result):
                fail(f"{ours['document']}: {what} differs from the base revision {base_revision} beyond color rounding: {result}")
    worst = max(comparisons, key=lambda c: (c["meanChannelDiff"], c["differing"]))
    summary["base"] = {"revision": base_revision, "comparisons": len(comparisons), "exact": sum(1 for c in comparisons if not c["differing"]), "worst": worst}
    (output / "base-comparisons.json").write_text(json.dumps(comparisons, indent=2) + "\n")

after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in examples}
if after != before:
    fail("an example changed")
summary["revision"] = head_revision
(output / "report.json").write_text(json.dumps(summary, indent=2) + "\n")
copied = [c for c in summary["copyRasters"] if c["written"]]
line = (f"PASS export paths for {summary['documents']} documents: {summary['pdfs']} view, copy and preview PDFs equal to graphink render "
        f"pixel for pixel, {summary['pngs']} view PNGs exact, ")
line += (f"{len(copied)} Copy PNG/TIFF within color rounding (mean channel difference at most {max(c['meanChannelDiff'] for c in copied):.3f})" if copied
         else "Copy PNG/TIFF not drawn offscreen (they need an on-screen window)")
if summary["base"]:
    b = summary["base"]
    w = b["worst"]
    line += (f"; against {b['revision'][:7]}: {b['exact']}/{b['comparisons']} outputs exact, worst {w['differing']} differing pixels "
             f"(mean channel difference {w['meanChannelDiff']:.3f}, {Path(w['document']).name} {w['output']})")
print(line)
