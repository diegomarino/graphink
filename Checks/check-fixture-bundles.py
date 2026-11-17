#!/usr/bin/env python3
"""Fail if a check fixture app could claim Graphink documents or ship with the app.

Check harnesses write throwaway .app bundles and run them; running a bundle registers it with
Launch Services, and Launch Services can register a bundle on disk again on its own later. A
fixture that declares document types or UTIs then shows up in Finder as "Open with <Fixture>"
for .graphink/.ograph and can redefine the type's Kind. So, for every .app under --evidence other
than the real Graphink.app, after the checks have run:
- no CFBundleDocumentTypes, UTExported/UTImportedTypeDeclarations, CFBundleURLTypes or NSServices
  (the fixtures that need document types to run drop them afterwards, see check-document-types.py,
  check-new-from.py and check-graphink-extensions.py);
- a bundle identifier that is not the app's (com.diegomarino.Graphink*) or GraphSketcher's.
And --products, the directory that is zipped and delivered, holds no app but Graphink.app.

Read-only: inspects Info.plist files, registers nothing.
"""
import argparse
from pathlib import Path
import plistlib

CLAIMS = ("CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations", "CFBundleURLTypes", "NSServices")
REAL_IDENTIFIERS = ("com.diegomarino.graphink", "com.graphsketcher.graphsketcher", "com.omnigroup.graphsketcher")

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

fixtures = sorted({p.resolve() for root in args.evidence for p in root.resolve().rglob("*.app") if p.name != "Graphink.app" and (p / "Contents/Info.plist").is_file()})
if not fixtures:
    parser.error("No fixture bundles under --evidence; run the checks first")
for bundle in fixtures:
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    identifier = info.get("CFBundleIdentifier", "")
    if identifier.lower().startswith(REAL_IDENTIFIERS):
        failures.append(f"{bundle}: uses a real application identifier {identifier}")
    claims = {key for key in CLAIMS if key in info}
    if claims:
        failures.append(f"{bundle}: declares {', '.join(sorted(claims))}")

for failure in failures:
    print("FAIL " + failure)
if failures:
    raise SystemExit(f"FAIL {len(failures)} fixture bundle problem(s)")
print(f"PASS fixture bundles: {len(fixtures)} checked, none claim documents; "
      f"only Graphink.app in {products}")
