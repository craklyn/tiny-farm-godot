"""Provider routing and bounded CLI execution, independent of HQ's server.

Codex turns are bounded by wall time, not Claude's exact max-turn count.
Read profiles allow sandboxed local shell reads, rather than Claude Read/Glob/Grep.
"""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import threading
import time
import tomllib

import roots

POLICY_PATH = Path(roots.ROOTS['data']) / 'execution_policy.json'
MODELS = {'fable': 'gpt-6-astra', 'opus': 'gpt-5.6-sol',
          'sonnet': 'gpt-5.6-terra', 'haiku': 'gpt-5.6-luna'}


def load_policy():
    policy = json.loads(POLICY_PATH.read_text())
    if (policy.get('version') != 1 or policy.get('mode') not in ('claude', 'codex')
            or policy.get('default_model') not in MODELS
            or not isinstance(policy.get('background_paused'), bool)
            or not isinstance(policy.get('trial_item'), str)
            or not re.fullmatch(r'[a-zA-Z0-9_-]*', policy['trial_item'])
            or policy.get('mappings') != MODELS):
        raise ValueError('Invalid HQ execution policy; restore version 1 model mappings and launch controls')
    return policy


def set_background_paused(paused, *, by='daniel', reason=''):
    """Atomically change the operator brake without rewriting model routing."""
    if not isinstance(paused, bool):
        raise ValueError('Paused must be true or false')
    reason = str(reason or '').strip()
    if paused and not reason:
        raise ValueError('A reason is required when automatic work is paused')
    policy = load_policy()
    policy['background_paused'] = paused
    policy['background_pause'] = {
        'by': str(by or 'daniel')[:80],
        'at': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'reason': reason[:300] if paused else '',
    }
    POLICY_PATH.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=POLICY_PATH.name + '.', dir=POLICY_PATH.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            json.dump(policy, handle, indent=2)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, POLICY_PATH)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass
    return load_policy()


def resolve_model(requested='', *, provider=None):
    policy = load_policy()
    requested = requested or policy['default_model']
    if provider not in (None, 'claude', 'codex'):
        raise ValueError('Provider must be claude or codex')
    actual_provider = provider or ('codex' if requested in MODELS.values() else policy['mode'])
    if requested in MODELS.values():
        if actual_provider != 'codex':
            raise ValueError('A GPT model requires the Codex provider')
        model = requested
    else:
        alias = next((key for key in MODELS if requested == key or
                      requested.startswith('claude-' + key + '-')), None)
        if alias is None:
            raise ValueError(f'No routing configured for model {requested!r}; update execution policy')
        model = MODELS[alias] if actual_provider == 'codex' else requested
    return {'provider': actual_provider, 'requested_model': requested, 'model': model}


def launch_allowed(*, launch_context='automatic', item='', phase=''):
    policy = load_policy()
    if launch_context not in ('automatic', 'interactive', 'supervised', 'writing_hook'):
        raise ValueError('Unknown launch context')
    if launch_context == 'supervised':
        return bool(item and item == policy['trial_item'] and phase in ('build-worker', 'checker'))
    return launch_context != 'automatic' or not policy['background_paused']


def command_for(prompt, system, tools, route, turns):
    if route['provider'] == 'claude':
        return ['claude', '-p', prompt, '--append-system-prompt', system,
                '--allowedTools', tools, '--max-turns', str(turns),
                '--permission-mode', 'acceptEdits', '--output-format', 'stream-json',
                '--verbose', '--model', route['model']]
    allowed = set(filter(None, re.split(r'[,\s]+', tools or '')))
    if not allowed:
        profile = 'none'
    elif allowed <= {'Read', 'Glob', 'Grep'}:
        profile = 'read'
    elif ({'Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep'} <= allowed
          and allowed <= {'Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep',
                          'MultiEdit', 'NotebookEdit', 'TodoWrite', 'WebFetch', 'WebSearch'}):
        profile = 'write'
    else:
        raise ValueError(f'Unsupported Codex tool restriction: {tools!r}')
    cmd = ['codex', 'exec', '--json', '--ignore-user-config', '--ignore-rules',
           '--ephemeral', '--skip-git-repo-check', '--sandbox',
           'workspace-write' if profile == 'write' else 'read-only', '--model', route['model']]
    disabled = ['view_image', 'apps', 'plugins', 'multi_agent', 'browser_use',
                'computer_use', 'image_generation', 'hooks', 'unbounded_connection_retries',
                'skill_mcp_dependency_install', 'remote_plugin', 'standalone_web_search']
    if profile == 'none':
        disabled.append('shell_tool')
    for feature in disabled:
        cmd += ['--disable', feature]
    return cmd + [system + '\n\n' + prompt]


