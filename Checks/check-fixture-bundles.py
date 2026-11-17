#!/usr/bin/env python3
"""Fail if a check fixture app could claim Graphink documents or ship with the app.

Check harnesses write throwaway .app bundles and run them; running a bundle registers it with
Launch Services. A fixture that declares document types or UTIs then shows up in Finder as
"Open with <Fixture>" for .graphink/.ograph and can redefine the type's Kind. So, for every
.app under --evidence other than the real Graphink.app:
- no CFBundleDocumentTypes, UTExported/UTImportedTypeDeclarations, CFBundleURLTypes or NSServices,
  except the fixtures in NEEDS_TYPES, which may keep their types ranked None and must not be
  registered with Launch Services after their run;
- a bundle identifier that is not the app's (com.diegomarino.Graphink*) or GraphSketcher's.
And --products, the directory that is zipped and delivered, holds no app but Graphink.app.

Read-only: inspects Info.plist files and the Launch Services database, registers nothing.
"""
import argparse
from pathlib import Path
import plistlib
import subprocess

LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
CLAIMS = ("CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations", "CFBundleURLTypes", "NSServices")
REAL_IDENTIFIERS = ("com.diegomarino.graphink", "com.graphsketcher.graphsketcher", "com.omnigroup.graphsketcher")
# NSDocumentController maps types to document classes only through CFBundleDocumentTypes, and these
# fixtures check that mapping (and, for the last two, the declared UTIs themselves).
NEEDS_TYPES = {
    "NewFromChecks.app": {"CFBundleDocumentTypes"},
    "DocumentTypeChecks.app": {"CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"},
    "ExtensionChecks.app": {"CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"},
}

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="Example: python3 Checks/check-fixture-bundles.py --products BUILD/Debug/Products/Debug --evidence BUILD/checks")
parser.add_argument("--products", required=True, type=Path, help="Debug products directory that holds Graphink.app")
parser.add_argument("--evidence", required=True, type=Path, nargs="+", help="Directories the checks wrote their fixtures to")
args = parser.parse_args()
products = args.products.resolve()
if not (products / "Graphink.app/Contents/Info.plist").is_file():
    parser.error("--products must contain Graphink.app")

failures = []
shipped = sorted(p for p in products.rglob("*.app") if p != products / "Graphink.app" and products / "Graphink.app" not in p.parents)
failures += [f"{p}: app bundle in the delivered products directory" for p in shipped]

registered = subprocess.run([LSREGISTER, "-dump"], capture_output=True, text=True, check=True).stdout
registered = {line.split(":", 1)[1].strip().rsplit(" (0x", 1)[0] for line in registered.splitlines() if line.startswith("path:")}

fixtures = sorted({p.resolve() for root in args.evidence for p in root.resolve().rglob("*.app") if p.name != "Graphink.app" and (p / "Contents/Info.plist").is_file()})
if not fixtures:
    parser.error("No fixture bundles under --evidence; run the checks first")
for bundle in fixtures:
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    identifier = info.get("CFBundleIdentifier", "")
    if identifier.lower().startswith(REAL_IDENTIFIERS):
        failures.append(f"{bundle}: uses a real application identifier {identifier}")
    claims = {key for key in CLAIMS if key in info}
    allowed = NEEDS_TYPES.get(bundle.name, set())
    if claims - allowed:
        failures.append(f"{bundle}: declares {', '.join(sorted(claims - allowed))}")
    if claims:
        ranks = {t.get("LSHandlerRank") for t in info.get("CFBundleDocumentTypes", [])}
        if ranks - {"None"}:
            failures.append(f"{bundle}: document types ranked {sorted(map(str, ranks))}, not None")
        if str(bundle) in registered:
            failures.append(f"{bundle}: declares document types and is still registered with Launch Services")

for failure in failures:
    print("FAIL " + failure)
if failures:
    raise SystemExit(f"FAIL {len(failures)} fixture bundle problem(s)")
typed = sum(1 for b in fixtures if b.name in NEEDS_TYPES)
print(f"PASS fixture bundles: {len(fixtures)} checked, none claim documents except {typed} unregistered rank-None type fixtures; "
      f"only Graphink.app in {products}")
