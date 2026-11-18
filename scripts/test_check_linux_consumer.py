"""Hermetic consumer construction checks; never invoke Flutter or Git."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("consumer", Path(__file__).with_name("check-linux-consumer.py"))
if spec is None or spec.loader is None:
    raise RuntimeError("Cannot load consumer validator")
consumer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(consumer)


class ConsumerTests(unittest.TestCase):
    def exercise(self, poison=None, package="quick_blue", dirty=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / f"consumer_{package}"
            cache = root / f"cache_{package}"
            graph = {"roots": ["linux_consumer"], "packages": [
                {"name": "linux_consumer", "dependencies": ["flutter", package]},
                {"name": "quick_blue_linux", "dependencies": ["quick_blue_linux_dart"]},
                {"name": "quick_blue_linux_dart", "dependencies": ["bluez"]},
                {"name": "bluez", "dependencies": []},
            ]}
            config = {"packages": [{"name": name, "rootUri": cache.as_uri() + "/git/" + name}
                                    for name in consumer.PACKAGES + ("bluez",)]}
            if poison:
                poison(graph, config)
            calls = []
            def run(*args, **kwargs):
                calls.append(args)
                if args[1] == "create":
                    (app / "lib").mkdir(parents=True)
                    # Model first-run Flutter bootstrap, not consumer pub get.
                    template_cache = Path(kwargs["env"]["PUB_CACHE"])
                    self.assertNotEqual(template_cache, cache)
                    (template_cache / "flutter-bootstrap").touch()
                    if dirty:
                        (cache / "seed").touch()
                if args[1:3] == ("pub", "get"):
                    self.assertEqual(Path(kwargs["env"]["PUB_CACHE"]), cache)
                    self.assertEqual(list(cache.iterdir()), [])
                    (app / ".dart_tool").mkdir()
                    (app / ".dart_tool/package_graph.json").write_text(json.dumps(graph))
                    (app / ".dart_tool/package_config.json").write_text(json.dumps(config))
                if args[1:3] == ("build", "linux"):
                    binary = app / 'build/linux/x64/debug/bundle/linux_consumer'
                    binary.parent.mkdir(parents=True)
                    binary.touch()
            with patch.object(consumer, "run", run):
                consumer.check_consumer(package, root / "repository", "abc123", root)
            manifest = (app / "pubspec.yaml").read_text()
            self.assertEqual(calls[-1][0:2], ("timeout", "60"))
            source = (app / 'lib/main.dart').read_text()
            self.assertNotIn('.registerWith()', source)
            self.assertIn('installed is! backend.QuickBlueLinux', source)
            return manifest

    def test_valid_facade(self):
        manifest = self.exercise()
        overrides = manifest.split("dependency_overrides:\n")[1]
        for name in consumer.PACKAGES[1:]:
            self.assertIn(f"  {name}:\n", overrides)
        self.assertNotIn("  quick_blue:\n", overrides)

    def test_valid_linux(self):
        overrides = self.exercise(package="quick_blue_linux").split("dependency_overrides:\n")[1]
        self.assertEqual(overrides.count("    git:"), 3)
        self.assertIn("quick_blue_core", overrides)
        self.assertIn("quick_blue_platform_interface", overrides)

    def test_git_dependency(self):
        url = 'file:///some path/"quoted"'
        text = consumer.git_dependency("quick_blue", url, "abc123")
        self.assertIn(f"url: {json.dumps(url)}", text)
        self.assertIn("ref: abc123\n", text)
        self.assertIn("path: quick_blue\n", text)

    def test_invalid_graphs(self):
        cases = [
            (lambda g, c: g.update(roots=["workspace"]), "outside the workspace"),
            (lambda g, c: g["packages"][0].update(dependencies=["flutter"]), "dependencies"),
            (lambda g, c: g["packages"][1].update(dependencies=[]), "quick_blue_linux_dart"),
            (lambda g, c: g["packages"][2].update(dependencies=[]), "bluez"),
            (lambda g, c: g["packages"].pop(), "bluez"),
            (lambda g, c: c["packages"][0].update(rootUri="file:///outside"), "cache"),
        ]
        for poison, message in cases:
            with self.subTest(message=message), self.assertRaisesRegex((AssertionError, ValueError), message):
                self.exercise(poison)

    def test_dirty_cache(self):
        with self.assertRaisesRegex((AssertionError, ValueError), "empty"):
            self.exercise(dirty=True)


if __name__ == "__main__":
    unittest.main()
