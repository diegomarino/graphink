"""Unit tests for scripts/release/notes.py. Run: python3 -m unittest discover -s scripts/release/tests

git-cliff is stubbed; set GIT_CLIFF to a git-cliff binary to also run the end-to-end case."""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import notes  # noqa: E402

TEMPLATE = (HERE.parent / 'release-notes-template.html').read_text(encoding='utf-8')
CLIFF = """### Added

- Paper presets
"""


class Repo:
    def __init__(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.dir.name)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.email', 't@example.com')
        self.git('config', 'user.name', 'T')
        self.git('config', 'tag.gpgSign', 'false')
        self.git('config', 'commit.gpgSign', 'false')
        shutil.copy(HERE.parents[2] / 'cliff.toml', self.root / 'cliff.toml')

    def git(self, *args):
        env = dict(os.environ, GIT_COMMITTER_DATE='2026-11-10T12:00:00+01:00', GIT_AUTHOR_DATE='2026-11-10T12:00:00+01:00')
        return subprocess.run(['git', *args], cwd=self.root, capture_output=True, text=True, check=True, env=env).stdout

    def commit(self, message):
        self.git('commit', '-q', '--allow-empty', '-m', message)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')


class Stub:
    def __init__(self, output=CLIFF):
        self.output, self.calls = output, []

    def __call__(self, *args):
        self.calls.append(args)
        return self.output


