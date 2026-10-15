"""Hermetic graph/manifest validation; these tests do not run Dart or BLE."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('headless', Path(__file__).with_name('check-headless-consumer.py'))
if spec is None or spec.loader is None:
    raise RuntimeError('Cannot load standalone consumer validator')
headless = importlib.util.module_from_spec(spec)
spec.loader.exec_module(headless)


class HeadlessGraphTests(unittest.TestCase):
    def fixture(self, mutate=None, expected_root='headless_consumer'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            consumer = root / 'consumer'
            snapshot = root / 'packages'
            (consumer / '.dart_tool').mkdir(parents=True)
            graph = {'roots': ['headless_consumer']}
            config = {'packages': []}
            for name in (*headless.PACKAGES, 'bluez', 'dbus', 'plugin_platform_interface'):
                package = snapshot / name
                package.mkdir(parents=True)
                text = f'name: {name}\nenvironment:\n  sdk: ^3.13.0\n'
                if name == 'quick_blue_linux':
                    text += 'flutter:\n  plugin:\n    implements: quick_blue\n    platforms:\n      linux:\n        dartPluginClass: QuickBlueLinux\n'
                (package / 'pubspec.yaml').write_text(text)
                config['packages'].append({'name': name, 'rootUri': package.as_uri() + '/'})
            if mutate:
                mutate(graph, config, snapshot)
            (consumer / '.dart_tool/package_graph.json').write_text(json.dumps(graph))
            (consumer / '.dart_tool/package_config.json').write_text(json.dumps(config))
            return headless.inspect_graph(consumer, snapshot, expected_root)

    def test_cli_root_is_explicit_not_an_accepted_workspace(self):
        mutate = lambda graph, config, snapshot: graph.update(roots=['quick_blue_linux_cli'])
        self.fixture(mutate, expected_root='quick_blue_linux_cli')
        with self.assertRaisesRegex(ValueError, 'roots'):
            self.fixture(mutate)

    def test_plugin_metadata_is_not_an_sdk_dependency(self):
        manifests = self.fixture()
        self.assertIn('implements: quick_blue', manifests['quick_blue_linux']['pubspec'])

    def test_rejects_flutter_sdk_dependency(self):
        def mutate(graph, config, snapshot):
            path = snapshot / 'dbus/pubspec.yaml'
            path.write_text(path.read_text() + 'dependencies:\n  flutter:\n    sdk: flutter\n')
        with self.assertRaisesRegex(ValueError, 'Flutter SDK'):
            self.fixture(mutate)

    def test_rejects_transitive_flutter_environment_constraint(self):
        def mutate(graph, config, snapshot):
            path = snapshot / 'plugin_platform_interface/pubspec.yaml'
            path.write_text(path.read_text().replace('  sdk: ^3.13.0', '  sdk: ^3.13.0\n  flutter: ">=3.0.0"'))
        with self.assertRaisesRegex(ValueError, 'Flutter SDK'):
            self.fixture(mutate)

    def test_rejects_workspace_roots(self):
        with self.assertRaisesRegex(ValueError, 'roots'):
            self.fixture(lambda graph, config, snapshot: graph.update(roots=['workspace']))

    def test_rejects_mixed_repository_snapshots(self):
        def mutate(graph, config, snapshot):
            config['packages'][0]['rootUri'] = (snapshot / 'elsewhere').as_uri()
        with self.assertRaisesRegex(ValueError, 'matched snapshot'):
            self.fixture(mutate)

    def test_requires_transitive_manifests(self):
        def mutate(graph, config, snapshot):
            config['packages'].pop()
        with self.assertRaisesRegex(ValueError, 'plugin_platform_interface'):
            self.fixture(mutate)


if __name__ == '__main__':
    unittest.main()
