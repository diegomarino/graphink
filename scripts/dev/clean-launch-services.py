#!/usr/bin/env python3
"""List, check or remove Launch Services registrations that claim Graphink documents.

Every app that macOS has seen (opened, unzipped, built, run by a check harness) stays registered
with Launch Services, even after it is deleted. Any of them that declares .graphink/.ograph or
their UTIs competes for "Open with" and can redefine the Kind Finder shows. This finds every
registered app that claims them, through a document type or a type declaration, and sorts it:

- KEEP: the paths given with --keep, and original OmniGraphSketcher apps (com.omnigroup.*).
- REMOVE: everything else: check fixtures, old Graphink/GraphSketcher dev copies, mounted DMG
  copies and registrations whose app no longer exists.

Modes (default: list only, changes nothing):
  --check   exit 1 if anything would be removed (for test checklists).
  --apply   unregister every REMOVE path with `lsregister -u`, then re-register the --keep paths
            with `lsregister -f` so they handle the documents. Files are not deleted.

Only the Launch Services database is changed, and only with --apply. Unregistering is undone by
opening the app again.
"""
import argparse
from pathlib import Path
import subprocess
import sys

LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
UTIS = {"com.diegomarino.graphink.document", "com.graphsketcher.graphdocument"}
EXTENSIONS = {".graphink", ".ograph", "graphink", "ograph"}
ORIGINAL_PREFIX = "com.omnigroup."


def field(record, name):
    for line in record:
        if line.startswith(name + ":"):
            return line.split(":", 1)[1].strip()
    return None


def unit(value):
    """'Graphink (0x3a40)' -> '0x3a40'."""
    return value.rsplit("(", 1)[-1].rstrip(")") if value and value.endswith(")") else None


def words(value):
    return {w.strip(",") for w in (value or "").split()}


def registrations():
    dump = subprocess.run([LSREGISTER, "-dump"], capture_output=True, text=True, check=True).stdout
    records, current = [], []
    for line in dump.splitlines():
        if line.startswith("-----"):
            records.append(current)
            current = []
        else:
            current.append(line)
    records.append(current)

    bundles, claimants = {}, set()
    for record in records:
        bundle_id = field(record, "bundle id")
        if bundle_id:
            path = field(record, "path")
            if path:
                bundles[unit(bundle_id)] = (path.rsplit(" (0x", 1)[0], field(record, "identifier") or "")
            if words(field(record, "claimed UTIs")) & UTIS:
                claimants.add(unit(bundle_id))
            continue
        owner = unit(field(record, "bundle"))
        if not owner:
            continue
        if field(record, "claim id") and words(field(record, "bindings")) & (UTIS | EXTENSIONS):
            claimants.add(owner)
        if field(record, "type id") and (field(record, "uti") in UTIS or words(field(record, "tags")) & EXTENSIONS):
            claimants.add(owner)
    return sorted({bundles[u] for u in claimants if u in bundles})


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                     epilog="Example: python3 scripts/dev/clean-launch-services.py --keep ~/Desktop/GraphinkRetest/app/GraphinkRetest.app --apply")
    parser.add_argument("--keep", type=Path, action="append", default=[], help="app bundle to keep registered (repeatable)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="exit 1 if anything would be removed")
    mode.add_argument("--apply", action="store_true", help="unregister everything listed as REMOVE")
    args = parser.parse_args()
    keep = {str(p.expanduser().resolve()) for p in args.keep}
    for path in keep:
        if not Path(path, "Contents/Info.plist").is_file():
            parser.error(f"--keep {path}: not an app bundle")

    remove = []
    for path, identifier in registrations():
        resolved = str(Path(path).resolve()) if Path(path).exists() else path
        if resolved in keep or identifier.startswith(ORIGINAL_PREFIX):
            print(f"KEEP    {path}  [{identifier}]")
        else:
            state = "" if Path(path).exists() else "  (app no longer exists)"
            print(f"REMOVE  {path}  [{identifier}]{state}")
            remove.append(path)

    if args.check:
        print(f"{'FAIL' if remove else 'PASS'}: {len(remove)} registration(s) to remove")
        return 1 if remove else 0
    if not args.apply:
        print(f"{len(remove)} registration(s) would be removed; run again with --apply to unregister them")
        return 0

    failed = 0
    for path in remove:
        result = subprocess.run([LSREGISTER, "-u", path], capture_output=True, text=True)
        if result.returncode:
            failed += 1
            print(f"ERROR   lsregister -u {path}: {(result.stderr or result.stdout).strip()}")
    for path in sorted(keep):
        subprocess.run([LSREGISTER, "-f", path], check=True)
    left = [path for path, identifier in registrations()
            if path not in keep and not identifier.startswith(ORIGINAL_PREFIX)]
    print(f"Unregistered {len(remove) - failed} of {len(remove)}; {len(left)} still claim Graphink documents")
    for path in left:
        hint = "  (still on disk: macOS registers it again; move it to the Trash)" if Path(path).exists() else ""
        print(f"LEFT    {path}{hint}")
    return 1 if failed or left else 0


if __name__ == "__main__":
    sys.exit(main())
