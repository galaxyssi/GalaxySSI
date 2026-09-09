"""Exercise actual inbound timing hooks with isolated transport/storage doubles."""

from contextlib import ExitStack
from dataclasses import asdict
import json
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import agent_latency
import link_protocol
import mqtt_bridge
from test_agent_latency import MemorySink


class MqttIngressTimingTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.ns = 100_000_000
        self.sink = MemorySink()
        self.tracer = agent_latency.AgentLatencyTracer(self.sink, monotonic_ns=lambda: self.ns)
        self.stack.enter_context(patch('agent_latency.tracer', return_value=self.tracer))
        self.stack.enter_context(patch.object(mqtt_bridge, 'timing_now_ns', side_effect=lambda: self.ns))
        self.client = {'client_route_id': 'route', 'signal_name': 'phone', 'link_secret': 'A' * 43}
        self.wire = json.dumps({'scheme': 'signal', 'from': 'phone', 'to': 'desktop', 'body': 'private-ciphertext'}).encode()
        self.payload = {'type': 'agent_task', 'client_route_id': 'route', 'conversation_id': 'private-conversation',
                        'task_id': 'private-task', 'turn_id': 'private-turn', 'content': 'private-prompt'}
        self.envelope = link_protocol.make_envelope(self.payload, source_id='phone', target_id='desktop',
                                                   conversation_id='private-conversation')
        self.resolve = self.mock('_resolve_inbound_topic', side_effect=lambda _: self.advance(5, ('client', self.client)))
        self.open = self.mock('open_wire_packet', side_effect=lambda *_: self.advance(7, self.wire))
        self.mock('_signal_ciphertext_digest', side_effect=lambda _: self.advance(3, 'digest'))
        self.lookup = self.mock('message_for_ciphertext', side_effect=lambda *_: self.advance(11, ''))
        self.decrypt = self.mock('decrypt_signal_envelope', side_effect=lambda *a, **k: self.advance(13, self.envelope))
        self.mock('desktop_id', return_value='desktop')
        self.mock('desktop_name', return_value='Test Desktop')
        self.mock('bind_ciphertext', side_effect=lambda *_: self.advance(17, None))
        self.claim = self.mock('claim_message', return_value=True)
        for name in ('touch_client', 'complete_message'):
            self.mock(name)
        self.publish = self.mock('_publish_phone_payload', return_value=True)
        self.stack.enter_context(patch('blob_input_bridge.persist_before_ack'))
        self.stack.enter_context(patch('agent_worker_mqtt.route_worker_payload', return_value=True))
        self.log = self.stack.enter_context(patch.object(mqtt_bridge, 'log'))

    def mock(self, name, **kwargs):
        return self.stack.enter_context(patch.object(mqtt_bridge, name, **kwargs))

    def advance(self, ms, result):
        self.ns += ms * 1_000_000
        return result

    def run_packet(self, received=10_000_000):
        msg = SimpleNamespace(topic='private-mailbox', payload=b'outer-packet',
                              received_at_ns=received, received_at_ms=1)
        mqtt_bridge._process_message(SimpleNamespace(), None, msg)

    def metrics(self):
        return agent_latency.summarize(self.sink.points)['metrics']

    def test_authenticated_task_phase_durations_and_privacy(self):
        self.run_packet()
        self.log.error.assert_not_called()
        expected = {'ingress_queue': 90, 'route_resolve': 5, 'wire_open': 7, 'wire_prepare': 3,
                    'replay_lookup': 11, 'signal_decrypt': 13, 'inbound_accept': 17, 'receive_queue': 116}
        for phase, duration in expected.items():
            with self.subTest(phase=phase):
                metric = self.metrics()[f'desktop_{phase}_ms']
                self.assertEqual((1, duration), (metric['count'], metric['p95_ms']))
        self.publish.assert_called_once()
        raw = json.dumps([asdict(p) for p in self.sink.points])
        for secret in ('private-task', 'private-conversation', 'private-turn', 'private-prompt',
                       'private-mailbox', 'private-ciphertext', self.client['link_secret']):
            self.assertNotIn(secret, raw)

    def test_direct_caller_without_receive_stamp_has_zero_queue(self):
        self.run_packet(received=0)
        self.assertEqual(0, self.metrics()['desktop_ingress_queue_ms']['p95_ms'])

    def test_unresolvable_route_has_no_authenticated_task_timings(self):
        self.resolve.side_effect = None
        self.resolve.return_value = None
        self.run_packet()
        self.assertEqual([], self.sink.points)
        self.open.assert_not_called()

    def test_decrypt_failure_cannot_emit_successful_phases(self):
        self.decrypt.side_effect = ValueError('invalid Signal packet')
        self.run_packet()
        self.assertEqual([], self.sink.points)
        self.publish.assert_not_called()

    def test_sender_or_route_mismatch_cannot_attribute_task_timings(self):
        self.envelope['source_id'] = 'another-phone'
        self.run_packet()
        self.assertEqual([], self.sink.points)
        self.envelope['source_id'] = 'phone'
        self.envelope['payload']['client_route_id'] = 'another-route'
        self.run_packet()
        self.assertEqual([], self.sink.points)

    def test_encrypted_replay_does_not_redecrypt_or_count_as_new_task(self):
        self.lookup.side_effect = None
        self.lookup.return_value = 'seen-message'
        self.mock('previous_acknowledgement', return_value={'status': 'completed', 'receipt_required': False})
        self.run_packet()
        self.assertEqual([], self.sink.points)
        self.decrypt.assert_not_called()

    def test_post_decrypt_duplicate_has_no_new_task_sample(self):
        self.claim.return_value = False
        self.mock('previous_acknowledgement', return_value={'status': 'accepted'})
        self.run_packet()
        self.assertEqual([], self.sink.points)
        self.publish.assert_called_once()

    def test_diagnostic_failure_does_not_prevent_acceptance(self):
        with patch('agent_latency.tracer', side_effect=OSError('diagnostics unavailable')):
            self.run_packet()
        self.log.error.assert_not_called()
        self.publish.assert_called_once()
        self.claim.assert_called_once()

    def test_fragment_timing_belongs_only_to_completing_packet(self):
        assembled = self.wire.decode()
        self.wire = json.dumps({'scheme': 'signal-chunk', 'protocol': link_protocol.PROTOCOL_NAME,
                                'version': link_protocol.PROTOCOL_VERSION, 'from': 'phone', 'to': 'desktop'}).encode()
        with patch.object(mqtt_bridge.inbound_chunk_assembler, 'accept', side_effect=[None, assembled]):
            self.run_packet()
            self.assertEqual([], self.sink.points)
            self.decrypt.assert_not_called()
            self.ns = 500_000_000
            self.run_packet(received=400_000_000)
        self.decrypt.assert_called_once()
        self.assertEqual(100, self.metrics()['desktop_ingress_queue_ms']['p95_ms'])
        self.assertEqual(7, self.metrics()['desktop_wire_open_ms']['p95_ms'])

    def test_repeated_task_does_not_double_count_phase_samples(self):
        self.run_packet()
        self.run_packet()
        self.assertEqual(1, self.metrics()['desktop_ingress_queue_ms']['count'])
        self.assertEqual(90, self.metrics()['desktop_ingress_queue_ms']['p95_ms'])


if __name__ == '__main__':
    unittest.main()
