"""Execute the production Bash launcher; NUL output preserves argv boundaries."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / 'windows-integration-test.sh'


class LaunchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="launch ' fixture ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.marker = self.root / 'invoked'
        for name in ('docker', 'curl', 'wget', 'lsusb'):
            stub = self.bin / name
            stub.write_text('#!/bin/bash\nprintf invoked >> "$INVOCATION_MARKER"\nexit 99\n')
            stub.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith('QUICK_BLUE_')}
        self.env.update(PATH=f'{self.bin}:' + self.env['PATH'],
                        INVOCATION_MARKER=str(self.marker),
                        QUICK_BLUE_WINDOWS_WORK_DIR=str(self.root / "state ' dir"))

    def run_launch(self, **overrides):
        env = self.env | overrides
        result = subprocess.run(['bash', str(SCRIPT), '--dry-run'], env=env,
                                capture_output=True)
        self.assertFalse(self.marker.exists(), 'Docker/download/USB discovery invoked')
        self.assertFalse(Path(env['QUICK_BLUE_WINDOWS_WORK_DIR']).exists())
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertTrue(result.stdout.endswith(b'\0'))
        return result.stdout[:-1].decode().split('\0')

    def test_default_ports(self):
        args = self.run_launch()
        self.assertEqual([args[i + 1] for i, a in enumerate(args) if a == '-p'],
                         ['127.0.0.1:8006:8006/tcp', '127.0.0.1:3389:3389/tcp',
                          '127.0.0.1:3389:3389/udp'])
        self.assertEqual(args[:2], ['docker', 'run'])
        self.assertEqual(args[-1], 'dockurr/windows:latest')

    def test_explicit_remote_opt_in(self):
        args = self.run_launch(QUICK_BLUE_WINDOWS_BIND_ADDRESS='0.0.0.0',
                               QUICK_BLUE_WINDOWS_ALLOW_REMOTE='1')
        self.assertIn('0.0.0.0:3389:3389/udp', args)

    def test_remote_requires_opt_in(self):
        for address in ('0.0.0.0', '192.0.2.1', '::', 'localhost:1234'):
            with self.subTest(address=address):
                result = subprocess.run(['bash', str(SCRIPT), '--dry-run'],
                    env=self.env | {'QUICK_BLUE_WINDOWS_BIND_ADDRESS': address},
                    capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.marker.exists())

    def test_quoted_overrides_and_no_reset(self):
        args = self.run_launch(QUICK_BLUE_WINDOWS_RESET='1',
            QUICK_BLUE_WINDOWS_CONTAINER="name ' with spaces",
            QUICK_BLUE_WINDOWS_IMAGE='custom/image:tag', QUICK_BLUE_WINDOWS_MEMORY='12G',
            QUICK_BLUE_WINDOWS_CPU_CORES='6', QUICK_BLUE_WINDOWS_DISK_SIZE='256G',
            QUICK_BLUE_WINDOWS_VERSION='10', QUICK_BLUE_WINDOWS_WEB_PORT='18006',
            QUICK_BLUE_WINDOWS_RDP_PORT='13389')
        for value in ("name ' with spaces", 'RAM_SIZE=12G', 'CPU_CORES=6',
                      'DISK_SIZE=256G', 'VERSION=10', '127.0.0.1:18006:8006/tcp',
                      str(self.root / "state ' dir/storage") + ':/storage'):
            self.assertIn(value, args)
        self.assertEqual(args[-1], 'custom/image:tag')

    def test_usb_explicit_coordinates_without_discovery(self):
        args = self.run_launch(QUICK_BLUE_WINDOWS_USB_VENDOR_ID='0x0bda',
            QUICK_BLUE_WINDOWS_USB_PRODUCT_ID='0x8771', QUICK_BLUE_WINDOWS_USB_BUS='001',
            QUICK_BLUE_WINDOWS_USB_DEVICE='014')
        self.assertIn('/dev/bus/usb/001/014:/dev/bus/usb/001/014', args)
        self.assertIn('ARGUMENTS=-device usb-host,hostbus=1,hostaddr=14', args)


    def test_reset_preserves_existing_storage(self):
        storage = Path(self.env['QUICK_BLUE_WINDOWS_WORK_DIR']) / 'storage'
        storage.mkdir(parents=True)
        sentinel = storage / 'data.img'
        sentinel.write_text('preserve me')
        result = subprocess.run(['bash', str(SCRIPT), '--dry-run'],
            env=self.env | {'QUICK_BLUE_WINDOWS_RESET': '1'}, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(sentinel.read_text(), 'preserve me')
        self.assertEqual(list(storage.parent.iterdir()), [storage])
        self.assertFalse(self.marker.exists())

    def test_production_remote_gate_before_docker(self):
        result = subprocess.run(['bash', str(SCRIPT)],
            env=self.env | {'QUICK_BLUE_WINDOWS_BIND_ADDRESS': '0.0.0.0'},
            capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn(b'ALLOW_REMOTE=1', result.stderr)
        self.assertFalse(self.marker.exists())

    def test_quoted_repository_path(self):
        script = self.root / "repo ' quoted/scripts/windows-integration-test.sh"
        script.parent.mkdir(parents=True)
        script.write_bytes(SCRIPT.read_bytes())
        result = subprocess.run(['bash', str(script), '--dry-run'],
                                env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertIn(str(script.parent.parent) + ':/shared',
                      result.stdout[:-1].decode().split('\0'))
        self.assertFalse(self.marker.exists())


if __name__ == '__main__':
    unittest.main()
