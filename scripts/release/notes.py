#!/usr/bin/env python3
"""Release notes from git tags: git-cliff over the history, or release-notes/<version>.md.

A version's notes are release-notes/<version>.md when that file exists (hand-written; it wins).
Otherwise git-cliff (cliff.toml) generates them from the feat/fix/perf commits between the
previous release tag and v<version>. No changelog file is committed.

    notes.py check-release --version V   can V be released? exit 3 when it has no notes
                                         (no feat/fix/perf commits since the last tag and no
                                         override file); exit 1 when the override is a DRAFT
    notes.py version-notes --version V   the Markdown notes of V (GitHub release body)
    notes.py html --output PATH          the in-app release notes (MessageOfTheDay.html) of every
                                         published version reachable from HEAD, newest first.
                                         Run by the app's "Generate Release Notes" build phase.
                                         No timestamps: the file changes only with a release.

git-cliff is found through $GIT_CLIFF or PATH. Without it, `html` still succeeds and links a
version's notes on GitHub instead (CI always installs it); the other commands fail.
"""
import argparse
import html
import os
import pathlib
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import version as versions  # noqa: E402

ROOT = HERE.parents[1]
GROUPS = ('Added', 'Fixed', 'Improved')
RELEASES_URL = 'https://github.com/diegomarino/graphink/releases'
NOTHING_TO_RELEASE = 3


class NotesError(Exception):
    pass


def git(*args, root=ROOT):
    return subprocess.run(['git', *args], cwd=root, capture_output=True, text=True, check=True).stdout


def git_cliff(*args, root=ROOT):
    binary = os.environ.get('GIT_CLIFF') or shutil.which('git-cliff')
    if not binary:
        raise NotesError('git-cliff is not installed (set GIT_CLIFF or add it to PATH)')
    return subprocess.run([binary, '--config', str(root / 'cliff.toml'), *args], cwd=root,
                          capture_output=True, text=True, check=True).stdout


def parse(body, where):
    """(paragraph lines, {group: [bullets]}) from Markdown notes; rejects unknown groups."""
    other, groups, group = [], {name: [] for name in GROUPS}, None
    for line in body.splitlines():
        if line.startswith('### '):
            group = line[4:].strip()
            if group not in GROUPS:
                raise NotesError(f'{where}: unknown group "### {group}" (use {", ".join(GROUPS)})')
        elif line.startswith('- '):
            if group is None:
                raise NotesError(f'{where}: bullet outside Added/Fixed/Improved: {line!r}')
            groups[group].append(line[2:].strip())
        elif line.startswith('  ') and line.strip() and group and groups[group]:
            groups[group][-1] += ' ' + line.strip()
        elif line.strip():
            if group is not None:
                raise NotesError(f'{where}: only bullets may follow "### {group}": {line!r}')
            other.append(line.strip())
    return other, groups


def is_draft(text):
    return re.search(r'\bDRAFT\b', text) is not None


def override(version, root=ROOT):
    path = root / 'release-notes' / f'{version}.md'
    return path.read_text(encoding='utf-8').strip() if path.is_file() else None


def generated(version, tags, cliff=git_cliff, root=ROOT):
    """git-cliff notes for v<version>: an existing tag's range, or the unreleased commits."""
    tag = f'v{version}'
    target = versions.parse_tag(tag)
    older = [t for t in tags if (p := versions.parse_tag(t)) and p < target]
    previous = max(older, key=versions.parse_tag) if older else None
    if tag in tags:
        start = previous or git('rev-list', '--max-parents=0', tag, root=root).split()[-1]
        return cliff(f'{start}..{tag}').strip()
    return cliff('--unreleased', '--tag', tag).strip()


def notes(version, tags, cliff=git_cliff, root=ROOT):
    """(source, Markdown) for a version: the override file if any, else git-cliff."""
    text = override(version, root)
    if text is not None:
        return 'override', text
    return 'git-cliff', generated(version, tags, cliff, root)


