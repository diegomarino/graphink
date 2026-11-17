#!/usr/bin/env python3
"""Run linked production model checks without starting NSApplication or LinkBack."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def snapshot():
    result = {}
    for domain in ["com.diegomarino.Graphink", "com.omnigroup.GraphSketcher"]:
        read = subprocess.run(["/usr/bin/defaults", "export", domain, "-"], capture_output=True)
        result[domain] = dict(exit=read.returncode, bytes=len(read.stdout),
                              sha256=hashlib.sha256(read.stdout).hexdigest())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog="Example: python3 Checks/Analyzer/model/check-production.py --products /private/tmp/graphink-analyzer-model/Products/Debug")
    parser.add_argument("--products", required=True, type=Path, help="Own completed Debug build products")
    parser.add_argument("--output", type=Path, help="Evidence directory; default: new temporary directory")
    args = parser.parse_args()
    products = args.products.resolve()
    if not (products / "GraphSketcherModel.framework/GraphSketcherModel").is_file():
        parser.error("Missing model framework; complete the documented own Debug build first.")
    output = args.output or Path(tempfile.mkdtemp(prefix="graphink-model-production-"))
    output.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[3]
    info = output / "Info.plist"
    info.write_bytes(plistlib.dumps(dict(CFBundleIdentifier="org.graphink.analyzer.model.xml-fixture",
        CFBundleName="Model Analyzer Fixture", CFBundleVersion="1", CFBundleShortVersionString="1.0",
        NSHumanReadableCopyright="Copyright 2026 Model Analyzer Fixture")))
    binary = output / "ModelChecks"
    command = ["xcrun", "clang", "-fno-objc-arc", "-g", "-DDEBUG", "-DOMNI_BUILDING_FOR_MAC",
        "-include", "Cocoa/Cocoa.h", "-include", "OmniBase/OmniBase.h", "-F", str(products),
        "-framework", "Cocoa", "-framework", "OmniBase", "-framework", "OmniFoundation",
        "-framework", "GraphSketcherModel", "-Wl,-rpath," + str(products),
        "-Wl,-sectcreate,__TEXT,__info_plist," + str(info),
        str(root / "Checks/Analyzer/model/XMLChecks.m"), "-o", str(binary)]
    (output / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
    compile_result = subprocess.run(command, capture_output=True, text=True)
    (output / "compile.log").write_text(compile_result.stdout + compile_result.stderr)
    if compile_result.returncode:
        print(compile_result.stderr)
        return 1
    before = snapshot()
    run = subprocess.run([str(binary)], capture_output=True, text=True)
    after = snapshot()
    log = run.stdout + run.stderr
    (output / "run.log").write_text(log)
    (output / "preferences-before.json").write_text(json.dumps(before, indent=2) + "\n")
    (output / "preferences-after.json").write_text(json.dumps(after, indent=2) + "\n")
    passed = run.returncode == 0 and before == after and run.stdout.count("PASS ") == 2
    passed &= not bool(re.search(r"ASSERT.*failed|Assertion failed|FATAL|ERROR:", log))
    print(log, end="")
    print("Preference preservation:", "PASS" if before == after else "FAIL")
    print("Evidence:", output)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
