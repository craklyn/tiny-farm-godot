#!/usr/bin/env python3
"""Offline contract tests; no model account is contacted."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'hq'))
import execution as e


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        # Exercise the real policy loader against a stable fixture, never the
        # operator's current provider, pause setting, or nominated work card.
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.policy_path = Path(folder.name) / 'execution_policy.json'
        self.policy_path.write_text(json.dumps({
            'version': 1, 'mode': 'codex', 'default_model': 'opus',
            'mappings': {'fable': 'gpt-6-astra', 'opus': 'gpt-5.6-sol',
                         'sonnet': 'gpt-5.6-terra', 'haiku': 'gpt-5.6-luna'},
            'background_paused': True, 'trial_item': 'w85a6cc7505a',
        }))
        policy_patch = patch.object(e, 'POLICY_PATH', self.policy_path)
        policy_patch.start()
        self.addCleanup(policy_patch.stop)

    def test_routes_and_hold(self):
        for source, model in e.MODELS.items():
            self.assertEqual(e.resolve_model(source)['model'], model)
            self.assertEqual(e.resolve_model(source, provider='claude')['model'], source)
        self.assertEqual(e.resolve_model()['requested_model'], 'opus')
        self.assertEqual(e.resolve_model('gpt-6-astra')['provider'], 'codex')
        with self.assertRaises(ValueError):
            e.resolve_model('mystery')
        self.assertFalse(e.launch_allowed())
        self.assertTrue(e.launch_allowed(launch_context='writing_hook'))
        self.assertTrue(e.launch_allowed(launch_context='supervised', item='w85a6cc7505a', phase='checker'))
        self.assertFalse(e.launch_allowed(launch_context='supervised', item='other', phase='checker'))
        with patch.object(e.subprocess, 'Popen') as popen:
            self.assertTrue(e.run_session('', '', '', 'haiku', str(ROOT), 1, 1)['held'])
            popen.assert_not_called()

    def test_pause_control_records_reason_and_resumes(self):
        paused = e.set_background_paused(True, by='daniel', reason='Investigating a worker loop')
        self.assertTrue(paused['background_paused'])
        self.assertEqual(paused['background_pause']['by'], 'daniel')
        self.assertEqual(paused['background_pause']['reason'], 'Investigating a worker loop')
        with self.assertRaisesRegex(ValueError, 'reason is required'):
            e.set_background_paused(True, reason='')
        resumed = e.set_background_paused(False, by='daniel')
        self.assertFalse(resumed['background_paused'])
        self.assertEqual(resumed['background_pause']['reason'], '')

    def test_native_events_and_rollback(self):
        policy = e.load_policy()
        policy['mode'] = 'claude'
        with patch.object(e, 'load_policy', return_value=policy):
            route = e.resolve_model('sonnet')
        self.assertEqual(route['provider'], 'claude')
        parser = e.Normalizer(route)
        events = parser.feed({'type': 'result', 'result': 'done',
                              'usage': {'input_tokens': 3}, 'total_cost_usd': .02})
        self.assertEqual(parser.text, 'done')
        self.assertEqual(parser.usage['list_usd'], .02)
        self.assertEqual(events[0]['provider'], 'claude')
        self.assertTrue(parser.final)
        parser.feed({'type': 'result', 'is_error': True, 'result': 'usage limit reached'})
        self.assertIn('usage limit', parser.error)

    def test_project_mcp_guard(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / '.codex/config.toml'
            config.parent.mkdir()
            config.write_text('model = "gpt-6-astra"\n')
            e.check_mcp_config(root)
            config.write_text('[mcp_servers.demo]\ncommand = "false"\n')
            with self.assertRaisesRegex(ValueError, 'MCP tools may load'):
                e.check_mcp_config(root / 'child')
            with patch.object(e.subprocess, 'Popen') as popen:
                result = e.run_session('', '', '', 'haiku', str(root), 1, 1, launch_context='writing_hook')
                self.assertIn('MCP tools may load', result['error'])
                popen.assert_not_called()
            config.write_text('[mcp_servers.demo]\nenabled = false\ncommand = "false"\n')
            e.check_mcp_config(root)
            config.write_text('broken [')
            with self.assertRaisesRegex(ValueError, 'Cannot verify'):
                e.check_mcp_config(root)

    def test_final_answer_excludes_commentary(self):
        for phase in (None, 'commentary'):
            result, events, _ = self.run_fake([
                {'type': 'item.completed', 'item': {'type': 'agent_message', 'phase': phase,
                                                  'text': 'Example {"verdict":"bad"}'}},
                {'type': 'item.completed', 'item': {'type': 'agent_message', 'phase': 'final_answer',
                                                  'text': '{"verdict":"pass"}'}},
                {'type': 'turn.completed', 'usage': {}}])
            self.assertEqual(json.loads(result['text']), {'verdict': 'pass'})
            self.assertIn('Example', events[0]['message']['content'][0]['text'])

    def test_claude_max_turns_preserved(self):
        parser = e.Normalizer(e.resolve_model('sonnet', provider='claude'))
        parser.feed({'type': 'result', 'subtype': 'error_max_turns', 'is_error': True,
                     'stop_reason': 'max_turns', 'num_turns': 5, 'usage': {}})
        self.assertEqual(parser.stop_reason, 'max_turns')
        self.assertEqual(parser.subtype, 'error_max_turns')
        self.assertIn('max_turns', parser.error)

    def test_profiles(self):
        route = e.resolve_model('haiku')
        for tools, sandbox in [('', 'read-only'), ('Read,Glob,Grep', 'read-only'),
                               ('Read,Glob,Grep,Edit,Write,Bash', 'workspace-write')]:
            cmd = e.command_for('p', 's', tools, route, 1)
            self.assertIn('--ignore-user-config', cmd)
            self.assertIn(sandbox, cmd)
            self.assertEqual('shell_tool' in cmd, not bool(tools))
            self.assertIn('plugins', cmd)
            self.assertNotIn('--dangerously-bypass-approvals-and-sandbox', cmd)
        with self.assertRaises(ValueError):
            e.command_for('', '', 'Bash', route, 1)

    def run_fake(self, events, code=0, delay=0, timeout=3):
        with tempfile.TemporaryDirectory() as folder:
            cli = Path(folder) / 'codex'
            cli.write_text('#!/usr/bin/env python3\nimport sys,time\n' +
                           '\n'.join('print(' + repr(json.dumps(ev) if isinstance(ev, dict) else ev) + ',flush=True)' for ev in events) +
                           f'\ntime.sleep({delay})\nsys.exit({code})\n')
            cli.chmod(0o755)
            seen = []
            pids = []
            with patch.dict(os.environ, {'PATH': folder + os.pathsep + os.environ['PATH']}):
                result = e.run_session('p', 's', '', 'haiku', folder, timeout, 1,
                                       on_event=seen.append, on_start=pids.append, launch_context='writing_hook')
            self.assertEqual(len(pids), 1)
            return result, seen, pids[0]

    def test_stream(self):
        result, events, _ = self.run_fake([
            {'type': 'thread.started', 'thread_id': 't'},
            {'type': 'item.started', 'item': {'id': 'c', 'type': 'command_execution', 'command': 'pwd'}},
            {'type': 'item.completed', 'item': {'id': 'c', 'type': 'command_execution',
                                                'command': 'pwd', 'aggregated_output': '/tmp',
                                                'status': 'completed', 'exit_code': 0}},
            {'type': 'rate_limit_event'},
            {'type': 'item.completed', 'item': {'type': 'agent_message', 'text': 'done'}},
            {'type': 'turn.completed', 'usage': {'input_tokens': 100, 'cached_input_tokens': 40, 'output_tokens': 5}}])
        self.assertEqual(result['error'], '')
        self.assertFalse(result['limited'])
        self.assertEqual(result['text'], 'done')
        self.assertEqual(result['usage']['input_tokens'], 60)
        self.assertEqual(result['usage']['cache_read_input_tokens'], 40)
        self.assertIsNone(result['usage']['list_usd'])
        self.assertEqual(result['usage']['tokens'], 105)
        self.assertEqual(result['usage']['fresh'], 65)
        self.assertEqual(events[1]['message']['content'][0]['type'], 'tool_use')
        self.assertEqual(events[2]['message']['content'][0]['type'], 'tool_result')
        self.assertEqual(events[2]['message']['content'][0]['status'], 'completed')
        self.assertEqual(events[2]['message']['content'][0]['exit_code'], 0)
        self.assertEqual(events[2]['message']['content'][0]['command'], 'pwd')
        self.assertFalse(events[2]['message']['content'][0]['is_error'])
        self.assertEqual(events[-1]['type'], 'result')

    def test_errors_and_timeout(self):
        for stream, code, expected in [([], 0, 'without a final'), (['broken'], 0, 'Malformed'),
                                       ([{'type': 'turn.failed', 'error': {'message': 'quota exhausted'}}], 1, 'quota')]:
            result, _, _ = self.run_fake(stream, code)
            self.assertIn(expected, result['error'])
            self.assertEqual(result['provider'], 'codex')
            self.assertEqual(result['limited'], expected == 'quota')
        result, _, pid = self.run_fake([], delay=30, timeout=.05)
        self.assertIn('timed out', result['error'])
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_snapshot_import_and_judge(self):
        # Copy precisely the staged-snapshot dependencies declared by the hook.
        hook = (ROOT / '.githooks/pre-commit').read_text()
        for name in ['hq/execution.py', 'hq/data/execution_policy.json']:
            self.assertIn(name, hook)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ['tools/check_writing.py', 'hq/execution.py', 'hq/data/execution_policy.json']:
                dest = root / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                source = self.policy_path if name == 'hq/data/execution_policy.json' else ROOT / name
                dest.write_bytes(source.read_bytes())
            cli = root / 'codex'
            cli.write_text('#!/usr/bin/env python3\nimport json\nprint(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":\'{"findings": []}\'}}))\nprint(json.dumps({"type":"turn.completed","usage":{}}))\n')
            cli.chmod(0o755)
            script = "import sys; sys.path.insert(0, 'tools'); import check_writing as w; assert w.have_cli(); assert w.judge(['Hello'], 'Read plainly') == {}"
            proc = subprocess.run([sys.executable, '-c', script], cwd=root,
                                  env={**os.environ, 'PATH': folder + os.pathsep + os.environ['PATH']}, capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_actual_hook_preserves_unstaged_cache(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ['.githooks/pre-commit', 'tools/check_writing.py', 'hq/execution.py',
                         'hq/data/execution_policy.json', 'docs/WRITING.md', 'docs/writing_rulings.json']:
                dest = root / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                source = self.policy_path if name == 'hq/data/execution_policy.json' else ROOT / name
                dest.write_bytes(source.read_bytes())
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.STDOUT)
            git('init', '-q')
            fingerprint = subprocess.check_output([sys.executable, '-c',
                "import sys;sys.path.insert(0,'tools');import check_writing as w; print(w.brief_fingerprint())"], cwd=root).decode().strip()
            cache = {'brief': fingerprint, 'verdicts': {'staged-entry': {'verdict': 'ok'}}}
            cachepath = root / 'docs/writing_verdicts.json'
            cachepath.write_text(json.dumps(cache))
            card = root / 'hq/data/work/test.json'
            card.parent.mkdir(parents=True)
            card.write_text(json.dumps({'title': 'Review the new animation', 'state': 'queued'}))
            git('add', '.')
            cache['verdicts']['unstaged-entry'] = {'verdict': 'ok'}
            cachepath.write_text(json.dumps(cache))
            cli = root / 'codex'
            cli.write_text("#!/usr/bin/env python3\nimport json\nprint(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':json.dumps({'findings': []})}}))\nprint(json.dumps({'type':'turn.completed','usage':{}}))\n")
            cli.chmod(0o755)
            proc = subprocess.run(['sh', '.githooks/pre-commit'], cwd=root,
                                  env={**os.environ, 'PATH': folder + os.pathsep + os.environ['PATH']},
                                  capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            staged = json.loads(git('show', ':docs/writing_verdicts.json'))['verdicts']
            working = json.loads(cachepath.read_text())['verdicts']
            self.assertNotIn('unstaged-entry', staged)
            self.assertIn('unstaged-entry', working)
            self.assertIn('staged-entry', staged)
            self.assertEqual(len(staged), 2)
            self.assertEqual(len(working), 3)


if __name__ == '__main__':
    unittest.main()
