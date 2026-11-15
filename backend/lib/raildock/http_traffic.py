"""Bounded proxy-log reader. Only sanitized aggregate data leaves the host."""
import base64
import datetime as dt
import json
import math
import os
import re
import stat
import sys
import time
import urllib.parse
import zlib

BOUNDS = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000, 60000]
MAX_BYTES = 2 * 1024 * 1024
MAX_LINE = 65536
SUSPICIOUS = re.compile(r"\.\./|/etc/(passwd|shadow)|/(?:\.env|\.git)(?:/|$|\?)|phpunit|/wp-login\.php", re.I)


def collect(config):
    path = config['path']
    if not (path.startswith('/var/log/') or path.startswith('/var/lib/dokku/')) or not path.endswith(('.log', '.jsonl')):
        raise ValueError('unsupported log path')
    if os.path.realpath(path) != path:
        raise ValueError('symlink log paths are not supported')
    cursor = config.get('cursor', {})
    cap = max(10, min(100, int(config.get('top_n', 25))))
    groups = {}
    invalid = 0
    mappings = config.get('domains', {})
    now = time.time()
    with open(path, 'rb') as log:
        info = os.fstat(log.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise ValueError('log is not a regular file')
        identity = str(info.st_dev) + ':' + str(info.st_ino)
        rotated = bool(cursor) and (cursor.get('inode') != identity or int(cursor.get('offset', 0)) > info.st_size)
        # Begin at the end on first enable: don't replay a huge historic log or
        # produce stale alerts. Rotation starts at the new file and is reported.
        offset = info.st_size if not cursor else (0 if rotated else int(cursor.get('offset', 0)))
        log.seek(offset)
        raw = log.read(MAX_BYTES)
        end = raw.rfind(b'\n') + 1
        oversized = False
        if not end and len(raw) == MAX_BYTES:
            # A malformed giant line must not pin the cursor forever. Drain a
            # bounded chunk and count it, never send the content to the API.
            end = len(raw)
            oversized = True
        for line in raw[:end].splitlines():
            if len(line) > MAX_LINE or oversized:
                invalid += 1
                continue
            try:
                row = json.loads(line)
                if config['format'] == 'traefik':
                    timestamp = dt.datetime.fromisoformat(str(row['StartUTC']).replace('Z', '+00:00')).timestamp()
                    host = row.get('RequestHost', '')
                    target = row.get('RequestPath', '/')
                    status = int(row['DownstreamStatus'])
                    duration = float(row.get('Duration', 0)) / 1_000_000
                    size = max(0, int(row.get('DownstreamContentSize', 0)))
                else:
                    timestamp = float(row['ts'])
                    request = row.get('request', {})
                    host = request.get('host', '')
                    target = request.get('uri', '/')
                    status = int(row['status'])
                    duration = float(row.get('duration', 0)) * 1000
                    size = max(0, int(row.get('size', 0)))
                if not math.isfinite(timestamp) or not math.isfinite(duration) or duration < 0 or not 100 <= status <= 599 or not now-86400 <= timestamp <= now+60:
                    invalid += 1
                    continue
                host = str(host).lower().split(':')[0].rstrip('.')[:253]
                service = str(mappings.get(host, 'unmapped'))
                minute = int(timestamp // 60) * 60
                key = (minute, service)
                if key not in groups:
                    # Bound group cardinality even if a malformed source invents
                    # request timestamps or there are thousands of domains.
                    if len(groups) >= 2000:
                        invalid += 1
                        continue
                    groups[key] = dict(requests=0, bandwidth=0, statuses={}, histogram=[0]*15, suspicious=0, paths={})
                bucket = groups[key]
                bucket['requests'] += 1
                bucket['bandwidth'] += size
                category = str(status // 100) + 'xx'
                bucket['statuses'][category] = bucket['statuses'].get(category, 0) + 1
                bucket['histogram'][next((i for i, upper in enumerate(BOUNDS) if duration <= upper), 14)] += 1
                # Inspect ephemeral target for scan patterns, but persist no
                # query parameters, credentials, raw IPs, headers or user agents.
                decoded = urllib.parse.unquote(urllib.parse.unquote(str(target)[:4096]))
                bucket['suspicious'] += int(bool(SUSPICIOUS.search(decoded)))
                clean = urllib.parse.urlsplit(str(target)).path[:160]
                # Collapse common identifiers to avoid a path-cardinality bomb.
                clean = re.sub(r'/[0-9a-fA-F-]{8,}(?=/|$)|/\d+(?=/|$)', '/:id', clean)
                clean = ''.join(c for c in clean if c.isprintable()) or '/'
                if config.get('capture_paths', False):
                    label = clean if clean in bucket['paths'] or len(bucket['paths']) < cap else '(other paths)'
                    bucket['paths'][label] = bucket['paths'].get(label, 0) + 1
            except (ValueError, TypeError, KeyError, OverflowError, UnicodeDecodeError):
                invalid += 1
        return dict(cursor=dict(inode=identity, offset=offset+end), backlog_bytes=max(0, info.st_size-offset-end), rotated=rotated, invalid_lines=invalid,
                    groups=[dict(at=minute, service_id=service, **data) for (minute, service), data in groups.items()])


if __name__ == '__main__':
    try:
        print(json.dumps(collect(json.loads(zlib.decompress(base64.b64decode(sys.argv[1])))), separators=(',', ':')))
    except Exception:
        # Never return raw log contents, host paths, credentials or exception data.
        print(json.dumps({'error': 'Cannot read proxy JSON access log. Check Python 3, file permissions, path and format.'}))
        sys.exit(1)
