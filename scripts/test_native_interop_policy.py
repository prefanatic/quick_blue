"""Regression gates for the bounded Android native transport."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeInteropPolicyTest(unittest.TestCase):
    def test_generator_is_pinned_across_backends(self):
        for package in ('quick_blue', 'quick_blue_darwin', 'quick_blue_windows'):
            with self.subTest(package=package):
                self.assertIn('pigeon: 30.0.2', (ROOT / package / 'pubspec.yaml').read_text())

    def test_native_schema_is_sync_only(self):
        path = ROOT / 'quick_blue/pigeons/availability.dart'
        self.assertTrue(path.is_file(), 'bounded native availability schema is missing')
        schema = path.read_text()
        self.assertIn('useJni: true', schema)
        self.assertIn('bool isBluetoothAvailable();', schema)
        self.assertNotIn('@async', schema)
        self.assertNotIn('@FlutterApi', schema)
        self.assertNotIn('@EventChannelApi', schema)


if __name__ == '__main__':
    unittest.main()