def check_mcp_config(cwd):
    """Fail closed for inherited MCP configuration; there is no global off flag.

    User config is ignored by the CLI. Project and system config remain possible
    sources; callers must disable/remove their MCP entries before using HQ.
    Do not include config contents in errors because they may contain secrets.
    """
    paths = [Path('/etc/codex/config.toml'), Path('/etc/codex/managed_config.toml')]
    directory = Path(cwd).resolve()
    paths.extend(parent / '.codex' / 'config.toml' for parent in (directory, *directory.parents))
    ignored_user_config = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))) / 'config.toml'
    for path in paths:
        if path.resolve() == ignored_user_config.resolve():
            continue
        try:
            config = tomllib.loads(path.read_text())
        except FileNotFoundError:
            continue
        except (OSError, ValueError) as exc:
            raise ValueError(f'Cannot verify MCP restrictions in {path}; check this configuration before running HQ') from exc
        def has_mcp(value):
            if not isinstance(value, dict):
                return False
            if value.get('mcp_servers'):
                servers = value['mcp_servers']
                if not isinstance(servers, dict) or any(
                        not isinstance(server, dict) or server.get('enabled') is not False
                        for server in servers.values()):
                    return True
            return any(has_mcp(child) for child in value.values() if isinstance(child, dict))
        if has_mcp(config):
            raise ValueError(f'MCP tools may load from {path}; disable each server with enabled=false before running HQ')


class Normalizer:
    def __init__(self, route):
        self.route = route
        self.text = ''
        self.usage = {**route, 'list_usd': None}
        self.error = ''
        self.final = False
        self.stop_reason = None
        self.subtype = None
        self.explicit_final = False

    def feed(self, ev):
        if self.route['provider'] == 'claude':
            if ev.get('type') == 'result':
                self.final = True
                self.text = ev.get('result', '')
                self.stop_reason = ev.get('stop_reason')
                self.subtype = ev.get('subtype')
                self.usage.update(ev.get('usage') or {})
                self.usage['list_usd'] = ev.get('total_cost_usd')
                self.usage['turns'] = ev.get('num_turns')
                if ev.get('is_error'):
                    self.error = self.text or str(ev.get('errors') or 'Claude session failed')
                    if self.stop_reason == 'max_turns' or self.subtype == 'error_max_turns':
                        self.error = 'max_turns: ' + self.error
            return [{**ev, **self.route}]
        kind = ev.get('type', '')
        base = {**self.route, 'raw_event': ev}
        if kind == 'thread.started':
            return [{**base, 'type': 'system', 'subtype': 'init', 'session_id': ev.get('thread_id')}]
        if kind in ('error', 'turn.failed'):
            self.error = str(ev.get('message') or ev.get('error') or 'Codex session failed')
        if kind == 'turn.completed':
            self.final = True
            usage = ev.get('usage') or {}
            cached = usage.get('cached_input_tokens', 0)
            self.usage.update(input_tokens=max(0, usage.get('input_tokens', 0) - cached),
                              cache_read_input_tokens=cached, output_tokens=usage.get('output_tokens', 0))
            return [{**base, 'type': 'result', 'result': self.text, 'usage': self.usage,
                     'total_cost_usd': None, 'is_error': bool(self.error)}]
        item = ev.get('item') or {}
        if kind == 'item.completed' and item.get('type') == 'agent_message':
            phase = item.get('phase') or ev.get('phase')
            if phase in ('final', 'final_answer'):
                self.text = item.get('text', '')
                self.explicit_final = True
            elif phase != 'commentary' and not self.explicit_final:
                # Older CLI events omit phase; their last message is the answer.
                self.text = item.get('text', '')
            return [{**base, 'type': 'assistant', 'message': {'content':
                    [{'type': 'text', 'text': item.get('text', '')}]}}]
        if kind in ('item.started', 'item.completed') and item.get('type') in (
                'command_execution', 'mcp_tool_call', 'file_change', 'web_search'):
            content = ({'type': 'tool_use', 'id': item.get('id'), 'name': item.get('tool') or item['type'],
                        'input': {'command': item.get('command', '')}} if kind == 'item.started' else
                       {'type': 'tool_result', 'tool_use_id': item.get('id'),
                        'content': item.get('aggregated_output', ''),
                        # Keep the provider's structured result. Consumers must not
                        # guess whether a command failed from words in its output.
                        'status': item.get('status'),
                        'exit_code': item.get('exit_code'),
                        'command': item.get('command', ''),
                        'is_error': (item.get('status') == 'failed'
                                     or (isinstance(item.get('exit_code'), int)
                                         and item.get('exit_code') != 0))})
            return [{**base, 'type': 'assistant' if kind == 'item.started' else 'user',
                     'message': {'content': [content]}}]
        return [{**base, 'type': 'system', 'subtype': kind}]


