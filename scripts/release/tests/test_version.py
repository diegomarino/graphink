"""Unit tests for scripts/release/version.py. Run: python3 -m unittest discover -s scripts/release/tests"""
import datetime
import io
import pathlib
import sys
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import version  # noqa: E402

UTC = datetime.timezone.utc


def at(text):
    return datetime.datetime.fromisoformat(text.replace('Z', '+00:00'))


class NextVersion(unittest.TestCase):
    def test_no_tags_starts_current_month_at_zero(self):
        self.assertEqual(version.next_version([], at('2026-11-15T12:00:00Z')), '2026.11.0')

    def test_same_month_increments(self):
        tags = ['v2026.11.0', 'v2026.11.1', 'v2026.10.4']
        self.assertEqual(version.next_version(tags, at('2026-11-20T09:00:00Z')), '2026.11.2')

    def test_month_rollover_resets_counter(self):
        self.assertEqual(version.next_version(['v2026.11.3'], at('2026-12-02T10:00:00Z')), '2026.12.0')

    def test_year_rollover(self):
        self.assertEqual(version.next_version(['v2026.12.1'], at('2027-01-05T10:00:00Z')), '2027.1.0')

    def test_counter_compares_numerically(self):
        self.assertEqual(version.next_version(['v2026.11.9', 'v2026.11.10'], at('2026-11-30T10:00:00Z')), '2026.11.11')

    def test_malformed_tags_are_ignored(self):
        tags = ['v2026.11.05', 'v2026.011.1', '2026.11.7', 'v2026.11', 'v2026.13.0', 'v2026.11.1-rc.1',
                'v1999.1.0', 'release-2026.11.4', 'v2026.11.2 ', 'latest']
        # Only 'v2026.11.2 ' survives (surrounding whitespace is stripped).
        self.assertEqual(version.next_version(tags, at('2026-11-15T12:00:00Z')), '2026.11.3')
        self.assertEqual(version.next_version(['v2026.11.05', 'nightly'], at('2026-11-15T12:00:00Z')), '2026.11.0')

    def test_madrid_midnight_month_edge(self):
        # 2026-11-30 23:30 UTC is already 2026-12-01 00:30 in Madrid (CET, UTC+1).
        self.assertEqual(version.next_version(['v2026.11.2'], at('2026-11-30T23:30:00Z')), '2026.12.0')
        # One hour earlier it is still November in Madrid.
        self.assertEqual(version.next_version(['v2026.11.2'], at('2026-11-30T22:30:00Z')), '2026.11.3')

    def test_madrid_summer_time_edge(self):
        # 2026-07-31 22:30 UTC is 2026-08-01 00:30 in Madrid (CEST, UTC+2).
        self.assertEqual(version.next_version(['v2026.7.0'], at('2026-07-31T22:30:00Z')), '2026.8.0')
        self.assertEqual(version.next_version(['v2026.7.0'], at('2026-07-31T21:30:00Z')), '2026.7.1')

    def test_tag_newer_than_today_is_an_error(self):
        with self.assertRaises(ValueError):
            version.next_version(['v2026.12.0'], at('2026-11-15T12:00:00Z'))


class CurrentVersion(unittest.TestCase):
    def test_latest_tag_without_v(self):
        self.assertEqual(version.current_version(['v2026.10.1', 'v2026.11.0', 'junk'], at('2026-12-15T12:00:00Z')), '2026.11.0')

    def test_no_tags_uses_this_month_in_madrid(self):
        self.assertEqual(version.current_version([], at('2026-11-30T23:30:00Z')), '2026.12.0')
        self.assertEqual(version.current_version(['v2026.11.07'], at('2026-11-15T12:00:00Z')), '2026.11.0')


class CommandLine(unittest.TestCase):
    def run_main(self, *args, tags=''):
        stdin, out = sys.stdin, io.StringIO()
        sys.stdin = io.StringIO(tags)
        try:
            with redirect_stdout(out):
                status = version.main(list(args))
        finally:
            sys.stdin = stdin
        return status, out.getvalue().strip()

    def test_next_reads_tags_and_now(self):
        self.assertEqual(self.run_main('next', '--tags', '-', '--now', '2026-11-15T10:00:00Z', tags='v2026.11.0\nfoo\n'), (0, '2026.11.1'))

    def test_from_tag(self):
        self.assertEqual(self.run_main('from-tag', 'v2026.11.3'), (0, '2026.11.3'))
        for bad in ('2026.11.3', 'v2026.11.03', 'v2026.11.3-rc1', 'v2026.0.1'):
            self.assertEqual(self.run_main('from-tag', bad)[0], 1)

    def test_current(self):
        self.assertEqual(self.run_main('current', '--tags', '-', '--now', '2026-11-15T10:00:00Z', tags='v2026.10.2'), (0, '2026.10.2'))

    def test_latest_tag(self):
        self.assertEqual(self.run_main('latest-tag', '--tags', '-', tags='v2026.10.3 v2026.11.0 bogus'), (0, 'v2026.11.0'))
        self.assertEqual(self.run_main('latest-tag', '--tags', '-', tags='bogus'), (0, ''))


if __name__ == '__main__':
    unittest.main()