def has_entries(text, where):
    return any(parse(text, where)[1].values())


def check_release(version, tags, cliff=git_cliff, root=ROOT):
    source, text = notes(version, tags, cliff, root)
    if source == 'override' and is_draft(text):
        raise NotesError(f'release-notes/{version}.md is still marked DRAFT; review it and remove the DRAFT note first')
    return source if has_entries(text, f'{version} ({source})') else None


def inline(text):
    out = html.escape(text, quote=True)
    out = re.sub(r'`([^`]+)`', r'<code>\1</code>', out)
    out = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', out)
    return re.sub(r'\[([^\]]+)\]\((https?://[^)\s]+)\)', r'<a href="\2">\1</a>', out)


def render(template, published, cliff=git_cliff, root=ROOT, warn=print):
    """published: [(version, date)] newest first."""
    tags = [f'v{v}' for v, _ in published]
    parts = []
    for version, date in published:
        parts.append(f'<section>\n<h2>Graphink {html.escape(version)} <span class="date">{html.escape(date)}</span></h2>')
        try:
            _, text = notes(version, tags, cliff, root)
            other, groups = parse(text, version)
        except NotesError as error:
            warn(f'warning: {error}; linking the GitHub release instead')
            other, groups = [], {}
            parts.append(f'<p><a href="{RELEASES_URL}/tag/v{html.escape(version)}">Read the notes for this version on GitHub.</a></p>')
        parts += [f'<p>{inline(line.lstrip("> ").strip())}</p>' for line in other]
        for name in GROUPS:
            if groups.get(name):
                parts.append(f'<h3>{name}</h3>\n<ul>\n' + '\n'.join(f'<li>{inline(i)}</li>' for i in groups[name]) + '\n</ul>')
        parts.append('</section>')
    if not published:
        parts.append(f'<p class="empty">No version has been published yet. Release notes appear here with each new version, and on <a href="{RELEASES_URL}">GitHub</a>.</p>')
    return template.replace('{{RELEASES}}', '\n'.join(parts))


def published_versions(root=ROOT):
    """[(version, YYYY-MM-DD of the tagged commit)] for valid tags merged into HEAD, newest first."""
    tags = git('tag', '--list', '--merged', 'HEAD', root=root).split()
    found = sorted({versions.parse_tag(t) for t in tags if versions.parse_tag(t)}, reverse=True)
    return [('%d.%d.%d' % v, git('log', '-1', '--format=%cs', 'v%d.%d.%d' % v, root=root).strip()) for v in found]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=['check-release', 'version-notes', 'html'])
    parser.add_argument('--version')
    parser.add_argument('--output', type=pathlib.Path)
    parser.add_argument('--template', type=pathlib.Path, default=HERE / 'release-notes-template.html')
    args = parser.parse_args(argv)
    try:
        if args.command == 'html':
            if not args.output:
                parser.error('html needs --output')
            page = render(args.template.read_text(encoding='utf-8'), published_versions(), warn=lambda m: print(m, file=sys.stderr))
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(page, encoding='utf-8')
            return 0
        if not args.version or not versions.parse_tag(f'v{args.version}'):
            parser.error('--version YYYY.M.n is required')
        tags = git('tag', '--list').split()
        if args.command == 'check-release':
            source = check_release(args.version, tags)
            if source is None:
                print(f'No feat/fix/perf commits since the last release and no release-notes/{args.version}.md; nothing to release.')
                return NOTHING_TO_RELEASE
            print(f'{args.version}: notes from {source}')
        else:
            source, text = notes(args.version, tags)
            if source == 'override' and is_draft(text):
                raise NotesError(f'release-notes/{args.version}.md is still marked DRAFT')
            if not has_entries(text, args.version):
                raise NotesError(f'{args.version} has no Added/Fixed/Improved notes')
            print(text)
    except (NotesError, OSError, subprocess.CalledProcessError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
