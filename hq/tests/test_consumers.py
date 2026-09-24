#!/usr/bin/env python3
"""Execution holds, provider accounting and streamed consumer seams, without CLI calls."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import execution
import drain
import server
import work
import anim


class Consumers(unittest.TestCase):
    def test_job_labels_use_the_visible_test_names(self):
        self.assertEqual(server.JOBS['unit']['label'], 'Unit tests')
        self.assertEqual(server.JOBS['integration']['label'], 'Integration tests')
        pillars = json.loads((Path(__file__).resolve().parents[1] / 'data/pillars.json').read_text())
        demos = {pillar['id']: pillar['demos'] for pillar in pillars['pillars']}
        self.assertEqual(demos['engineering'][0]['label'], 'Run the unit tests')
        self.assertEqual(demos['ops'][0]['label'], 'Where every asset came from')
        with patch.object(server, 'latest_job_result', return_value=None):
            for job in ('unit', 'integration'):
                self.assertEqual(server.eval_measure({'kind': 'job_state', 'job': job})['source_human'],
                                 server.JOBS[job]['label'])

    def test_hold_does_not_claim_or_mutate(self):
        item = {'id': 'held', 'owner': 'sam', 'attempts': 3, 'state': 'doing'}
        original = dict(item)
        with patch.object(execution, 'launch_allowed', return_value=False), \
             patch.object(work, 'save_item') as save, \
             patch.object(execution, 'run_session') as run:
            self.assertFalse(work._process_item(item, {}))
            self.assertFalse(work.prep_question(item, {}))
            self.assertFalse(work._process_response(item, {}))
            self.assertFalse(work._process_capture(item, {}))
            self.assertFalse(work.start_reply('held'))
            self.assertTrue(anim.start_run({})['held'])
            self.assertTrue(anim.start_rework('slug', '')['held'])
            self.assertTrue(drain.do_item(item, {}, '', lambda x: None)['held'])
            save.assert_not_called()
            run.assert_not_called()
        self.assertEqual(original, item)

    def test_dry_run_selects_only_requested_card(self):
        pool = [{'id': name, 'owner': 'sam', 'title': name} for name in ('trial', 'backlog')]
        output = io.StringIO()
        with patch.object(sys, 'argv', ['drain.py', 'trial', '--limit', '1', '--jobs', '1', '--dry-run']), \
             patch.object(work, 'bind'), patch.object(server, 'load_org', return_value={}), \
             patch.object(server, 'seat_model', return_value='sonnet'), \
             patch.object(drain, 'queued', return_value=pool), \
             patch.object(execution, 'run_session') as run, contextlib.redirect_stdout(output):
            self.assertEqual(drain.main(), 0)
        self.assertIn('trial', output.getvalue())
        self.assertNotIn('backlog', output.getvalue())
        run.assert_not_called()

    def test_explicit_nontrial_obeys_background_policy(self):
        with patch.object(drain, 'SUPERVISED_IDS', {'other', 'trial'}):
            for paused in (False, True):
                with patch.object(execution, 'load_policy', return_value={
                        'background_paused': paused, 'trial_item': 'trial'}):
                    context = drain._launch_context('other')
                    self.assertEqual(context, 'automatic')
                    self.assertEqual(execution.launch_allowed(launch_context=context,
                        item='other', phase='build-worker'), not paused)
                    self.assertEqual(drain._launch_context('trial'),
                                     'supervised' if paused else 'automatic')

    def test_retry_once_requires_paused_nominated_trial(self):
        for trial, paused in [('other', True), ('weather', False)]:
            with self.subTest(trial=trial, paused=paused), \
                 patch.object(sys, 'argv', ['drain.py', '--retry-once', 'weather']), \
                 patch.object(execution, 'load_policy', return_value={
                     'background_paused': paused, 'trial_item': trial}), \
                 patch.object(work, 'bind') as bind, \
                 patch.object(execution, 'run_session') as run, \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(drain.main(), 2)
                bind.assert_not_called()
                run.assert_not_called()

    def test_structured_max_turns_can_resume_changed_files(self):
        self.assertTrue(drain.ran_out_of_turns({'stop_reason': 'max_turns'}))
        self.assertTrue(drain.ran_out_of_turns({'subtype': 'error_max_turns'}))
        self.assertFalse(drain.ran_out_of_turns({'error': 'some other failure'}))
        rec = {'error': 'max_turns', 'files': ['example.py'], 'limited': False}
        self.assertEqual(drain.auto_resume_reason({}, rec), 'max_turns')
        self.assertEqual(drain.auto_resume_reason({}, {**rec, 'files': []}), '')

    def test_provider_limits_remain_independent(self):
        with patch.object(server, '_LIMIT', {'until': 0., 'detail': ''}), \
             patch.object(server, '_PROVIDER_LIMITS', {}), \
             patch.object(server, '_save_limit_locked'), patch.object(server, 'append_history'):
            server.note_limit('out of tokens', provider='claude')
            self.assertTrue(server.limited_until('claude'))
            self.assertFalse(server.limited_until('codex'))
            server.note_limit('out of tokens', provider='codex')
            server.clear_limit('codex')
            self.assertTrue(server.limited_until('claude'))
            self.assertFalse(server.limited_until('codex'))

    def test_cost_summary_distinguishes_unpriced_and_free(self):
        unknown = server.sum_usage([{'list_usd': None}, {'list_usd': None}])
        self.assertEqual(drain.cost_summary(unknown), 'dollar cost unavailable for 2 calls')
        mixed = server.sum_usage([{'list_usd': None}, {'list_usd': 1.25}])
        self.assertEqual(drain.cost_summary(mixed), '$1.25 known plus 1 call with unknown dollar cost')
        known = server.sum_usage([{'list_usd': 1.25}, {'list_usd': 0.75}])
        self.assertTrue(drain.cost_summary(known).startswith('$2.00 at API list price'))
        free = server.sum_usage([{'list_usd': 0.0}])
        self.assertTrue(drain.cost_summary(free).startswith('$0.00 at API list price'))

    def test_unknown_cost_is_counted(self):
        total = server.sum_usage([{'tokens': 11, 'list_usd': None}, {'tokens': 7, 'list_usd': 2.5}])
        self.assertEqual(total['list_usd'], 2.5)
        self.assertEqual(total['unknown_cost_calls'], 1)
        self.assertEqual(total['tokens'], 18)
        self.assertIsNone(server.usage_from_cli({'usage': {}})['list_usd'])

    def test_window_filters_provider_and_limit(self):
        now = '2026-09-21T12:00:00'
        rows = [{'at': now, 'provider': 'claude', 'tokens': 999},
                {'at': now, 'provider': 'codex', 'tokens': 23, 'list_usd': None}]
        with patch.object(server, 'read_history', side_effect=lambda kind, n: rows if kind == 'tokens' else []), \
             patch('time.time', return_value=server._parse_iso(now)):
            result = server.token_window(provider='codex')
        self.assertEqual(result['tokens'], 23)
        self.assertEqual(result['unknown_cost_calls'], 1)
        self.assertIsNone(result['dry_spend'])

    def test_stream_keeps_actual_model_and_transcript(self):
        route = {'provider': 'codex', 'requested_model': 'sonnet', 'model': 'gpt-5.6-terra'}
        events = [{'type': 'assistant', **route, 'message': {'content': [{'type': 'text', 'text': 'A real answer'}]}},
                  {'type': 'result', **route, 'usage': {'input_tokens': 7, 'cache_read_input_tokens': 3, 'output_tokens': 2}, 'total_cost_usd': None}]
        def fake_run(*args, **kw):
            self.assertEqual(kw['phase'], 'build-worker')
            self.assertEqual(kw['launch_context'], 'supervised')
            kw['on_start'](123)
            for event in events:
                kw['on_event'](event)
            return {**route, 'text': 'A real answer', 'usage': {**route, 'tokens': 12, 'list_usd': None}, 'exit_code': 0, 'error': ''}
        with tempfile.TemporaryDirectory() as tmp, \
             patch.object(drain, 'WORKERS', tmp), patch.object(drain, 'RUN_ID', 'test'), \
             patch.object(drain, 'SUPERVISED_IDS', {'trial'}), \
             patch.object(execution, 'load_policy', return_value={'background_paused': True, 'trial_item': 'trial'}), \
             patch.object(execution, 'launch_allowed', return_value=True), \
             patch.object(execution, 'resolve_model', return_value=route), \
             patch.object(execution, 'run_session', side_effect=fake_run), \
             patch.object(server, 'record_model_usage'), patch.object(server, 'clear_limit'):
            text, usage, error = drain.run_cli('p', 's', '', 'sonnet', tmp, 30, 2, 'drain-work', 'sam', 'trial')
            self.assertEqual((text, error), ('A real answer', ''))
            path, meta_path = drain._session_paths('drain-work', 'trial')
            meta = json.loads(Path(meta_path).read_text())
            self.assertEqual(meta['model'], 'gpt-5.6-terra')
            self.assertEqual(meta['requested_model'], 'sonnet')
            progress = server._session_progress(path)
            self.assertEqual(progress['tokens'], 12)
            self.assertIsNone(progress['cost'])
            self.assertEqual(server._compact_event(events[0])[0]['text'], 'A real answer')
            self.assertEqual(server._compact_event(events[1])[0]['text'], 'Session finished')

    def test_stream_completion_uses_only_fields_the_provider_supplied(self):
        claude = server._compact_event({'type': 'result', 'subtype': 'success',
                                        'num_turns': 4, 'duration_ms': 12500,
                                        'total_cost_usd': 1.25})[0]
        self.assertEqual(claude, {'kind': 'done',
            'text': 'Session finished: success, 4 turns, 12 s, $1.25'})
        failed = server._compact_event({'type': 'result', 'is_error': True})[0]
        self.assertEqual(failed, {'kind': 'terminal-failure', 'text': 'Session failed'})

    def test_worker_stream_distinguishes_warning_failure_retry_and_finding(self):
        def tool_start(tool_id, command):
            return {'type': 'assistant', 'message': {'content': [{
                'type': 'tool_use', 'id': tool_id, 'name': 'command_execution',
                'input': {'command': command}}]}}
        def tool_end(tool_id, command, output, status, exit_code):
            return {'type': 'user', 'message': {'content': [{
                'type': 'tool_result', 'tool_use_id': tool_id, 'command': command,
                'content': output, 'status': status, 'exit_code': exit_code,
                'is_error': status == 'failed'}]}}

        with tempfile.TemporaryDirectory() as tmp, patch.object(server, 'WORKERS_DIR', tmp):
            run = Path(tmp) / 'run'
            run.mkdir()
            (run / 'work.json').write_text(json.dumps({'phase': 'drain-work'}))
            events = [
                tool_start('warning', 'git status'),
                tool_end('warning', 'git status',
                         'Failed to create stream fd: Operation not permitted', 'completed', 0),
                tool_start('first', 'python3 test_example.py'),
                tool_end('first', 'python3 test_example.py', 'one assertion failed', 'failed', 1),
                tool_start('retry', 'python3 test_example.py'),
                tool_end('retry', 'python3 test_example.py', 'all checks passed', 'completed', 0),
            ]
            (run / 'work.jsonl').write_text(''.join(json.dumps(event) + '\n' for event in events))
            lines = server.worker_events('run', 'work')['lines']
            kinds = [line['kind'] for line in lines]
            self.assertIn('warning', kinds)
            self.assertIn('command-failure', kinds)
            self.assertIn('recovered', kinds)
            self.assertNotIn('terminal-failure', kinds)

            finding = {'verdict': 'fail', 'summary': 'not ready', 'findings': [{
                'what': 'The saved value is lost', 'where': 'hq/server.py:1',
                'fix': 'Preserve the stored field'}]}
            (run / 'review.json').write_text(json.dumps({'phase': 'drain-check'}))
            (run / 'review.jsonl').write_text(json.dumps({
                'type': 'assistant', 'message': {'content': [{
                    'type': 'text', 'text': json.dumps(finding)}]}}) + '\n')
            review = server.worker_events('run', 'review')['lines']
            self.assertEqual(review[0]['kind'], 'finding')
            self.assertIn('The saved value is lost', review[0]['text'])

    def test_worker_header_uses_terminal_metadata_not_command_output(self):
        now = __import__('time').time()
        with tempfile.TemporaryDirectory() as tmp, \
             patch.object(server, 'WORKERS_DIR', tmp), \
             patch.object(work, 'items', return_value=[]):
            run = Path(tmp) / 'run'
            run.mkdir()
            base = {'started_ts': now, 'started': 'now', 'finished': 'now',
                    'phase': 'drain-work', 'seat': 'sam'}
            (run / 'clean.json').write_text(json.dumps({**base, 'error': ''}))
            (run / 'clean.jsonl').write_text(json.dumps({
                'type': 'user', 'message': {'content': [{
                    'type': 'tool_result', 'is_error': True, 'status': 'failed',
                    'exit_code': 1, 'content': 'test failed'}]}}) + '\n')
            (run / 'broken.json').write_text(json.dumps({**base, 'error': 'CLI exited with code 1'}))
            (run / 'broken.jsonl').write_text('')
            states = {row['name']: row['state'] for row in server.worker_sessions()}
            self.assertEqual(states['clean'], 'finished')
            self.assertEqual(states['broken'], 'failed')

    def test_worker_progress_marks_a_blocking_review_finding(self):
        finding = {'verdict': 'concerns', 'summary': 'needs another pass', 'findings': [{
            'what': 'The second candidate cannot land', 'where': 'docs/plan.md:17',
            'fix': 'Rebuild it against the new parent'}]}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'item-drain-check.jsonl'
            path.write_text(json.dumps({'type': 'assistant', 'message': {'content': [{
                'type': 'text', 'text': json.dumps(finding)}]}}) + '\n')
            progress = server._session_progress(str(path), 'drain-check')
            self.assertTrue(progress['has_finding'])
            self.assertIn('Review finding:', progress['last'])


if __name__ == '__main__':
    unittest.main()
