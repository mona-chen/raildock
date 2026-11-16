"""Read sampled TCP data counters. No payloads, socket addresses or ports leave the host."""
import base64
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import sys
import tempfile
import time

ROOT = Path('/var/lib/dokku/raildock-flow')
MAX_BYTES = 4 * 1024 * 1024


def command(args, timeout=3):
    def limits():
        resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_BYTES, MAX_BYTES))
    with tempfile.TemporaryFile() as output:
        result = subprocess.run(args, stdout=output, stderr=subprocess.DEVNULL, timeout=timeout, preexec_fn=limits)
        if result.returncode or output.tell() >= MAX_BYTES:
            raise ValueError('Command failed or exceeded collection budget')
        output.seek(0)
        return output.read().decode()


def endpoint(value):
    host, port = value.rsplit(':', 1)
    address = ipaddress.ip_address(host.strip('[]').split('%')[0])
    if address.version == 6 and address.ipv4_mapped:
        address = address.ipv4_mapped
    return str(address), int(port)


def sockets(output):
    rows = []
    for line in output.splitlines():
        columns = line.split()
        if not columns:
            continue
        offset = 1 if columns[0] == 'ESTAB' else 0
        try:
            local, peer = endpoint(columns[offset+2]), endpoint(columns[offset+3])
            cookie = re.search(r'\bsk:([0-9a-f]+)\b', line)
            if not cookie:
                raise ValueError('Socket identity unavailable')
            sent = re.search(r'\bbytes_sent:(\d+)', line)
            received = re.search(r'\bbytes_received:(\d+)', line)
            rows.append((local, peer, cookie[1], int(sent[1]) if sent else 0, int(received[1]) if received else 0))
        except (ValueError, IndexError):
            raise ValueError('Unsupported ss output; counters are unavailable')
        if len(rows) > 10000:
            raise ValueError('Socket budget exceeded')
    return rows


def measure(containers, config, previous, read=command, now=None):
    now = now or time.time()
    wanted = config['services']
    inventory, addresses = {}, {}
    exact, apps = {}, {}
    for sid, names in wanted.items():
        for name in names:
            index = exact if name.startswith('dokku.') else apps
            index.setdefault(name, set()).add(sid)
    for container in containers:
        name = container['Name'].lstrip('/')
        parts = name.rsplit('.', 2)
        owners = exact.get(name, set()) or (apps.get(parts[0], set()) if len(parts) == 3 and parts[-1].isdigit() else set())
        if len(owners) != 1 or not container['State'].get('Running'):
            continue
        sid = next(iter(owners))
        mode = container['HostConfig'].get('NetworkMode', '')
        if mode in ('host', 'none') or mode.startswith('container:'):
            continue
        pid = int(container['State']['Pid'])
        if pid <= 0:
            continue
        networks = container['NetworkSettings']['Networks']
        network_ids = {network.get('NetworkID') or name for name, network in networks.items()}
        inventory.setdefault(sid, []).append((container['Id'], pid, network_ids))
        for name, network in networks.items():
            for field in ('IPAddress', 'GlobalIPv6Address'):
                address = network.get(field)
                if address:
                    addresses.setdefault((network.get('NetworkID') or name, str(ipaddress.ip_address(address))), set()).add(sid)
    links = config['links']
    sources = {link['from'] for link in links}
    destinations = {sid: {link['to'] for link in links if link['from'] == sid} for sid in sources}
    if sum(len(inventory.get(s, [])) for s in sources) > 32 or len(links) > 500:
        raise ValueError('Linked container budget exceeded')
    baseline = previous.get('counters', {})
    elapsed = now - previous.get('at', 0)
    warm = 1 <= elapsed <= 180 and previous.get("epoch") == config.get("epoch")
    current, observations = {}, {}
    deadline = time.monotonic() + 8
    for sid in sources:
        observations[sid] = []
        for identity, pid, network_ids in inventory.get(sid, []):
            if time.monotonic() >= deadline:
                observations[sid] = None
                break
            try:
                # Verify the namespace before and after ss to reject a container exiting/PID reuse.
                namespace = os.readlink('/proc/%d/ns/net' % pid)
                output = read(['nsenter', '--target', str(pid), '--net', '--', 'ss', '-HtinOe', 'state', 'established'])
                if os.readlink('/proc/%d/ns/net' % pid) != namespace:
                    raise ValueError('Network namespace changed')
                for local, peer, cookie, sent, received in sockets(output):
                    targets = set().union(*(addresses.get((network, peer[0]), set()) for network in network_ids))
                    if len(targets) != 1:
                        continue
                    target = next(iter(targets))
                    if target not in destinations[sid]:
                        continue
                    # Socket cookie plus container incarnation prevents IP/port reuse from creating activity.
                    key = hashlib.sha256((identity + namespace + cookie).encode()).hexdigest()
                    old = baseline.get(key)
                    current[key] = [sent, received]
                    outgoing = max(0, sent-old[0]) if old and warm else 0
                    incoming = max(0, received-old[1]) if old and warm else 0
                    observations[sid].append((target, outgoing, incoming, bool(old and warm)))
            except (OSError, ValueError, subprocess.SubprocessError):
                observations[sid] = None
                break
    if len(current) > 10000:
        raise ValueError('Counter budget exceeded')
    result = []
    for link in links:
        rows = observations.get(link['from'])
        available = rows is not None and bool(inventory.get(link['from'])) and bool(inventory.get(link['to']))
        relevant = [r for r in rows or [] if r[0] == link['to']]
        measured = available and warm and all(r[3] for r in relevant)
        result.append(dict(id=link['id'], state='sampled' if measured else 'warming' if available else 'unavailable', sent_bytes=sum(r[1] for r in relevant) if measured else 0, received_bytes=sum(r[2] for r in relevant) if measured else 0, connections=len(relevant), window_seconds=round(elapsed, 2) if warm else 0))
    return dict(at=now, counters=current, epoch=config.get("epoch")), result


def collect(config):
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    if ROOT.resolve() != ROOT or ROOT.is_symlink():
        raise ValueError('Unsafe collector directory')
    scope = config['scope']
    if not re.fullmatch(r'[0-9a-f]{16}', scope):
        raise ValueError('Invalid collector scope')
    if int(os.uname().release.split('.')[0]) < 5:
        raise ValueError('Linux 5 or later is required')
    with open(ROOT/(scope+'.lock'), 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        file = ROOT/(scope+'.json')
        if file.is_symlink():
            raise ValueError('Unsafe counter file')
        previous = json.loads(file.read_text()) if file.exists() and file.stat().st_size < MAX_BYTES else {}
        ids = command(['docker', 'ps', '-q']).split()
        if len(ids) > 250:
            raise ValueError('Container budget exceeded')
        containers = json.loads(command(['docker', 'inspect', *ids])) if ids else []
        cursor, links = measure(containers, config, previous)
        tmp = ROOT/(scope+'.tmp')
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'w') as output:
            json.dump(cursor, output)
        os.replace(tmp, file)
        return dict(sampled_at=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(cursor['at'])), links=links, coverage='Sampled TCP only. Short-lived connections, UDP, Unix sockets and proxy/NAT aliases may not be observed.')


if __name__ == '__main__':
    try:
        os.umask(0o077)
        print(json.dumps(collect(json.loads(base64.b64decode(sys.argv[1])))))
    except Exception:
        print(json.dumps({'error': 'TCP flow collection unavailable. Check Linux, root SSH, Python 3, nsenter and ss; host/container budgets may be exceeded.'}))
        sys.exit(1)
