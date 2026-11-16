import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('flows', Path(__file__).parents[2]/'backend/lib/raildock/network_flows.py')
flows = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flows)


def container(name, address, pid):
    return dict(Name=name, Id=name, State=dict(Running=True, Pid=pid), HostConfig=dict(NetworkMode='bridge'), NetworkSettings=dict(Networks={'test':dict(IPAddress=address)}))


class FlowTest(unittest.TestCase):
    def setUp(self):
        self.containers=[container('/api.web.1','172.18.0.2',100),container('/dokku.postgres.db','172.18.0.3',101)]
        self.config=dict(services={'1':['api'],'2':['dokku.postgres.db']},links=[dict(id='link',**{'from':'1','to':'2'})])

    def sample(self, sent, received, previous=None, now=100, cookie='abc'):
        line=f'0 0 172.18.0.2:50000 172.18.0.3:5432 ino:55 sk:{cookie} cubic bytes_sent:{sent} bytes_received:{received}'
        with patch.object(flows.os,'readlink',return_value='net:[123]'):
            return flows.measure(self.containers,self.config,previous or {},read=lambda args:line,now=now)

    def test_initial_totals_are_not_claimed_as_new_traffic(self):
        cursor, rows=self.sample(50000,70000)
        self.assertEqual(rows[0]['state'],'warming')
        self.assertEqual(rows[0]['sent_bytes'],0)

    def test_only_counter_increases_become_directional_activity(self):
        cursor,_=self.sample(50000,70000)
        _,rows=self.sample(50120,70400,cursor,110)
        self.assertEqual(rows[0]['state'],'sampled')
        self.assertEqual((rows[0]['sent_bytes'],rows[0]['received_bytes']),(120,400))
        self.assertEqual(rows[0]['connections'],1)
        self.assertEqual(rows[0]['window_seconds'],10)

    def test_idle_sockets_and_counter_resets_do_not_create_activity(self):
        cursor,_=self.sample(50000,70000)
        for sent,received in [(50000,70000),(0,0)]:
            _,rows=self.sample(sent,received,cursor,110)
            self.assertEqual((rows[0]['sent_bytes'],rows[0]['received_bytes']),(0,0))

    def test_socket_reuse_or_stale_baselines_never_animate_old_bytes(self):
        cursor,_=self.sample(10,10)
        for cookie,now in [('def',110),('abc',400)]:
            _,rows=self.sample(99999,99999,cursor,now,cookie)
            self.assertEqual(rows[0]['state'],'warming')
            self.assertEqual(rows[0]['sent_bytes'],0)

    def test_reenabling_resets_baseline_instead_of_counting_disabled_traffic(self):
        cursor,_=self.sample(10,10)
        self.config['epoch']='new-policy'
        _,rows=self.sample(9999,9999,cursor,110)
        self.assertEqual(rows[0]['state'],'warming')
        self.assertEqual(rows[0]['sent_bytes'],0)

    def test_failed_namespace_read_is_unavailable_not_idle(self):
        with patch.object(flows.os,'readlink',side_effect=OSError):
            _,rows=flows.measure(self.containers,self.config,{},now=100)
        self.assertEqual(rows[0]['state'],'unavailable')

    def test_addresses_and_ports_do_not_leave_the_host(self):
        cursor,_=self.sample(10,10)
        _,rows=self.sample(20,20,cursor,110)
        self.assertNotIn('172.18',str(rows))
        self.assertNotIn('5432',str(rows))
        self.assertNotIn('172.18',str(cursor))

    def test_ipv6_and_mapped_ipv4_endpoint_parsing(self):
        self.assertEqual(flows.endpoint('[::ffff:172.18.0.3]:5432'),('172.18.0.3',5432))
        self.assertEqual(flows.endpoint('[fd00::5]:443'),('fd00::5',443))


if __name__=='__main__':unittest.main()
