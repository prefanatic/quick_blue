"""Hermetic argv/proof-boundary tests, not ARM64 execution evidence."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('arm64', Path(__file__).with_name('check-arm64-consumer.py'))
if spec is None or spec.loader is None:
    raise RuntimeError('Cannot load ARM64 verifier')
arm64 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(arm64)


class Arm64ConsumerTest(unittest.TestCase):
    def exercise(self, emulator=False, header='AArch64'):
        with tempfile.TemporaryDirectory() as directory:
            cli = Path(directory)
            (cli / 'resolved-manifests.json').write_text('{}')
            args = ['check', '--dart', '/standalone/dart', '--cli', directory]
            if emulator:
                args += ['--qemu', '/tools/qemu-aarch64', '--sysroot', '/arm64']
            calls = []

            def run(argv, cwd, env):
                self.assertNotIn('DISPLAY', env)
                self.assertNotIn('WAYLAND_DISPLAY', env)
                self.assertNotIn('LD_LIBRARY_PATH', env)
                calls.append([str(x) for x in argv])
                if '--version' in argv:
                    return 'Dart SDK version: 3.13.5'
                if '-h' in argv:
                    return header
                return ''

            with patch('sys.argv', args), patch.object(arm64, 'run', side_effect=run):
                arm64.main()
            return calls, json.loads((cli / 'build/arm64-result.json').read_text())

    def test_cross_build_never_claims_execution(self):
        calls, result = self.exercise()
        self.assertEqual(result['runtime'], 'not executed')
        self.assertEqual(result['hardware'], 'not executed')
        compiles = [call for call in calls if 'compile' in call]
        self.assertEqual(len(compiles), 3)
        self.assertTrue(all('--target-arch=arm64' in call for call in compiles))

    def test_emulator_checks_help_fake_and_loader_separately(self):
        calls, result = self.exercise(True)
        guests = [call for call in calls if '-L' in call]
        self.assertEqual(len(guests), 3)
        self.assertEqual(guests[0][-1], '--help')
        self.assertTrue(guests[1][-1].endswith('fake_flow-arm64'))
        self.assertTrue(guests[2][-1].endswith('native_libraries-arm64'))
        self.assertIn('loader-only', result['runtime'])
        self.assertEqual(result['hardware'], 'not executed')

    def test_wrong_elf_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'AArch64'):
            self.exercise(header='X86-64')

    def test_partial_emulator_configuration_is_rejected(self):
        with patch('sys.argv', ['check', '--dart', '/dart', '--cli', '/cli', '--qemu', '/qemu']):
            with self.assertRaises(SystemExit) as error:
                arm64.main()
        self.assertEqual(error.exception.code, 2)


if __name__ == '__main__':
    unittest.main()
