"""Keep the supported Flutter floor, CI pins and consumer recipe aligned.

This is a source-policy check, not SDK execution or hardware verification.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class FlutterSupportPolicyTest(unittest.TestCase):
    def test_flutter_floor_matches_both_ci_lanes_and_consumer(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        match = re.search(r'FLUTTER_VERSION: "(\d+\.\d+\.\d+)"', workflow)
        if match is None:
            self.fail('CI must pin a stable Flutter version')
        version = match.group(1)
        minimum = workflow.split('  minimum-toolchain:', 1)[1].split('  format:', 1)[0]
        self.assertIn(f'flutter-version: "{version}"', minimum)
        for package in ('quick_blue', 'quick_blue/example', 'quick_blue_darwin',
                        'quick_blue_windows', 'quick_blue_linux'):
            with self.subTest(package=package):
                manifest = (ROOT / package / 'pubspec.yaml').read_text()
                self.assertIn(f'flutter: ">={version}"', manifest)
        consumer = (ROOT / 'scripts/check-linux-consumer.py').read_text()
        self.assertIn(f"flutter: '>={version}'", consumer)

    def test_standalone_packages_keep_flutter_free_environment(self):
        for package in ('quick_blue_core', 'quick_blue_platform_interface',
                        'quick_blue_linux_dart', 'quick_blue_linux/example'):
            with self.subTest(package=package):
                manifest = (ROOT / package / 'pubspec.yaml').read_text()
                environment = manifest.split('environment:', 1)[1].split('\n\n', 1)[0]
                self.assertNotIn('flutter:', environment)
                self.assertNotIn('sdk: flutter', manifest)


if __name__ == '__main__':
    unittest.main()
