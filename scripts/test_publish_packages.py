"""Release metadata fixtures use a logging Dart stand-in, not publication."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

FACADE_DEPENDENCIES = ("quick_blue_platform_interface", "quick_blue_core", "quick_blue_darwin", "quick_blue_linux", "quick_blue_windows")
PACKAGES = (*FACADE_DEPENDENCIES, "quick_blue_linux_dart", "quick_blue")


class PublishTests(unittest.TestCase):
    def fixture(self, mutate=None, args=()):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            script = root / "scripts/publish-packages.sh"
            shutil.copyfile(Path(__file__).with_name("publish-packages.sh"), script)
            for package in PACKAGES:
                (root / package).mkdir()
                dependencies = FACADE_DEPENDENCIES if package == "quick_blue" else ((PACKAGES[0],) if package != PACKAGES[0] else ())
                if package == "quick_blue_linux":
                    dependencies += ("quick_blue_core", "quick_blue_linux_dart")
                if package == "quick_blue_linux_dart":
                    dependencies += ("quick_blue_core",)
                (root / package / "pubspec.yaml").write_text(
                    f"name: {package}\nversion: 1.2.3\ndependencies:\n" +
                    "".join(f"  {name}: ^1.2.3\n" for name in dependencies))
            if mutate:
                path = root / mutate[0] / "pubspec.yaml"
                path.write_text(path.read_text().replace(mutate[1], mutate[2]))
            binary = root / "bin"
            binary.mkdir()
            dart = binary / "dart"
            dart.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALL_LOG"\n')
            dart.chmod(0o755)
            log = root / "calls"
            result = subprocess.run(["bash", str(script), *args], capture_output=True, text=True,
                                    env=dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"], CALL_LOG=str(log)))
            return result, log.read_text().splitlines() if log.exists() else []

    def test_valid(self):
        result, calls = self.fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 7)
        self.assertTrue(all("publish --dry-run --ignore-warnings" in call for call in calls))

    def test_usage(self):
        for args in (("--bad",), ("--dry-run", "extra")):
            with self.subTest(args=args):
                result, calls = self.fixture(args=args)
                self.assertEqual(result.returncode, 64)
                self.assertIn("Usage:", result.stderr)
                self.assertEqual(calls, [])

    def test_invalid_metadata(self):
        cases = [(package, "version: 1.2.3", "version: 9.0.0") for package in PACKAGES]
        cases += [("quick_blue", "version: 1.2.3", replacement) for replacement in
                  ("", 'version: "1.2.3"', "version: |\n  1.2.3")]
        for package in PACKAGES[1:]:
            cases.extend((package, "  quick_blue_platform_interface: ^1.2.3", replacement) for replacement in
                         ("", "  quick_blue_platform_interface: ^1.2.30", "  quick_blue_platform_interface: ^9.0.0",
                          "  quick_blue_platform_interface: ^1.2.3\n  quick_blue_platform_interface: ^9.0.0"))
        for mutation in cases:
            with self.subTest(mutation=mutation):
                result, calls = self.fixture(mutation)
                self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
                self.assertTrue(result.stderr.strip())
                self.assertEqual(calls, [])


    def test_facade_dependency_membership(self):
        for dependency in FACADE_DEPENDENCIES:
            for replacement in ("", f"  {dependency}: ^1.2.3\n  {dependency}: ^9.0.0"):
                with self.subTest(dependency=dependency, replacement=replacement):
                    result, calls = self.fixture(("quick_blue", f"  {dependency}: ^1.2.3", replacement))
                    self.assertEqual(result.returncode, 65)
                    self.assertIn(dependency, result.stderr)
                    self.assertEqual(calls, [])

    def test_linux_backend_dependency_membership(self):
        for package, dependency in (
            ('quick_blue_linux', 'quick_blue_linux_dart'),
            ('quick_blue_linux', 'quick_blue_core'),
            ('quick_blue_linux_dart', 'quick_blue_core'),
        ):
            for replacement in ('', f'  {dependency}: ^9.0.0'):
                with self.subTest(package=package, dependency=dependency):
                    result, calls = self.fixture((package, f'  {dependency}: ^1.2.3', replacement))
                    self.assertEqual(result.returncode, 65)
                    self.assertIn(dependency, result.stderr)
                    self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
