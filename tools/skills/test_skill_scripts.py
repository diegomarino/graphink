"""Tests for the agent skill's scripts (skills/graphink/scripts). Run: python3 -m unittest discover -s tools/skills

find-graphink.sh with the tool on PATH, with only the app, with neither and on another platform (uname is
simulated, so this also runs on Linux); make-graph.sh's arguments and outputs with a stand-in graphink. The
products tier runs make-graph.sh with the real tool (tools/cli/check-cli.py)."""
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIND = ROOT / 'skills/graphink/scripts/find-graphink.sh'
MAKE = ROOT / 'skills/graphink/scripts/make-graph.sh'

# A stand-in for graphink: --version, and create/render write their -o output (refusing an existing one
# without --force, like the real tool).
FAKE = '''#!/bin/sh
case "$1" in
  --version) echo "graphink 2026.11.0 (build 1)"; exit 0 ;;
  create|render) ;;
  *) exit 2 ;;
esac
out='' force=no
while [ $# -gt 0 ]; do
  case "$1" in -o) out=$2; shift ;; --force) force=yes ;; esac
  shift
done
if [ -e "$out" ] && [ $force = no ]; then echo "graphink: $out already exists" >&2; exit 1; fi
echo "made by $0" > "$out"
echo "wrote $out"
'''


def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755)
    return path


class Scripts(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.root = pathlib.Path(self.dir.name)
        self.system('Darwin')

    def system(self, name):
        executable(self.root / 'uname/uname', f'#!/bin/sh\necho {name}\n')

    def run_script(self, script, *args, path=(), apps=None, cwd=None):
        env = {'HOME': str(self.root / 'home'), 'PATH': os.pathsep.join([*map(str, path), str(self.root / 'uname'), '/usr/bin', '/bin'])}
        env['GRAPHINK_APP_DIRS'] = str(apps) if apps else ''
        return subprocess.run(['/bin/sh', str(script), *map(str, args)], capture_output=True, text=True, env=env, cwd=cwd, timeout=60)

    def app(self, broken=False):
        apps = self.root / 'Applications'
        executable(apps / 'Graphink.app/Contents/Helpers/graphink', '#!/bin/sh\nexit 1\n' if broken else FAKE)
        return apps

    def test_tool_on_path(self):
        tool = executable(self.root / 'bin/graphink', FAKE)
        proc = self.run_script(FIND, path=[tool.parent], apps=self.app())
        self.assertEqual((proc.returncode, proc.stdout), (0, f'{tool}\n'))

    def test_only_the_app(self):
        apps = self.app()
        proc = self.run_script(FIND, apps=apps)
        self.assertEqual((proc.returncode, proc.stdout), (0, f'{apps}/Graphink.app/Contents/Helpers/graphink\n'))
        proc = self.run_script(FIND, '--version', apps=apps)
        self.assertEqual(proc.returncode, 0)
        self.assertIn('graphink 2026.11.0', proc.stderr)

    def test_a_tool_that_does_not_run_is_skipped(self):
        broken = executable(self.root / 'bin/graphink', '#!/bin/sh\nexit 1\n')
        apps = self.app()
        proc = self.run_script(FIND, path=[broken.parent], apps=apps)
        self.assertEqual((proc.returncode, proc.stdout), (0, f'{apps}/Graphink.app/Contents/Helpers/graphink\n'))

    def test_neither(self):
        proc = self.run_script(FIND, apps=self.app(broken=True))
        self.assertEqual((proc.returncode, proc.stdout), (3, ''))
        for step in ('brew install --cask diegomarino/tap/graphink-cli', 'Install Command-Line Tool', 'releases/latest', 'graphink-cli.zip'):
            self.assertIn(step, proc.stderr)

    def test_not_a_mac(self):
        self.system('Linux')
        tool = executable(self.root / 'bin/graphink', FAKE)
        proc = self.run_script(FIND, path=[tool.parent], apps=self.app())
        self.assertEqual((proc.returncode, proc.stdout), (4, ''))
        self.assertIn('needs a Mac', proc.stderr)
        self.assertIn('issues/8', proc.stderr)

    def test_find_arguments(self):
        self.assertEqual(self.run_script(FIND, '--bogus').returncode, 2)
        self.assertEqual(self.run_script(FIND, '--help').returncode, 0)

    def test_make_graph(self):
        tool = executable(self.root / 'bin/graphink', FAKE)
        spec = self.root / 'work/plot.json'
        spec.parent.mkdir()
        spec.write_text('{}')
        proc = self.run_script(MAKE, spec, path=[tool.parent])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.split(), [f'{spec.parent}/plot.{ext}' for ext in ('graphink', 'png', 'pdf')])
        self.assertTrue(all(pathlib.Path(p).is_file() for p in proc.stdout.split()))
        # Existing outputs: refused before anything is written, replaced with --force.
        (spec.parent / 'plot.png').write_text('keep')
        (spec.parent / 'plot.graphink').unlink()
        proc = self.run_script(MAKE, spec, path=[tool.parent])
        self.assertEqual(proc.returncode, 1)
        self.assertFalse((spec.parent / 'plot.graphink').exists())
        self.assertEqual((spec.parent / 'plot.png').read_text(), 'keep')
        # --force replaces all three, the kept PNG included, and passes --force to every graphink call.
        proc = self.run_script(MAKE, spec, '--force', path=[tool.parent])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for ext in ('graphink', 'png', 'pdf'):
            self.assertEqual((spec.parent / f'plot.{ext}').read_text(), f'made by {tool}\n', ext)
        proc = self.run_script(MAKE, spec, spec.parent / 'plot', '--force', path=[tool.parent])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stderr.count('wrote '), 3)
        # A new OUT with --force: nothing to replace, still fine.
        self.assertEqual(self.run_script(MAKE, spec, spec.parent / 'other', '--force', path=[tool.parent]).returncode, 0)
        self.assertTrue((spec.parent / 'other.pdf').is_file())

    def test_make_graph_arguments_and_missing_tool(self):
        spec = self.root / 'plot.json'
        spec.write_text('{}')
        self.assertEqual(self.run_script(MAKE).returncode, 2)
        self.assertEqual(self.run_script(MAKE, self.root / 'missing.json').returncode, 2)
        self.assertEqual(self.run_script(MAKE, spec, 'a', 'b').returncode, 2)
        proc = self.run_script(MAKE, spec)
        self.assertEqual(proc.returncode, 3)
        self.assertIn('brew install', proc.stderr)
        self.system('Linux')
        self.assertEqual(self.run_script(MAKE, spec).returncode, 4)
        self.assertFalse((self.root / 'plot.graphink').exists())


if __name__ == '__main__':
    unittest.main()
