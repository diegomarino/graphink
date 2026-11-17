#!/usr/bin/env python3
"""Graphink's calendar version (YYYY.M.n) comes from git tags; it is never committed.

The single source of the rules, used by .github/scripts/build.sh and the README build command
(MARKETING_VERSION for every build), scripts/release.sh and the "Release" workflow.

Next release version:

- today is the calendar date in Europe/Madrid;
- the latest valid tag vYYYY.M.n is in the same year and month: n + 1;
- otherwise (older month, or no valid tag): YYYY.M.0 for today.

Build version (what `git describe --tags --match 'v[0-9]*'` finds): the latest valid tag
reachable from HEAD, or YYYY.M.0 for today when there is none. It stays purely numeric; dev
builds differ from the release only by CFBundleVersion.

Tags that are not exactly vYYYY.M.n (year 2000-2099, month 1-12, no zero padding) are ignored.

    version.py next [--now ISO-8601] [--tags FILE]      the next release version (no "v")
    version.py current [--now ISO-8601] [--tags FILE]   the version of a build of HEAD
    version.py latest-tag [--tags FILE]                 the latest valid tag, or nothing
    version.py from-tag TAG                             the version of a release tag, or an error

Without --tags, `next` and `latest-tag` read every tag and `current` reads the tags merged into
HEAD. --now is for tests and takes a timestamp with a UTC offset.
"""
import argparse
import datetime
import re
import subprocess
import sys
from zoneinfo import ZoneInfo

TIME_ZONE = ZoneInfo('Europe/Madrid')
TAG = re.compile(r'^v(20[0-9]{2})\.([1-9]|1[0-2])\.(0|[1-9][0-9]*)$')


def parse_tag(tag):
    match = TAG.match(tag.strip())
    return tuple(int(part) for part in match.groups()) if match else None


def latest(tags):
    versions = [v for v in map(parse_tag, tags) if v]
    return max(versions) if versions else None


def next_version(tags, now):
    """tags: iterable of tag names; now: aware datetime. Returns 'YYYY.M.n'."""
    today = now.astimezone(TIME_ZONE).date()
    newest = latest(tags)
    if newest and newest[:2] > (today.year, today.month):
        raise ValueError(f'Latest tag v{newest[0]}.{newest[1]}.{newest[2]} is newer than today ({today} in Europe/Madrid)')
    if newest and newest[:2] == (today.year, today.month):
        return f'{today.year}.{today.month}.{newest[2] + 1}'
    return f'{today.year}.{today.month}.0'


def current_version(tags, now):
    """Version of a build: the latest valid tag (reachable from HEAD), else this month .0."""
    newest = latest(tags)
    if newest:
        return '%d.%d.%d' % newest
    today = now.astimezone(TIME_ZONE).date()
    return f'{today.year}.{today.month}.0'


def read_tags(path, merged=False):
    if path:
        with (sys.stdin if path == '-' else open(path)) as source:
            return source.read().split()
    command = ['git', 'tag', '--list'] + (['--merged', 'HEAD'] if merged else [])
    return subprocess.run(command, capture_output=True, text=True, check=True).stdout.split()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=['next', 'current', 'latest-tag', 'from-tag'])
    parser.add_argument('tag', nargs='?', help='from-tag: the release tag')
    parser.add_argument('--now', help='ISO-8601 timestamp with a UTC offset (tests only)')
    parser.add_argument('--tags', help='File with one tag per line, or - for stdin (tests only)')
    args = parser.parse_args(argv)
    if args.command == 'from-tag':
        parsed = parse_tag(args.tag or '')
        if not parsed or args.tag != args.tag.strip():
            print(f'error: {args.tag!r} is not a release tag vYYYY.M.n (no zero padding)', file=sys.stderr)
            return 1
        print('%d.%d.%d' % parsed)
        return 0
    tags = read_tags(args.tags, merged=args.command == 'current')
    if args.command == 'latest-tag':
        newest = latest(tags)
        if newest:
            print('v%d.%d.%d' % newest)
        return 0
    now = datetime.datetime.fromisoformat(args.now.replace('Z', '+00:00')) if args.now else datetime.datetime.now(datetime.timezone.utc)
    if now.tzinfo is None:
        parser.error('--now needs a UTC offset')
    if args.command == 'current':
        print(current_version(tags, now))
        return 0
    try:
        print(next_version(tags, now))
    except ValueError as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
