#!/usr/bin/env python3
"""The Homebrew casks in diegomarino/homebrew-tap, for release.yml.

Casks/graphink-app.rb installs Graphink.dmg and moves with every release. Casks/graphink-cli.rb
installs graphink-cli.zip and moves only when the tool's content changed against the zip the cask
points to now (cli_zip.py compare with the release named by its version, which need not be the
previous release: an earlier homebrew job may have been off or failed); otherwise it stays, so
`brew upgrade` offers nothing. Both casks hold one `version "..."` and one `sha256 "..."` line, and
their url interpolates the version.

    casks.py previous TAG                 the newest published release tag older than TAG, from the
                                          tags on stdin (one per line); nothing if there is none
    casks.py cli-version --tap DIR        the version graphink-cli.rb points to
    casks.py update --tap DIR --version V --dist DIST --cli changed|unchanged
                                          set version and sha256 of graphink-app.rb from
                                          DIST/Graphink.dmg.sha256, and of graphink-cli.rb from
                                          DIST/graphink-cli.zip.sha256 when --cli is changed (the result
                                          of comparing the new zip with cli-version's); print what changed
"""
import argparse
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import version as versions  # noqa: E402


class CaskError(Exception):
    pass


def previous(tag, tags):
    target = versions.parse_tag(tag)
    if not target:
        raise CaskError(f'{tag} is not a release tag vYYYY.M.n')
    older = [t.strip() for t in tags if versions.parse_tag(t) and versions.parse_tag(t) < target]
    return max(older, key=versions.parse_tag) if older else None


def cask_value(path, key):
    """The value of the one `key "..."` line of a cask."""
    values = re.findall(rf'^\s*{key}\s+"([^"]*)"$', path.read_text(), re.M)
    if len(values) != 1:
        raise CaskError(f'{path} must have exactly one {key} "..." line')
    return values[0]


def cli_version(tap):
    version = cask_value(tap / 'Casks' / 'graphink-cli.rb', 'version')
    if not versions.parse_tag(f'v{version}'):
        raise CaskError(f'graphink-cli.rb points to {version!r}, not a version YYYY.M.n')
    return version


def sha256_of(path):
    match = re.fullmatch(r'([0-9a-f]{64})  \S+\n?', path.read_text())
    if not match:
        raise CaskError(f'{path} is not one shasum -a 256 line')
    return match.group(1)


def set_cask(path, version, sha256):
    """Rewrite the version and sha256 lines of a cask; True if it changed."""
    text = path.read_text()
    for key, value in (('version', version), ('sha256', sha256)):
        pattern = re.compile(rf'^(\s*{key}\s+)"[^"]*"$', re.M)
        if len(pattern.findall(text)) != 1:
            raise CaskError(f'{path} must have exactly one {key} "..." line')
        text = pattern.sub(lambda m, value=value: f'{m.group(1)}"{value}"', text)
    changed = text != path.read_text()
    path.write_text(text)
    return changed


def update(tap, version, dist, cli):
    if not versions.parse_tag(f'v{version}'):
        raise CaskError(f'{version} is not a version YYYY.M.n')
    if cli not in ('changed', 'unchanged'):
        raise CaskError(f'--cli must be changed or unchanged, not {cli!r}')
    casks = tap / 'Casks'
    report = []
    if set_cask(casks / 'graphink-app.rb', version, sha256_of(dist / 'Graphink.dmg.sha256')):
        report.append(f'graphink-app {version}')
    if cli == 'changed' and set_cask(casks / 'graphink-cli.rb', version, sha256_of(dist / 'graphink-cli.zip.sha256')):
        report.append(f'graphink-cli {version}')
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('previous').add_argument('tag')
    sub.add_parser('cli-version').add_argument('--tap', required=True, type=pathlib.Path)
    up = sub.add_parser('update')
    up.add_argument('--tap', required=True, type=pathlib.Path)
    up.add_argument('--version', required=True)
    up.add_argument('--dist', required=True, type=pathlib.Path)
    up.add_argument('--cli', required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == 'previous':
            found = previous(args.tag, sys.stdin.read().split())
            if found:
                print(found)
        elif args.command == 'cli-version':
            print(cli_version(args.tap))
        else:
            for line in update(args.tap, args.version, args.dist, args.cli) or ['no cask changed']:
                print(line)
    except (CaskError, OSError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
