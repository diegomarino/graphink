#!/usr/bin/env python3
"""Copy small check logs and this job's crash reports into the uploaded logs directory.

Usage: collect-diagnostics.py --build-root BUILD_ROOT --logs LOG_DIR --since MARKER [--executables-in GLOB ...] [--wait SECONDS]

The product checks keep their per-run logs (for example every `graphink render` of the cli check)
under BUILD_ROOT/checks, which is not uploaded. This copies every *.log file there into
LOG_DIR/checks/<same relative path>, each one at most 1 MiB (a longer log keeps its last MiB) and
all of them at most 20 MiB. Only *.log files that do not start with a Mach-O or other binary
magic are copied: never products, renders or binaries.

Crash reports (*.ips, *.crash) in ~/Library/Logs/DiagnosticReports modified after MARKER (a file
touched when the job started) are copied into LOG_DIR/crash-reports when they are for one of our
processes, matched by name (macOS redacts the paths in reports): Graphink, the graphink command-line
tool, or any Mach-O executable in BUILD_ROOT/*/Products, BUILD_ROOT/checks or an --executables-in
directory (the checks' fixtures). Reports of other processes stay where they are; their file and
process names are listed. macOS writes a report a moment after the crash, so with --wait (used when
the job failed) it keeps looking for up to that many seconds while none of ours has appeared.

Diagnostics only: it prints what it copied and the total size, and a problem here is reported but
never fails the job (exit 0).
"""
import argparse
import glob
import json
import os
from pathlib import Path
import re
import sys
import time

FILE_LIMIT = 1 << 20
TOTAL_LIMIT = 20 << 20
CRASH_LIMIT = 4 << 20
# Mach-O (both byte orders, 32/64-bit and fat); with PNG, PDF and zip, never copied as a log.
MACHO_MAGIC = (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe')
BINARY_MAGIC = MACHO_MAGIC + (b'\x89PNG', b'%PDF', b'PK\x03\x04')
OUR_NAMES = {'Graphink', 'graphink'}

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--build-root', required=True, type=Path)
parser.add_argument('--logs', required=True, type=Path)
parser.add_argument('--since', required=True, type=Path, help='File whose modification time is the job start')
parser.add_argument('--wait', type=float, default=0, metavar='SECONDS', help='Keep looking this long for a crash report of ours')
parser.add_argument('--executables-in', action='append', default=[], metavar='GLOB', help='Directories (a glob) whose executables are ours too, such as the toolchain checks\' fixtures')
args = parser.parse_args()


def size(n):
    return f'{n / 1024:.1f} KiB' if n < 1 << 20 else f'{n / (1 << 20):.1f} MiB'


def copy_logs():
    checks = args.build_root / 'checks'
    if not checks.is_dir():
        print(f'No check evidence at {checks}')
        return 0
    total, copied, skipped = 0, 0, []
    for path in sorted(p for p in checks.rglob('*.log') if p.is_file() and not p.is_symlink()):
        with path.open('rb') as f:
            if f.read(4) in BINARY_MAGIC:
                skipped.append(f'{path} (binary)')
                continue
        length = path.stat().st_size
        keep = min(length, FILE_LIMIT)
        if total + keep > TOTAL_LIMIT:
            skipped.append(f'{path} (over the {size(TOTAL_LIMIT)} total)')
            continue
        target = args.logs / 'checks' / path.relative_to(checks)
        target.parent.mkdir(parents=True, exist_ok=True)
        with path.open('rb') as f:
            f.seek(length - keep)
            data = f.read()
        if keep < length:
            data = f'[collect-diagnostics: first {length - keep} bytes of {length} dropped]\n'.encode() + data
        target.write_bytes(data)
        total += len(data)
        copied += 1
    print(f'Copied {copied} check logs ({size(total)}) from {checks}')
    for line in skipped:
        print(f'  skipped {line}')
    return total


def process_names(text):
    """Process and app names in an .ips report (a JSON header line, then a JSON body) or a .crash report.
    Paths are not used: macOS redacts them in reports (for example /private/tmp/*/fixture)."""
    header, _, body = text.partition('\n')
    names = set()
    try:
        meta = json.loads(header)
        names |= {meta.get('app_name'), meta.get('name')}
    except ValueError:
        pass
    names |= set(re.findall(r'"procName"\s*:\s*"([^"]+)"', body)[:1])
    names |= set(re.findall(r'^Process:\s+(\S+)', text, re.M)[:1])
    return {n for n in names if n}


def our_executables():
    """Names of the Mach-O executables in the build's products, its check evidence and the --executables-in
    directories: Graphink, graphink and every fixture the checks compiled."""
    roots = [args.build_root / 'checks', *args.build_root.glob('*/Products')]
    roots += [Path(d) for pattern in args.executables_in for d in glob.glob(pattern)]
    names = set(OUR_NAMES)
    for root in roots:
        for dirpath, _, files in os.walk(root):
            for file in files:
                path = Path(dirpath, file)
                try:
                    if path.is_symlink() or not os.access(path, os.X_OK):
                        continue
                    with path.open('rb') as f:
                        if f.read(4) in MACHO_MAGIC:
                            names.add(file)
                except OSError:
                    continue
    return names


def copy_crash_reports():
    if not args.since.is_file():
        print(f'::warning::No job-start marker at {args.since}; crash reports not collected')
        return 0
    since = args.since.stat().st_mtime
    folder = Path.home() / 'Library/Logs/DiagnosticReports'
    ours = None
    deadline = time.monotonic() + args.wait
    while True:
        candidates = sorted(p for p in folder.glob('*') if p.suffix in ('.ips', '.crash') and p.is_file() and p.stat().st_mtime > since) if folder.is_dir() else []
        reports = [(path, path.read_bytes()[:CRASH_LIMIT].decode('utf-8', errors='replace')) for path in candidates]
        if reports and ours is None:
            ours = our_executables()
        mine = [(path, text, process_names(text)) for path, text in reports]
        if any(names & ours for _, _, names in mine) or time.monotonic() >= deadline:
            break
        time.sleep(2)
    total, found, others = 0, 0, []
    for path, text, names in mine:
        if not names & ours:
            others.append(f'{path.name} ({", ".join(sorted(names)) or "no process name"})')
            continue
        target = args.logs / 'crash-reports' / path.name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        total += target.stat().st_size
        found += 1
        print(f'Crash report: {path.name} ({", ".join(sorted(names & ours))})')
    print(f'Copied {found} crash reports ({size(total)}) from {folder}; {len(others)} newer reports of other processes left out')
    for line in others:
        print(f'  left out {line}')
    return total


try:
    args.logs.mkdir(parents=True, exist_ok=True)
    collected = copy_logs() + copy_crash_reports()
    everything = sum(p.stat().st_size for p in args.logs.rglob('*') if p.is_file())
    print(f'Diagnostics added: {size(collected)}; {args.logs} now holds {size(everything)}')
except Exception as exc:  # diagnostics must never fail the job
    print(f'::warning::collect-diagnostics.py: {type(exc).__name__}: {exc}', file=sys.stderr)
