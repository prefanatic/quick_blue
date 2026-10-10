"""Executable fixtures consume ci.yml/docs.yml, not a copied filter policy."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from workflow_policy import ROOT, aggregate, documentation_selected, load, matches, selection

PACKAGES = ('quick_blue', 'quick_blue/example', 'quick_blue_darwin', 'quick_blue_linux', 'quick_blue_platform_interface', 'quick_blue_windows')
COMMON = {'Changes', 'Minimum toolchain', 'Format', 'Generated code', 'Publish readiness', 'Docs validation', 'Readiness policy'} | {f'{kind} {p}' for kind in ('Analyze', 'Test') for p in PACKAGES}
NATIVE = {'Darwin type check', 'Build Android', 'Build Linux', 'Build ios', 'Build macos', 'Build windows'}
ALL = COMMON | NATIVE


class SelectionTests(unittest.TestCase):
    def assert_selection(self, paths, expected, docs=False, **kwargs):
        selected, skipped = selection(paths, **kwargs)
        self.assertEqual(selected, expected)
        self.assertEqual(skipped, ALL - expected)
        self.assertEqual(documentation_selected(paths), docs)

    def test_changelog(self):
        for p in PACKAGES:
            with self.subTest(package=p):
                native = {
                    'quick_blue': set(),
                    'quick_blue/example': NATIVE,
                    'quick_blue_darwin': {'Darwin type check', 'Build ios', 'Build macos'},
                    'quick_blue_linux': {'Build Linux'},
                    'quick_blue_platform_interface': NATIVE,
                    'quick_blue_windows': {'Build windows'},
                }
                self.assert_selection([p + '/CHANGELOG.md'], COMMON | native[p])

    def test_docs(self):
        self.assert_selection(['docs/testing.md'], {'Changes'}, docs=True)

    def test_android(self):
        self.assert_selection(['quick_blue/android/src/Plugin.kt'], COMMON | {'Build Android'})

    def test_shared(self):
        self.assert_selection(['quick_blue_platform_interface/lib/api.dart'], ALL)

    def test_workflows(self):
        self.assert_selection(['.github/workflows/ci.yml'], ALL)
        self.assert_selection(['.github/workflows/docs.yml'], ALL, docs=True)

    def test_hosted_skip(self):
        self.assert_selection(['pubspec.yaml'], ALL - {'Build ios', 'Build macos', 'Build windows'}, skip_hosted=True)

    def test_non_pr(self):
        for event in ('push', 'workflow_dispatch'):
            self.assert_selection([], ALL, event=event)

    def test_scripts(self):
        self.assert_selection(['scripts/tool.py'], COMMON)
        self.assert_selection(['scripts/check-linux-consumer.py'], COMMON | {'Build Linux'})

    def test_dependabot(self):
        self.assert_selection(['.github/dependabot.yml'], COMMON)

    def test_glob_subset(self):
        self.assertTrue(matches('CHANGELOG.md', '**/CHANGELOG.md'))
        self.assertTrue(matches('.github/workflows/ci.yml', '.github/workflows/**'))
        with self.assertRaises(ValueError):
            matches('x', '{x,y}')

    def test_minimum_toolchain(self):
        job = load('ci.yml')['jobs']['minimum-toolchain']
        setup = next(s for s in job['steps'] if s.get('uses', '').startswith('subosito/flutter-action@'))
        self.assertEqual(setup['with']['flutter-version'], '3.44.2')
        self.assertEqual(setup['with']['cache'], 'false')
        self.assertIn('runner.temp', job['env']['PUB_CACHE'])
        run = job['steps'][-1]['run']
        for command in ('set -euo pipefail', 'flutter pub get', 'flutter pub deps --json', 'flutter analyze', 'flutter test'):
            self.assertIn(command, run)
        for package in PACKAGES:
            self.assertIn(package, run)

    def test_workflow_invokes_validator(self):
        runs = '\n'.join(s.get('run', '') for s in load('ci.yml')['jobs']['publish-readiness']['steps'])
        self.assertIn('python3 scripts/check-changelog-coverage.py', runs)
        self.assertNotIn('grep -q', runs)


class AggregateTests(unittest.TestCase):
    def test_results(self):
        selected, skipped = selection(['quick_blue/android/src/Plugin.kt'])
        results = {j: 'success' for j in selected} | {j: 'skipped' for j in skipped}
        self.assertEqual(aggregate(selected, skipped, results), 'PASS')
        for job in selected:
            for status, expected in [('failure', 'FAIL'), ('cancelled', 'UNRESOLVED'), ('skipped', 'UNRESOLVED')]:
                with self.subTest(job=job, status=status):
                    self.assertEqual(aggregate(selected, skipped, results | {job: status}), expected)
        with self.assertRaises(ValueError):
            aggregate(selected, skipped, {})

    def test_docs_build_failure_and_deploy_skip(self):
        self.assertEqual(set(load('docs.yml')['jobs']), {'build', 'deploy'})
        self.assertIn("github.event_name != 'pull_request'", load('docs.yml')['jobs']['deploy']['if'])
        self.assertEqual(aggregate({'build'}, {'deploy'}, {'build': 'failure', 'deploy': 'skipped'}), 'FAIL')
        self.assertEqual(aggregate({'build'}, {'deploy'}, {'build': 'success', 'deploy': 'skipped'}), 'PASS')


class ChangelogTests(unittest.TestCase):
    def test_current_version(self):
        self.assertEqual(subprocess.run([sys.executable, str(ROOT / 'scripts/check-changelog-coverage.py')]).returncode, 0)

    def test_missing_heading(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'quick_blue_platform_interface').mkdir()
            (root / 'quick_blue').mkdir()
            (root / 'quick_blue_platform_interface/pubspec.yaml').write_text('version: 1.2.3+test\n')
            for heading, expected in [('## Unreleased', 65), ('## [1.2.3+test]suffix', 65), ('## [1.2.3+test] - today', 0)]:
                (root / 'quick_blue/CHANGELOG.md').write_text(heading + '\n')
                self.assertEqual(subprocess.run([sys.executable, str(ROOT / 'scripts/check-changelog-coverage.py'), '--root', directory]).returncode, expected)


if __name__ == '__main__':
    unittest.main()
