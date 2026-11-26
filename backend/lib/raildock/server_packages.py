"""Bounded Debian/Ubuntu package maintenance, detached from the control plane.
No reboot, package removal, repository rewrite or unattended release upgrade.
"""
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import time
import subprocess
import sys

ROOT = Path('/var/lib/raildock/maintenance')
ID = re.compile(r'^[a-f0-9]{32}$')
PACKAGE = re.compile(r'^[a-z0-9][a-z0-9+.:~-]*$')
VERSION = re.compile(r'^[A-Za-z0-9.+:~_-]+$')


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def packages(output):
    result = []
    for line in output.splitlines():
        match = re.match(r'^Inst (\S+)(?: \[([^\]]+)\])? \((\S+)', line)
        if match:
            name, installed, candidate = match.groups()
            if not PACKAGE.fullmatch(name) or not VERSION.fullmatch(candidate):
                raise ValueError('Unsupported package metadata; install from the host console.')
            result.append({'name': name, 'installed': installed or '', 'candidate': candidate})
    return sorted(result, key=lambda item: item['name'])


def digest(rows):
    return hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()


def main(operation, mode, reviewed):
    if not ID.fullmatch(operation) or mode not in ('inspect', 'check', 'install') or (reviewed and not ID.fullmatch(reviewed)):
        raise ValueError('Invalid operation')
    if os.geteuid() != 0:
        raise ValueError('Root host access is required')
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    if ROOT.is_symlink() or ROOT.resolve() != ROOT:
        raise ValueError('Unsafe maintenance directory')
    directory = ROOT / operation
    directory.mkdir(mode=0o700, exist_ok=True)
    if directory.is_symlink():
        raise ValueError('Unsafe operation directory')
    state = {'id': operation, 'status': 'running', 'kind': mode, 'started_at': timestamp(), 'updated_at': timestamp()}

    def save(**values):
        state.update(values, updated_at=timestamp())
        temporary = directory / 'status.tmp'
        temporary.write_text(json.dumps(state))
        temporary.replace(directory / 'status.json')

    def run(args, seconds=120):
        process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   env={**os.environ, 'LC_ALL': 'C', 'DEBIAN_FRONTEND': 'noninteractive', 'NEEDRESTART_MODE': 'l'})
        output = bytearray()
        total = 0
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        started = time.monotonic()
        written = started
        try:
            while selector.get_map():
                if time.monotonic() - started > seconds:
                    # Do not kill apt/dpkg in the middle of a transaction. The
                    # systemd process retains the package-manager child. Block
                    # retries until an operator has inspected the host.
                    save(error='Package command exceeded its reporting window. Inspect the host; do not retry while apt/dpkg is running.')
                    process.wait()
                    raise ValueError('Package command exceeded its reporting window; inspect the host before retrying.')
                for key, _ in selector.select(timeout=1):
                    chunk = os.read(key.fileobj.fileno(), 8192)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    total += len(chunk)
                    output.extend(chunk)
                    if len(output) > 1024 * 1024:
                        del output[:-1024 * 1024]
                if time.monotonic() - written > 3:
                    save(log_tail=output[-12000:].decode(errors='replace'))
                    written = time.monotonic()
            code = process.wait()
        finally:
            selector.close()
            process.stdout.close()
        text = output.decode(errors='replace')
        save(log_tail=text[-12000:])
        if code:
            raise ValueError('Package command failed; inspect the output and host package-manager state before retrying.')
        if total > 1024 * 1024 and '-s' in args:
            raise ValueError('Package plan exceeded the reporting budget. Review this host manually.')
        return text

    save()
    try:
        with open(ROOT / 'maintenance.lock', 'w') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('Another maintenance operation is running on this host.')
            facts = {}
            for line in Path('/etc/os-release').read_text().splitlines():
                key, _, value = line.partition('=')
                facts[key] = value.strip('"')
            supported = facts.get('ID') in ('ubuntu', 'debian')
            save(supported=supported, os=facts.get('PRETTY_NAME', 'Linux'), os_id=facts.get('ID'), os_version=facts.get('VERSION_ID'))
            if not supported:
                if mode == 'install':
                    raise ValueError('This distribution does not support package installation through RailDock.')
                save(status='completed', checked_at=timestamp(), count=0, packages=[], held_packages=[], release={'supported': False, 'available': False}, message='Package management is available for Ubuntu and Debian hosts. Use this distribution’s package manager from its console.')
                return
            if mode == 'check':
                save(phase='Refreshing package indexes')
                run(['apt-get', '-o', 'APT::Update::Error-Mode=any', '-o', 'Acquire::Retries=0', '-o', 'Acquire::http::Timeout=30', '-o', 'Acquire::https::Timeout=30', 'update'], 300)
            save(phase='Reviewing available packages')
            simulation = run(['apt-get', '-s', 'upgrade'])
            if any(line.startswith('Remv ') for line in simulation.splitlines()):
                raise ValueError('This plan removes packages. Review it in the host console.')
            rows = packages(simulation)
            if len(rows) > 2000:
                raise ValueError('More than 2000 package changes; review this host manually.')
            fingerprint = digest(rows)
            if mode == 'install':
                if not reviewed:
                    raise ValueError('A reviewed package check is required.')
                previous = json.loads((ROOT / reviewed / 'status.json').read_text())
                age = datetime.datetime.now(datetime.timezone.utc) - datetime.datetime.fromisoformat(previous['checked_at'])
                if previous.get('status') != 'completed' or previous.get('plan_digest') != fingerprint or age.total_seconds() > 3600:
                    raise ValueError('The package plan changed or expired. Check and review updates again.')
                if not rows:
                    raise ValueError('No package updates to install.')
                specs = [row['name'] + '=' + row['candidate'] for row in rows]
                # Confirm the exact reviewed versions introduce no removals or new packages.
                args = ['apt-get', '--only-upgrade', '--no-remove', '--no-install-recommends', 'install', *specs]
                exact = run([*args[:1], '-s', *args[1:]])
                if any(line.startswith('Remv ') for line in exact.splitlines()) or digest(packages(exact)) != fingerprint:
                    raise ValueError('The install plan changed. Check and review updates again.')
                save(phase='Installing reviewed package versions')
                run(['apt-get', '-y', '-o', 'DPkg::Lock::Timeout=60', '-o', 'Dpkg::Options::=--force-confdef', '-o', 'Dpkg::Options::=--force-confold', *args[1:]], 7200)
                rows = packages(run(['apt-get', '-s', 'upgrade']))
                fingerprint = digest(rows)
            release = {'supported': facts.get('ID') == 'ubuntu', 'available': False}
            cached = Path('/var/lib/ubuntu-release-upgrader/release-upgrade-available')
            if cached.is_file():
                text = cached.read_text()[:2000]
                match = re.search(r"New release ['\"]([^'\"]+)['\"] available", text)
                if match:
                    release.update(available=True, target=match[1])
            # A manual check refreshes release availability; background inspection
            # uses the distribution's cached result and makes no repository request.
            if mode == 'check' and facts.get('ID') == 'ubuntu' and Path('/usr/bin/do-release-upgrade').exists():
                try:
                    result = subprocess.run(['do-release-upgrade', '-c'], capture_output=True, text=True, timeout=90, env={**os.environ, 'LC_ALL': 'C'})
                    match = re.search(r"New release ['\"]([^'\"]+)['\"] available", result.stdout)
                    release.update(available=bool(match), target=match[1] if match else None, checked=result.returncode in (0, 1))
                except (subprocess.SubprocessError, OSError):
                    release.update(checked=False)
            free = os.statvfs('/')
            save(status='completed', phase='Finished', checked_at=timestamp(), count=len(rows), packages=rows[:200], truncated=len(rows)>200,
                 plan_digest=fingerprint, reboot_required=Path('/var/run/reboot-required').exists(), release=release,
                 disk_available=free.f_bavail * free.f_frsize, held_packages=run(['apt-mark', 'showhold']).splitlines()[:200])
    except Exception as error:
        save(status='failed', error=str(error)[:500])
        raise


if __name__ == '__main__':
    os.umask(0o077)
    main(*sys.argv[1:4])
