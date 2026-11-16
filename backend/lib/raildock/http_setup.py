"""Discover and configure a single Compose-owned Traefik. No raw configuration leaves the API."""
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import time

ROOT = Path('/var/lib/dokku/raildock-http')
FIELDS = ['StartUTC', 'RequestHost', 'DownstreamStatus', 'DownstreamContentSize', 'Duration']


def run(args, timeout=20):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=timeout, text=True)


def regular(path, max_bytes=262144):
    p = Path(path)
    if not p.is_absolute() or p.is_symlink() or p.resolve() != p or not p.is_file() or (max_bytes is not None and p.stat().st_size > max_bytes):
        raise ValueError('Configuration is not a regular, bounded file')
    return p


def discover():
    ids = run(['docker', 'ps', '-q']).split()
    if len(ids) > 250:
        raise ValueError('Too many containers for automatic discovery')
    containers = json.loads(run(['docker', 'inspect', *ids])) if ids else []
    candidates = []
    for c in containers:
        image = c['Config']['Image'].lower().split('@')[0]
        if not re.search(r'(?:^|/)traefik(?::|$)', image):
            continue
        name = c['Name'].lstrip('/')
        labels = c['Config'].get('Labels') or {}
        item = dict(container=name, container_id=c['Id'], image=image, can_manage=False)
        args = c['Config'].get('Cmd') or []
        flags = dict(a[2:].lower().split('=', 1) for a in args if a.startswith('--') and '=' in a)
        dest = flags.get('accesslog.filepath')
        if dest and flags.get('accesslog.format') == 'json':
            for mount in c['Mounts']:
                target = mount['Destination'].rstrip('/')
                if mount['Type'] == 'bind' and (dest == target or dest.startswith(target + '/')):
                    source = mount['Source'] + dest[len(target):]
                    if source.startswith(('/var/log/', '/var/lib/dokku/')) and source.endswith(('.log', '.jsonl')):
                        try:
                            regular(source, None)
                            item['path'] = source
                        except ValueError:
                            pass
        files = labels.get('com.docker.compose.project.config_files', '').split(',')
        service = labels.get('com.docker.compose.service', '')
        project = labels.get('com.docker.compose.project', '')
        try:
            if len(files) != 1 or not service or not project:
                raise ValueError('Requires a single Compose source file')
            file = regular(files[0])
            if c['Config'].get('User') not in ('', 'root', '0', '0:0'):
                raise ValueError('Automatic setup requires a root proxy container')
            if any(a.lower().startswith('--configfile') for a in args) or any(k.startswith('TRAEFIK_') for k in (x.split('=')[0] for x in c['Config'].get('Env', []))):
                raise ValueError('File or environment based static settings require advanced setup')
            if not shutil.which('logrotate') or not Path('/run/systemd/system').is_dir():
                raise ValueError('Install logrotate and enable systemd before automatic setup')
            run(['docker', 'compose', '-f', str(file), 'config', '--quiet'])
            raw = file.read_bytes()
            if str(file).startswith('/var/lib/dokku/'):
                template = regular('/var/lib/dokku/plugins/available/traefik-vhosts/templates/compose.yml.sigil')
                custom = run(['plugn', 'trigger', 'traefik-template-source', '']).strip()
                if custom and custom != str(ROOT / 'compose.yml.sigil'):
                    raise ValueError('A custom Dokku proxy template already exists; use advanced setup')
                template_raw = template.read_bytes()
                if template_raw.count(b'      - --log.format=json') != 1 or template_raw.count(b'    volumes:') != 1:
                    raise ValueError('Unsupported Dokku proxy template')
                item['template_b64'] = base64.b64encode(template_raw).decode()
                raw_digest = raw + template_raw
            else:
                raw_digest = raw
            item.update(can_manage=True, compose_path=str(file), compose_b64=base64.b64encode(raw).decode(), digest=hashlib.sha256(raw_digest).hexdigest(), service=service, project=project)
        except (ValueError, subprocess.SubprocessError) as e:
            item['reason'] = str(e) if isinstance(e, ValueError) else 'Compose configuration could not be validated'
        candidates.append(item)
    return candidates


