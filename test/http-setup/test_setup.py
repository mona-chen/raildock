import base64
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('setup', Path(__file__).parents[2] / 'backend/lib/raildock/http_setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class HostSetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        for directory in ['etc/logrotate.d', 'etc/systemd/system', 'var/lib/dokku/plugins/enabled']:
            (self.root / directory).mkdir(parents=True)
        self.compose = self.root / 'compose.yml'
        self.compose.write_bytes(b'original-compose')
        self.candidate = dict(container='proxy', container_id='abc', can_manage=True, digest='review', compose_path=str(self.compose), project='project', service='traefik')
        self.plan = dict(self.candidate, compose_b64=base64.b64encode(b'new-compose').decode())
        self.calls = []
        self.fail_start = False

    def tearDown(self):
        self.temp.cleanup()

    def path(self, value):
        value = str(value)
        return self.root / value.lstrip('/') if value.startswith(('/var/', '/etc/')) else Path(value)

    def host_run(self, args, timeout=20):
        self.calls.append(args)
        if args[:2] == ['docker', 'inspect']:
            return json.dumps([dict(Image='sha256:test', State=dict(Running=True, Health=dict(Status='healthy')), NetworkSettings=dict(Ports={}))])
        if args[:3] == ['docker', 'image', 'inspect']:
            return 'sha256:test'
        if 'config' in args and '--format' in args:
            return json.dumps({'services': {'traefik': {'image': 'traefik:v3'}}})
        if 'up' in args and self.fail_start and self.compose.read_bytes() == b'new-compose':
            raise subprocess.CalledProcessError(1, args)
        return ''

    def apply(self):
        with patch.object(setup, 'ROOT', self.root / 'state'), patch.object(setup, 'Path', self.path), patch.object(setup, 'discover', return_value=[self.candidate]), patch.object(setup, 'run', side_effect=self.host_run), patch.object(setup.shutil, 'which', return_value='/usr/sbin/logrotate'), patch.object(setup.time, 'sleep'), patch.object(setup.subprocess, 'run'):
            return setup.apply(self.plan)

    def test_success_backs_up_source_and_only_recreates_selected_service(self):
        result = self.apply()
        self.assertEqual(self.compose.read_bytes(), b'new-compose')
        backups = list((self.root / 'state').glob('*.backup'))
        self.assertEqual(backups[0].read_bytes(), b'original-compose')
        starts = [args for args in self.calls if 'up' in args]
        self.assertEqual(len(starts), 1)
        self.assertEqual(starts[0][-1], 'traefik')
        self.assertIn('--no-deps', starts[0])
        self.assertTrue(Path(result['path']).is_file())
        self.assertIn('rotate 2', (self.root / 'state/proxy.logrotate').read_text())

    def test_failed_start_restores_original_and_recreates_it(self):
        self.fail_start = True
        with self.assertRaisesRegex(ValueError, 'original proxy configuration restored'):
            self.apply()
        self.assertEqual(self.compose.read_bytes(), b'original-compose')
        self.assertEqual(len([args for args in self.calls if 'up' in args]), 2)
        self.assertFalse((self.root / 'state/proxy.logrotate').exists())
        self.assertFalse((self.root / 'etc/systemd/system/raildock-http-proxy.timer').exists())

    def test_changed_configuration_never_writes_or_restarts(self):
        self.plan['digest'] = 'stale'
        with self.assertRaisesRegex(ValueError, 'Proxy changed'):
            self.apply()
        self.assertEqual(self.compose.read_bytes(), b'original-compose')
        self.assertEqual(self.calls, [])

    def test_dokku_template_uses_native_hook_and_retains_existing_template(self):
        template = 'services:\n  traefik:\n    command:\n      - --log.format=json\n    volumes:\n      - /certs:/certs\n'
        self.candidate['template_b64'] = base64.b64encode(template.encode()).decode()
        self.apply()
        hook = self.root / 'var/lib/dokku/plugins/available/raildock-http/traefik-template-source'
        custom = self.root / 'state/compose.yml.sigil'
        self.assertTrue(hook.is_file())
        self.assertEqual(subprocess.check_output(['sh', str(hook)], text=True).strip(), str(custom))
        self.assertIn('--accesslog.format=json', custom.read_text())
        self.assertIn('/certs:/certs', custom.read_text())
        self.assertNotIn('RequestPath', custom.read_text())

    def test_dokku_template_keeps_request_paths_only_when_the_plan_opts_in(self):
        template = 'services:\n  traefik:\n    command:\n      - --log.format=json\n    volumes:\n      - /certs:/certs\n'
        self.candidate['template_b64'] = base64.b64encode(template.encode()).decode()
        self.plan['capture_paths'] = True
        self.apply()
        rendered = (self.root / 'state/compose.yml.sigil').read_text()
        self.assertIn('--accesslog.fields.names.RequestPath=keep', rendered)
        self.assertIn('--accesslog.fields.names.RequestHost=keep', rendered)


if __name__ == '__main__':
    unittest.main()
