import importlib.util
import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('traffic', Path(__file__).parents[2] / 'backend/lib/raildock/http_traffic.py')
traffic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(traffic)

class TrafficTest(unittest.TestCase):
    def setUp(self):
        self.file = tempfile.NamedTemporaryFile(mode='wb+', delete=False)
        self.config = dict(path='/var/log/proxy.jsonl', format='caddy', cursor={}, domains={'app.example.test': '42'}, capture_paths=True)
        self.open_patch = patch.object(traffic, 'open', lambda *_: open(self.file.name, 'rb'), create=True)
        self.real_patch = patch.object(traffic.os.path, 'realpath', lambda value: value)
        self.open_patch.start()
        self.real_patch.start()
        self.config['cursor'] = traffic.collect(self.config)['cursor']
    def tearDown(self):
        self.open_patch.stop()
        self.real_patch.stop()
        self.file.close()
        os.unlink(self.file.name)
    def add(self, **overrides):
        row = dict(ts=time.time(), request=dict(host='app.example.test', uri='/items/123?token=SECRET', remote_ip='198.51.100.1'), status=200, duration=.018, size=256)
        row.update(overrides)
        self.file.write(json.dumps(row).encode()+b'\n')
        self.file.flush()
    def test_incremental_counts_histograms_and_privacy(self):
        self.add()
        self.add(status=503, request=dict(host='app.example.test',uri='/.env?key=SECRET'))
        result=traffic.collect(self.config)
        bucket=result['groups'][0]
        self.assertEqual(bucket['requests'],2)
        self.assertEqual(bucket['statuses'],{'2xx':1,'5xx':1})
        self.assertEqual(bucket['histogram'][3],2)
        self.assertEqual(bucket['suspicious'],1)
        self.assertEqual(bucket['paths']['/items/:id'],1)
        self.assertNotIn('SECRET',json.dumps(result))
        self.assertNotIn('198.51.100',json.dumps(result))
        self.config['cursor']=result['cursor']
        self.assertEqual(traffic.collect(self.config)['groups'],[])
    def test_partial_lines_are_not_consumed(self):
        self.file.write(b'{"ts":')
        self.file.flush()
        old=self.config['cursor']['offset']
        self.assertEqual(traffic.collect(self.config)['cursor']['offset'],old)
    def test_bad_lines_counted_without_exposing_contents(self):
        self.file.write(b'SECRET bad json\n')
        self.file.flush()
        result=traffic.collect(self.config)
        self.assertEqual(result['invalid_lines'],1)
        self.assertNotIn('SECRET',json.dumps(result))
    def test_rotation_is_reported(self):
        self.add()
        self.config['cursor']['inode']='old-file'
        result=traffic.collect(self.config)
        self.assertTrue(result['rotated'])
        self.assertEqual(result['groups'][0]['requests'],1)
    def test_paths_opt_in_and_cardinality_capped(self):
        self.config['capture_paths']=False
        self.add()
        self.assertEqual(traffic.collect(self.config)['groups'][0]['paths'],{})
        self.config['capture_paths']=True
        for index in range(100):self.add(request=dict(host='app.example.test',uri='/path'+str(index)))
        result=traffic.collect(self.config)['groups'][0]
        self.assertLessEqual(len(result['paths']),26)
        self.assertEqual(sum(result['paths'].values()),101)
    def test_first_enable_skips_history(self):
        self.add()
        self.config['cursor']={}
        self.assertEqual(traffic.collect(self.config)['groups'],[])
    def test_bounded_reads_report_backlog_without_double_counting(self):
        for _ in range(100):self.add()
        total=0
        with patch.object(traffic,'MAX_BYTES',2048):
            for _ in range(50):
                result=traffic.collect(self.config)
                total+=sum(group['requests'] for group in result['groups'])
                self.config['cursor']=result['cursor']
                if not result['backlog_bytes']:break
        self.assertEqual(total,100)
    def test_traefik_nanoseconds(self):
        import datetime
        self.config['format']='traefik'
        self.file.write(json.dumps(dict(StartUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),RequestHost='app.example.test',RequestPath='/',DownstreamStatus=201,Duration=2000000,DownstreamContentSize=20)).encode()+b'\n')
        self.file.flush()
        self.assertEqual(traffic.collect(self.config)['groups'][0]['histogram'][1],1)

if __name__=='__main__':unittest.main()