class Notes(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()
        self.addCleanup(self.repo.dir.cleanup)
        self.repo.commit('Initial import')

    def test_override_wins_over_git_cliff(self):
        self.repo.write('release-notes/2026.11.0.md', '### Fixed\n\n- Hand-written fix\n')
        stub = Stub()
        self.assertEqual(notes.notes('2026.11.0', [], stub, self.repo.root), ('override', '### Fixed\n\n- Hand-written fix'))
        self.assertEqual(stub.calls, [])

    def test_unreleased_version_uses_unreleased_commits(self):
        stub = Stub()
        self.assertEqual(notes.notes('2026.11.1', ['v2026.11.0'], stub, self.repo.root), ('git-cliff', CLIFF.strip()))
        self.assertEqual(stub.calls, [('--unreleased', '--tag', 'v2026.11.1')])

    def test_published_version_uses_range_from_previous_valid_tag(self):
        stub = Stub()
        self.repo.git('tag', 'v2026.10.2')
        self.repo.commit('feat: x')
        self.repo.git('tag', 'v2026.11.0')
        notes.generated('2026.11.0', ['v2026.10.2', 'v2026.11.0', 'v2026.10.07', 'nightly'], stub, self.repo.root)
        self.assertEqual(stub.calls, [('v2026.10.2..v2026.11.0',)])

    def test_first_published_version_starts_at_the_root_commit(self):
        stub = Stub()
        self.repo.commit('feat: x')
        self.repo.git('tag', 'v2026.11.0')
        root = self.repo.git('rev-list', '--max-parents=0', 'HEAD').strip()
        notes.generated('2026.11.0', ['v2026.11.0'], stub, self.repo.root)
        self.assertEqual(stub.calls, [(f'{root}..v2026.11.0',)])

    def test_check_release(self):
        self.assertEqual(notes.check_release('2026.11.0', [], Stub(), self.repo.root), 'git-cliff')
        self.assertIsNone(notes.check_release('2026.11.0', [], Stub(''), self.repo.root))
        self.repo.write('release-notes/2026.11.0.md', '> **DRAFT** for review.\n\n### Added\n\n- Presets\n')
        with self.assertRaisesRegex(notes.NotesError, 'DRAFT'):
            notes.check_release('2026.11.0', [], Stub(''), self.repo.root)
        self.repo.write('release-notes/2026.11.0.md', '### Added\n\n- Presets\n')
        self.assertEqual(notes.check_release('2026.11.0', [], Stub(''), self.repo.root), 'override')

    def test_unknown_group_is_refused(self):
        with self.assertRaises(notes.NotesError):
            notes.parse('### Changed\n\n- x\n', 'test')

    def test_command_line_and_agent_skill_groups(self):
        other, groups = notes.parse('### Command line\n\n- `graphink render` exports\n\n### Agent skill\n\n- Install steps\n', 'test')
        self.assertEqual((other, groups['Command line'], groups['Agent skill']), ([], ['`graphink render` exports'], ['Install steps']))
        self.repo.write('release-notes/2026.11.0.md', '### Agent skill\n\n- Only the skill changed\n')
        self.assertEqual(notes.check_release('2026.11.0', [], Stub(''), self.repo.root), 'override')


class Html(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()
        self.addCleanup(self.repo.dir.cleanup)
        self.repo.commit('Initial import')

    def page(self, stub=None):
        return notes.render(TEMPLATE, notes.published_versions(self.repo.root), stub or Stub(), self.repo.root, warn=lambda m: None)

    def test_only_published_tags_newest_first(self):
        self.repo.commit('feat: a')
        self.repo.git('tag', 'v2026.10.0')
        self.repo.commit('feat: b')
        self.repo.git('tag', '-a', 'v2026.11.0', '-m', 'Graphink 2026.11.0')
        self.repo.git('tag', 'v2026.11.01')  # malformed: ignored
        self.repo.write('release-notes/2026.11.0.md', '### Fixed\n\n- Hand-written `File > New` fix\n')
        self.repo.write('release-notes/2026.12.0.md', '### Added\n\n- Not published yet\n')
        page = self.page()
        self.assertLess(page.index('Graphink 2026.11.0'), page.index('Graphink 2026.10.0'))
        self.assertIn('<code>File &gt; New</code>', page)
        self.assertIn('2026-11-10', page)
        self.assertNotIn('Not published yet', page)
        self.assertNotIn('2026.11.01', page)
        self.assertIn('<title>Graphink Release Notes</title>', page)
        self.assertNotIn('GraphSketcher', page)

    def test_in_app_notes_show_command_line_but_not_agent_skill(self):
        self.repo.git('tag', 'v2026.11.0')
        stub = Stub('### Added\n\n- Presets\n\n### Command line\n\n- A `graphink` tool\n\n### Agent skill\n\n- A skill\n')
        page = self.page(stub)
        self.assertIn('<h3>Command line</h3>', page)
        self.assertIn('A <code>graphink</code> tool', page)
        self.assertNotIn('Agent skill', page)
        self.assertNotIn('A skill', page)

    def test_deterministic(self):
        self.repo.git('tag', 'v2026.11.0')
        self.assertEqual(self.page(), self.page())

    def test_unmerged_tags_are_not_published_for_this_build(self):
        self.repo.git('switch', '-q', '-c', 'other')
        self.repo.commit('feat: elsewhere')
        self.repo.git('tag', 'v2026.11.0')
        self.repo.git('switch', '-q', 'main')
        self.assertIn('No version has been published yet', self.page())

    def test_missing_git_cliff_links_github(self):
        self.repo.git('tag', 'v2026.11.0')

        def unavailable(*args):
            raise notes.NotesError('git-cliff is not installed')
        page = self.page(unavailable)
        self.assertIn('https://github.com/diegomarino/graphink/releases/tag/v2026.11.0', page)

    def test_light_and_dark_styles_are_readable(self):
        # Help > Release Notes follows the system appearance: the page must opt in to both
        # schemes and keep text and links at WCAG AA contrast (4.5:1) on both of its backgrounds.
        self.repo.git('tag', 'v2026.11.0')
        page = self.page()
        self.assertRegex(page, r'<meta name="color-scheme" content="light dark">')

        def colors(block):
            return dict(re.findall(r'--([a-z]+):\s*(#[0-9a-f]{6})', block))
        light = colors(re.search(r':root \{(.*?)\}', page, re.S).group(1))
        dark = colors(re.search(r'@media \(prefers-color-scheme: dark\) \{\s*:root \{(.*?)\}', page, re.S).group(1))
        for rule in (r'html \{[^}]*background: var\(--bg\);[^}]*color: var\(--text\)', r'section \{[^}]*background: var\(--surface\)', r'\ba \{ color: var\(--accent\)'):
            self.assertRegex(page, rule)

        def luminance(hex_color):
            channels = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
            r, g, b = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
            return 0.2126 * r + 0.7152 * g + 0.0722 * b

        def contrast(a, b):
            high, low = sorted((luminance(a), luminance(b)), reverse=True)
            return (high + 0.05) / (low + 0.05)
        for scheme, palette in (('light', light), ('dark', dark)):
            self.assertLessEqual({'bg', 'surface', 'text', 'muted', 'accent'}, set(palette), scheme)
            for background in ('bg', 'surface'):
                for foreground in ('text', 'muted', 'accent'):
                    with self.subTest(scheme=scheme, foreground=foreground, background=background):
                        self.assertGreaterEqual(contrast(palette[foreground], palette[background]), 4.5)
        self.assertLess(luminance(dark['bg']), luminance(light['bg']) / 4, 'the dark page background is dark')


@unittest.skipUnless(os.environ.get('GIT_CLIFF'), 'set GIT_CLIFF to run git-cliff end to end')
class EndToEnd(unittest.TestCase):
    def test_real_git_cliff(self):
        repo = Repo()
        self.addCleanup(repo.dir.cleanup)
        repo.commit('Legacy commit without a type')
        repo.commit('feat: add A4 presets')
        repo.git('tag', 'v2026.11.0')
        repo.commit('fix(export): keep PNG resolution')
        repo.commit('docs: hidden')
        repo.commit('feat(cli): add graphink render')
        repo.commit('fix(skill): find the tool in ~/Applications')
        repo.commit('test(cli): hidden too')
        repo.commit('docs(skill): hidden as well')
        cliff = lambda *args: notes.git_cliff(*args, root=repo.root)
        other, groups = notes.parse(notes.notes('2026.11.1', ['v2026.11.0'], cliff, repo.root)[1], 'git-cliff')
        self.assertEqual((other, {name: items for name, items in groups.items() if items}),
                         ([], {'Fixed': ['Keep PNG resolution'], 'Command line': ['Add graphink render'],
                               'Agent skill': ['Find the tool in ~/Applications']}))
        self.assertEqual(notes.notes('2026.11.0', ['v2026.11.0'], cliff, repo.root)[1], '### Added\n\n- Add A4 presets')
        self.assertIsNone(notes.check_release('2026.11.2', ['v2026.11.0'], lambda *a: '', repo.root))


if __name__ == '__main__':
    unittest.main()