def atomic(path, data, mode=0o600):
    path = Path(path)
    temporary = path.with_name(path.name + '.raildock-tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    with os.fdopen(fd, 'wb') as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(temporary, path)


def apply(plan):
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    if ROOT.is_symlink() or ROOT.resolve() != ROOT:
        raise ValueError('Unsafe setup directory')
    with open(ROOT / 'setup.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        candidate = next((c for c in discover() if c['container_id'] == plan['container_id']), None)
        if not candidate or not candidate['can_manage'] or candidate['digest'] != plan['digest']:
            raise ValueError('Proxy changed. Review a fresh setup plan')
        path = regular(candidate['compose_path'])
        original = path.read_bytes()
        before = json.loads(run(['docker', 'inspect', candidate['container_id']]))[0]
        ports = []
        for bindings in (before['NetworkSettings'].get('Ports') or {}).values():
            for binding in bindings or []:
                address = binding['HostIp']
                address = '127.0.0.1' if address in ('', '0.0.0.0') else '::1' if address == '::' else address
                endpoint = (address, int(binding['HostPort']))
                try:
                    with socket.create_connection(endpoint, timeout=1):
                        ports.append(endpoint)
                except OSError:
                    pass
        name = candidate['container']
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,100}', name):
            raise ValueError('Unsupported container name')
        directory = Path('/var/log/raildock-http') / name
        directory.mkdir(parents=True, exist_ok=True, mode=0o750)
        if directory.resolve() != directory:
            raise ValueError('Unsafe logging directory')
        log = directory / 'access.log'
        if not log.exists():
            atomic(log, b'', 0o640)
        regular(log, None)
        stamp = str(time.time_ns())
        backup = ROOT / (name + '-' + stamp + '.compose.backup')
        atomic(backup, original)
        compose = ['docker', 'compose', '-p', candidate['project'], '-f', str(path)]
        rotation = ROOT / (name + '.logrotate')
        old_rotation = rotation.read_bytes() if rotation.exists() else None
        changed = False
        restart_attempted = False
        hook = Path('/var/lib/dokku/plugins/available/raildock-http/traefik-template-source')
        template = ROOT / 'compose.yml.sigil'
        managed_files = [hook, template]
        saved_files = {p: p.read_bytes() if p.exists() else None for p in managed_files}
        unit_name = 'raildock-http-' + name
        unit = Path('/etc/systemd/system/' + unit_name + '.service')
        timer = Path('/etc/systemd/system/' + unit_name + '.timer')
        saved_units = {p: p.read_bytes() if p.exists() else None for p in [unit, timer]}
        try:
            atomic(path, base64.b64decode(plan['compose_b64']), path.stat().st_mode & 0o777)
            changed = True
            rendered = json.loads(run(compose + ['config', '--format', 'json']))
            selected_image = rendered['services'][candidate['service']].get('image')
            if not selected_image or run(['docker', 'image', 'inspect', '--format', '{{.Id}}', selected_image]).strip() != before['Image']:
                raise ValueError('Proxy image changed; review the image before retrying setup')
            if candidate.get('template_b64'):
                text = base64.b64decode(candidate['template_b64']).decode()
                fields_names = FIELDS + (['RequestPath'] if plan.get('capture_paths') else [])
                fields = ['--accesslog=true', '--accesslog.format=json', '--accesslog.filepath=' + str(log), '--accesslog.bufferingsize=100', '--accesslog.fields.defaultmode=drop', '--accesslog.fields.headers.defaultmode=drop'] + ['--accesslog.fields.names.' + f + '=keep' for f in fields_names]
                text = text.replace('      - --log.format=json', '      - --log.format=json\n' + '\n'.join('      - ' + f for f in fields))
                text = text.replace('    volumes:', '    volumes:\n      - "' + str(directory) + ':' + str(directory) + '"')
                atomic(template, text.encode())
                hook.parent.mkdir(parents=True, exist_ok=True)
                atomic(hook, ('#!/bin/sh\nprintf "%s\\n" "' + str(template) + '"\n').encode(), 0o755)
                enabled = Path('/var/lib/dokku/plugins/enabled/raildock-http')
                if not enabled.exists():
                    enabled.symlink_to(hook.parent)
            rotation_text = f'''{log} {{
    size 25M
    rotate 2
    missingok
    notifempty
    nocompress
    create 0640 root root
    sharedscripts
    postrotate
        /usr/bin/docker kill --signal=USR1 {name} >/dev/null 2>&1 || true
    endscript
}}
'''
            atomic(rotation, rotation_text.encode(), 0o644)
            # Validate rotation before touching the running proxy.
            run(['logrotate', '--debug', str(rotation)])
            atomic(unit, ('[Service]\nType=oneshot\nExecStart=' + shutil.which('logrotate') + ' -s ' + str(ROOT / (name + '.rotation-state')) + ' ' + str(rotation) + '\n').encode(), 0o644)
            atomic(timer, ('[Timer]\nOnCalendar=hourly\nPersistent=true\n[Install]\nWantedBy=timers.target\n').encode(), 0o644)
            run(['systemctl', 'daemon-reload'])
            run(['systemctl', 'enable', '--now', unit_name + '.timer'])
            restart_attempted = True
            run(compose + ['up', '-d', '--no-deps', '--pull', 'never', '--no-build', candidate['service']], timeout=90)
            for _ in range(30):
                state = json.loads(run(['docker', 'inspect', name]))[0]['State']
                healthy = state.get('Health', {}).get('Status')
                if state.get('Running') and healthy in (None, 'healthy'):
                    time.sleep(2)
                    state = json.loads(run(['docker', 'inspect', name]))[0]['State']
                    listeners_ready = True
                    for endpoint in ports:
                        try:
                            with socket.create_connection(endpoint, timeout=1):
                                pass
                        except OSError:
                            listeners_ready = False
                    if listeners_ready and state.get('Running') and state.get('Health', {}).get('Status') in (None, 'healthy'):
                        return dict(path=str(log), container=name, backup=str(backup))
                time.sleep(1)
            raise ValueError('Proxy did not become healthy')
        except Exception:
            if changed:
                atomic(path, original, path.stat().st_mode & 0o777)
                for p, data in {**saved_files, **saved_units}.items():
                    if data is None:
                        if p.exists():
                            p.unlink()
                    else:
                        atomic(p, data, 0o755 if p == hook else 0o644 if p in saved_units else 0o600)
                if saved_files[hook] is None:
                    enabled = Path('/var/lib/dokku/plugins/enabled/raildock-http')
                    if enabled.is_symlink() and enabled.resolve() == hook.parent:
                        enabled.unlink()
                if saved_units[timer] is None:
                    subprocess.run(['systemctl', 'disable', '--now', unit_name + '.timer'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(['systemctl', 'daemon-reload'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if old_rotation is not None:
                    atomic(rotation, old_rotation, 0o644)
                elif rotation.exists():
                    rotation.unlink()
                try:
                    if restart_attempted:
                        run(compose + ['up', '-d', '--no-deps', '--pull', 'never', '--no-build', candidate['service']], timeout=90)
                except Exception:
                    raise ValueError('Setup failed and proxy rollback needs attention; original configuration was restored')
            raise ValueError('Setup failed; original proxy configuration restored')


def interrupted(_signum, _frame):
    raise ValueError('Host setup interrupted')


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, interrupted)
    output = None
    try:
        action = sys.argv[1]
        result = discover() if action == 'discover' else apply(json.loads(Path(sys.argv[2]).read_text()))
        output = dict(state='completed', **result) if action != 'discover' else result
        print(json.dumps(output))
    except Exception as e:
        output = dict(state='failed', error=str(e) if isinstance(e, ValueError) else 'Proxy setup failed; inspect the host before retrying')
        print(json.dumps(output))
        sys.exit(1)
    finally:
        if len(sys.argv) > 2 and sys.argv[1] == 'apply-file':
            try:
                atomic(Path(sys.argv[2]).with_name('result.json'), json.dumps(output).encode())
                Path(sys.argv[2]).unlink()
            except OSError:
                pass
