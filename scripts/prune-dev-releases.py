#!/usr/bin/env python3
"""Preview or prune generated v0.0.0-main prereleases, preserving an audit backup."""
import argparse
import json
import pathlib
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', default='mona-chen/raildock')
parser.add_argument('--keep', type=int, default=5)
parser.add_argument('--keep-oldest', type=int, default=3)
parser.add_argument('--backup', default='release-cleanup-backup.json')
parser.add_argument('--expected-count', type=int, help='Required for --apply; abort if the reviewed count changed')
parser.add_argument('--apply', action='store_true', help='Delete exactly the eligible releases and tags shown in this run')
args = parser.parse_args()
if args.keep < 1 or args.keep_oldest < 0:
    parser.error('--keep must be at least 1 and --keep-oldest non-negative')

def gh(*parts):
    return subprocess.check_output(['gh', *parts], text=True)

releases = json.loads(gh('api', '--paginate', '--slurp', f'repos/{args.repo}/releases'))
releases = [release for page in releases for release in page]
eligible = sorted((r for r in releases if re.fullmatch(r'v0\.0\.0-main-[0-9a-f]{7,40}', r['tag_name']) and r['prerelease'] and not r['draft'] and not r.get('assets')), key=lambda r: r.get('published_at') or r['created_at'], reverse=True)
candidates = eligible[args.keep:len(eligible) - args.keep_oldest if args.keep_oldest else len(eligible)]
if args.apply and (args.expected_count is None or len(candidates) != args.expected_count):
    parser.error('Deletion count differs from the reviewed --expected-count')
backup = pathlib.Path(args.backup)
if backup.exists():
    parser.error('Backup already exists; choose a new --backup path to preserve the previous plan')
all_refs = json.loads(gh('api', f'repos/{args.repo}/git/matching-refs/tags'))
refs = {r['ref'][len('refs/tags/'):] : r for r in all_refs}

backup.write_text(json.dumps({'repository': args.repo, 'keep_newest': args.keep, 'keep_oldest': args.keep_oldest, 'releases': candidates, 'refs': refs}, indent=2) + '\n')
print(f"{'DELETE' if args.apply else 'PREVIEW'}: {len(candidates)} generated prereleases and their tags; keep newest {args.keep} and oldest {args.keep_oldest}.")
def remove(release):
    tag = release['tag_name']
    current = json.loads(gh('api', f"repos/{args.repo}/releases/{release['id']}"))
    current_ref = json.loads(gh('api', f"repos/{args.repo}/git/ref/tags/{tag}"))
    if current['updated_at'] != release['updated_at'] or current.get('assets') or current_ref['object']['sha'] != refs[tag]['object']['sha']:
        raise RuntimeError(f'Release or tag changed; refused {tag}')
    gh('api', '--method', 'DELETE', f"repos/{args.repo}/releases/{release['id']}")
    gh('api', '--method', 'DELETE', f'repos/{args.repo}/git/refs/tags/{tag}')
    return tag

if args.apply:
    with ThreadPoolExecutor(max_workers=4) as pool:
        for tag in pool.map(remove, candidates):
            print(f'Deleted {tag}', flush=True)
else:
    for release in candidates:
        print(release['tag_name'])
print(f'Audit backup: {backup}')
