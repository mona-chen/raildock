import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('server_packages', Path(__file__).parents[2] / 'lib/raildock/server_packages.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class PackageMaintenanceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        module.ROOT = Path(self.temp.name).resolve() / 'maintenance'
        self.commands = []
        self.plan = 'Inst openssl [3.0.1] (3.0.2 Ubuntu:24.04/noble-updates [amd64])\n'
        self.installed = False
        original_read = Path.read_text

        def read(path, *args, **kwargs):
            if str(path) == '/etc/os-release':
                return 'ID=ubuntu\nPRETTY_NAME="Ubuntu 24.04 LTS"\nVERSION_ID="24.04"\n'
            return original_read(path, *args, **kwargs)

        owner = self

        class Process:
            def __init__(self, args, **kwargs):
                owner.commands.append(args)
                output = owner.plan if '-s' in args else ''
                if '-y' in args:
                    owner.installed = True
                read_fd, write_fd = os.pipe()
                os.write(write_fd, output.encode())
                os.close(write_fd)
                self.stdout = os.fdopen(read_fd, 'rb')

            def wait(self):
                return 0

        self.patches = [patch.object(Path, 'read_text', read), patch.object(os, 'geteuid', return_value=0), patch.object(module.subprocess, 'Popen', Process)]
        for mock in self.patches:
            mock.start()

    def tearDown(self):
        for mock in reversed(self.patches):
            mock.stop()
        self.temp.cleanup()

    def result(self, id):
        return json.loads((module.ROOT / id / 'status.json').read_text())

    def test_background_inspection_never_refreshes_or_installs(self):
        module.main('a' * 32, 'inspect', '')
        self.assertFalse(self.installed)
        self.assertFalse(any('update' in command for command in self.commands))
        self.assertEqual(self.result('a' * 32)['count'], 1)

    def test_install_pins_the_reviewed_versions_and_forbids_removal(self):
        module.main('a' * 32, 'inspect', '')
        module.main('b' * 32, 'install', 'a' * 32)
        install = next(command for command in self.commands if '-y' in command)
        self.assertIn('--only-upgrade', install)
        self.assertIn('--no-remove', install)
        self.assertIn('openssl=3.0.2', install)
        self.assertEqual(self.result('b' * 32)['status'], 'completed')

    def test_a_changed_plan_is_rejected_before_install(self):
        module.main('a' * 32, 'inspect', '')
        self.plan = self.plan.replace('3.0.2', '3.0.3')
        with self.assertRaisesRegex(ValueError, 'changed or expired'):
            module.main('b' * 32, 'install', 'a' * 32)
        self.assertFalse(self.installed)
        self.assertEqual(self.result('b' * 32)['status'], 'failed')

    def test_a_removal_plan_is_never_executed(self):
        self.plan += 'Remv docker-ce [28.0.1]\n'
        with self.assertRaisesRegex(ValueError, 'removes packages'):
            module.main('a' * 32, 'inspect', '')
        self.assertFalse(self.installed)

    def test_rejects_untrusted_package_tokens(self):
        with self.assertRaises(ValueError):
            module.packages('Inst openssl [3.0.1] (evil;command Ubuntu [amd64])')


if __name__ == '__main__':
    unittest.main()