def run_session(prompt, system, tools, model, cwd, timeout, turns, *, phase='', seat='',
                item='', on_event=None, on_start=None, launch_context='automatic'):
    started = time.monotonic()
    route = resolve_model(model)
    result = {**route, 'text': '', 'usage': {**route, 'list_usd': None}, 'error': '',
              'limited': False, 'exit_code': None, 'held': False}
    if not launch_allowed(launch_context=launch_context, item=item, phase=phase):
        return {**result, 'held': True, 'error': 'HQ execution is paused or this supervised item is not nominated'}
    try:
        if route['provider'] == 'codex':
            check_mcp_config(cwd)
        command = command_for(prompt, system, tools, route, turns)
        proc = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, start_new_session=True,
                                env={**os.environ, 'CLAUDE_CODE_DISABLE_AUTOUPDATE': '1'})
    except (OSError, ValueError) as exc:
        return {**result, 'error': str(exc)}
    normalizer = Normalizer(route)
    errors = []
    stderr = []

    def stdout_reader():
        try:
            for line in proc.stdout:
                if not line.strip():
                    continue
                try:
                    event = json.loads(line)
                    if not isinstance(event, dict):
                        raise ValueError('Expected an event object')
                    for normalized in normalizer.feed(event):
                        if on_event:
                            on_event(normalized)
                except (ValueError, TypeError) as exc:
                    errors.append('Malformed CLI event: ' + str(exc))
        except Exception as exc:
            errors.append('Event reader failed: ' + str(exc))

    def stderr_reader():
        for line in proc.stderr:
            stderr.append(line)
            if len(stderr) > 100:
                del stderr[0]

    readers = [threading.Thread(target=stdout_reader, daemon=True),
               threading.Thread(target=stderr_reader, daemon=True)]
    for reader in readers:
        reader.start()
    terminal_error = ''
    try:
        if on_start:
            on_start(proc.pid)
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        terminal_error = f'Session timed out after {timeout} seconds'
    except Exception as exc:
        terminal_error = str(exc)
    finally:
        if terminal_error:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
        for reader in readers:
            reader.join(5)
        if any(reader.is_alive() for reader in readers):
            terminal_error = terminal_error or 'CLI stream did not close after process exit'
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            for reader in readers:
                reader.join(5)
        proc.stdout.close()
        proc.stderr.close()
    error = terminal_error or normalizer.error or ('; '.join(errors))
    if proc.returncode and not error:
        error = ''.join(stderr)[-2000:] or f'CLI exited with code {proc.returncode}'
    if not normalizer.final and not error:
        error = 'CLI exited without a final result'
    if not normalizer.text.strip() and not error:
        error = 'CLI returned an empty final result'
    usage = normalizer.usage
    for key, raw in [('input', 'input_tokens'), ('output', 'output_tokens'),
                     ('cache_read', 'cache_read_input_tokens'), ('cache_write', 'cache_creation_input_tokens')]:
        try:
            usage[key] = int(usage.get(raw) or 0)
        except (TypeError, ValueError):
            usage[key] = 0
            error = error or 'Malformed CLI token usage'
    usage['tokens'] = sum(usage[key] for key in ('input', 'output', 'cache_read', 'cache_write'))
    usage['fresh'] = usage['tokens'] - usage['cache_read']
    usage['seconds'] = round(time.monotonic() - started, 1)
    usage.setdefault('turns', None)
    return {**result, 'text': normalizer.text, 'usage': usage,
            'error': error, 'exit_code': proc.returncode,
            'stop_reason': normalizer.stop_reason, 'subtype': normalizer.subtype,
            'limited': bool(error and re.search(r'usage limit|rate.?limit|quota|too many requests|429',
                                                error, re.I))}
