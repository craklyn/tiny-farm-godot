#!/usr/bin/env python3
"""S-33: several items are worked at once and land one at a time.

Real temporary Git repositories; the model is never called (do_item and the
suites are stubbed). Covers the parallel work phase, the serial landing lane,
rebuilding a stale candidate whose files main never touched, the evidence a
rebuilt candidate may land on, crash recovery of one, and the queue page
showing every item being worked.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import work, drain, integration, server  # noqa: E402
from test_completion import record  # noqa: E402
from test_drain import fake_host, ORG  # noqa: E402

GREEN = {'unit': {'ok': True}, 'integration': {'ok': True}}


class Crash(BaseException):
    pass


class ParallelDrain(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'core.hooksPath', str(self.repo / '.git/hooks'))
        (self.repo / 'sample.txt').write_text('before\n')
        self.git('add', 'sample.txt')
        self.git('commit', '-qm', 'Initial')
        host = fake_host(str(self.root / 'data'))
        host.REPO = str(self.repo)
        host.load_json = lambda path: json.loads(Path(path).read_text())
        work.bind(host)
        self.patches = [patch.object(server, 'REPO', str(self.repo)),
                        patch.object(drain, 'REPO', str(self.repo)),
                        patch.object(drain, 'WORKTREES', str(self.root / 'worktrees')),
                        patch.object(drain, 'TRANSACTIONS', str(self.root / 'transactions')),
                        patch.object(drain, 'DRAIN_STATE', str(self.root / 'runs' / 'drain.json')),
                        patch.object(drain, 'PATCHES', str(self.root / 'patches'))]
        for p in self.patches:
            p.start()
        self.assertEqual(integration.handoff_main(str(self.repo), 'codex/fixture-user',
                                                  confirmed_idle=True), (True, ''))
        # The drain's own worktree lock: Git removes .git/worktrees when its
        # last entry goes, so adds and removes must not interleave.
        self.git_lock = drain._WT_LOCK

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    def git(self, *args, cwd=None):
        return subprocess.run(['git', *args], cwd=cwd or self.repo, capture_output=True,
                              text=True, check=True).stdout.strip()

    def card(self, ident):
        return work.save_item({'id': ident, 'title': 'Change ' + ident, 'owner': 'sam', 'tier': 1,
                               'state': 'waiting_session', 'ask': 'Change a file',
                               'first_action': 'Edit', 'attempts': 0,
                               'created': '2026-09-26T00:00', 'created_ts': 1.0})

    def candidate(self, ident, name, base, text=None):
        """What do_item returns: a checked candidate cut from `base`."""
        worker = self.root / ('worker-' + ident)
        with self.git_lock:
            self.git('worktree', 'add', '--detach', str(worker), base)
        (worker / name).write_text((text or ident) + '\n')
        self.git('add', name, cwd=worker)
        r = record(id=ident, attempt_id=ident, files=[name],
                   patch=self.git('diff', '--cached', '--binary', cwd=worker) + '\n')
        drain.save_patch(ident, r['patch'])
        r['patch_artifact'] = drain.patch_artifact(r['patch'])
        r['candidate'] = {'base': base, 'tree': self.git('write-tree', cwd=worker),
                          'files': drain.git_blobs(str(worker), '', [name]),
                          'base_files': drain.git_blobs(str(worker), base, [name])}
        r['candidate_test_evidence'] = work.evidence_id([r['candidate'], r['candidate_suites']])
        r['check_evidence'] = drain.check_evidence_id(r)
        with self.git_lock:
            self.git('worktree', 'remove', '--force', str(worker))
        return r

    def advance(self, name, text):
        """Someone else lands a commit on local main."""
        other = self.root / ('other-' + name)
        self.git('worktree', 'add', '--detach', str(other), 'main')
        (other / name).write_text(text)
        self.git('add', name, cwd=other)
        self.git('commit', '-qm', 'Another change to ' + name, cwd=other)
        new = self.git('rev-parse', 'HEAD', cwd=other)
        self.assertTrue(integration.advance_main(str(self.repo), new, self.git('rev-parse', 'main')))
        self.git('worktree', 'remove', '--force', str(other))
        return new

    # -- A: the work phase runs side by side --------------------------------

    def test_three_items_are_worked_at_once_and_the_queue_shows_all_three(self):
        cards = [self.card(ident) for ident in ('wa', 'wb', 'wc')]
        both_in = threading.Barrier(3, timeout=10)
        looked = threading.Barrier(3, timeout=10)
        seen, spans = {}, {}

        def worked(item, *args, **kwargs):
            start = time.monotonic()
            item['started'] = work._now_iso()
            work.save_item(item)
            both_in.wait()          # breaks unless all three are running at once
            if item['id'] == 'wa':
                doc = json.loads(Path(drain.DRAIN_STATE).read_text())
                seen['drain'] = doc
                with patch.object(server, 'drain_state', return_value=doc):
                    seen['queue'] = drain.queue_view()
            looked.wait()
            spans[item['id']] = (start, time.monotonic())
            return {'id': item['id'], 'held': True, 'error': '', 'usage': [],
                    'check': None, 'applied': False, 'limited': False}

        with patch.object(drain, 'do_item', side_effect=worked):
            records, done = drain.run_verified_batch(cards, ORG, 'fixture', lambda m: None, jobs=3)
        self.assertEqual(set(records), {'wa', 'wb', 'wc'})
        self.assertLess(max(s for s, _ in spans.values()), min(e for _, e in spans.values()))
        # drain.json names every item being worked, and keeps its old shape.
        doc = seen['drain']
        self.assertEqual({e['item'] for e in doc['items']}, {'wa', 'wb', 'wc'})
        self.assertIn(doc['item'], {'wa', 'wb', 'wc'})
        self.assertEqual(doc['run'], 'fixture')
        # The queue page's "Being worked now" lists all three, none as a lost claim.
        self.assertEqual({row['work_id'] for row in seen['queue']['working']}, {'wa', 'wb', 'wc'})
        self.assertEqual(seen['queue']['held'], [])
        # When the run has finished with them, none is still shown as worked.
        self.assertEqual(json.loads(Path(drain.DRAIN_STATE).read_text())['items'], [])

    def test_a_dry_token_window_starts_nothing_further(self):
        cards = [self.card(ident) for ident in ('wa', 'wb', 'wc', 'wd')]
        started = []

        def limited(item, *args, **kwargs):
            started.append(item['id'])
            return {'id': item['id'], 'limited': True, 'held': False, 'error': '',
                    'usage': [], 'check': None, 'applied': False}

        with patch.object(drain, 'do_item', side_effect=limited):
            records, _ = drain.run_verified_batch(cards, ORG, 'fixture', lambda m: None, jobs=2)
        self.assertEqual(sorted(started), ['wa', 'wb'])
        self.assertEqual(sorted(records), ['wa', 'wb'])

    def test_one_job_works_items_in_turn(self):
        cards = [self.card(ident) for ident in ('wa', 'wb')]
        order = []

        def worked(item, *args, **kwargs):
            order.append(('start', item['id'], threading.current_thread() is threading.main_thread()))
            return {'id': item['id'], 'held': True, 'error': '', 'usage': [],
                    'check': None, 'applied': False, 'limited': False}

        with patch.object(drain, 'do_item', side_effect=worked):
            drain.run_verified_batch(cards, ORG, 'fixture', lambda m: None, jobs=1)
        self.assertEqual(order, [('start', 'wa', True), ('start', 'wb', True)])

    # -- B: serial landing, and the rebuild -----------------------------------

    def run_pair(self, names, texts=(None, None)):
        cards = [self.card('wfirst'), self.card('wsecond')]
        base = self.git('rev-parse', 'main')
        both_in = threading.Barrier(2, timeout=10)
        tested = []

        def worked(item, *args, **kwargs):
            index = 0 if item['id'] == 'wfirst' else 1
            both_in.wait()
            return self.candidate(item['id'], names[index], base, texts[index])

        def suites(cwd=None, files=None):
            tested.append((cwd, self.git('write-tree', cwd=cwd)))
            return GREEN

        with patch.object(drain, 'do_item', side_effect=worked), \
                patch.object(drain, 'run_suites', side_effect=suites):
            records, done = drain.run_verified_batch(cards, ORG, 'fixture', lambda m: None, jobs=2)
        return base, records, done, tested

    def test_two_disjoint_candidates_from_one_base_both_land_the_second_rebuilt(self):
        base, records, done, tested = self.run_pair(['sample.txt', 'another.txt'])
        self.assertEqual(sorted(i['state'] for i in done), ['landed', 'landed'])
        self.assertEqual(self.git('rev-list', '--count', 'main'), '3')
        rebuilt = [i for i in done if i['attempt_outcome']['candidate'].get('rebuilt_from')]
        self.assertEqual(len(rebuilt), 1)
        card = rebuilt[0]
        first = next(i for i in done if i is not card)
        candidate = card['attempt_outcome']['candidate']
        # Rebuilt on the commit the first one made, from the reviewed base.
        self.assertEqual(candidate['base'], first['completion']['sha'])
        self.assertEqual(candidate['rebuilt_from']['base'], base)
        self.assertNotEqual(candidate['tree'], candidate['rebuilt_from']['tree'])
        self.assertEqual(candidate['files'], candidate['rebuilt_from']['files'])
        self.assertEqual(self.git('rev-parse', card['completion']['sha'] + '^'),
                         first['completion']['sha'])
        # Both suites ran on each exact tree landed, the rebuilt one included.
        self.assertEqual(len(tested), 2)
        self.assertEqual(tested[1][1], candidate['tree'])
        self.assertEqual(self.git('rev-parse', 'main^{tree}'), candidate['tree'])
        # The old tree's candidate tests are not on the record as evidence.
        self.assertIsNone(card['attempt_outcome']['candidate_tests'])
        self.assertIsNone(records[card['id']]['candidate_suites'])
        row = card['workflow']['candidates'][-1]
        self.assertEqual(row['rebuilt_from']['base'], base)
        self.assertEqual(self.git('show', 'main:sample.txt'), 'wfirst')
        self.assertEqual(self.git('show', 'main:another.txt'), 'wsecond')

    def test_overlapping_candidates_send_the_second_back_as_stale(self):
        base, records, done, tested = self.run_pair(['sample.txt', 'sample.txt'])
        states = sorted(i['state'] for i in done)
        self.assertEqual(states, ['for_review', 'landed'])
        self.assertEqual(self.git('rev-list', '--count', 'main'), '2')
        held = next(i for i in done if i['state'] == 'for_review')
        self.assertIn('stale', records[held['id']]['why_not'])
        self.assertFalse(records[held['id']]['applied'])
        self.assertNotIn('rebuilt_from', held['attempt_outcome']['candidate'])
        self.assertEqual(len(tested), 1)
        view = work.work_view(work.load_item(held['id']))
        self.assertEqual(view['blocker']['type'], 'stale_base')
        self.assertEqual(view['next_action']['type'], 'reconcile')

    # -- the evidence a rebuilt candidate may land on -------------------------

    def rebuilt(self):
        base = self.git('rev-parse', 'main')
        rec = self.candidate('wtest', 'another.txt', base)
        self.advance('unrelated.txt', 'landed meanwhile\n')
        stale = drain.prepare_integration(dict(rec))
        self.assertEqual(stale, ('', 'stale_base',
                                 'Local main changed; obtain a new candidate, review, and tests.'))
        checkout, kind, why = drain.prepare_integration(rec, rebuild=True)
        self.assertEqual((kind, why), ('', ''))
        rec['integration_checkout'] = checkout
        rec['tree_evidence'] = drain.tree_evidence(rec['files'], repo=checkout)
        return base, rec

    def test_rebuilt_candidate_is_recorded_and_lands_only_on_its_own_suites(self):
        base, rec = self.rebuilt()
        card = self.card('wtest')
        checkout = rec['integration_checkout']
        self.assertEqual(rec['candidate']['rebuilt_from']['base'], base)
        self.assertEqual(rec['candidate']['base'], self.git('rev-parse', 'main'))
        self.assertIsNone(rec['candidate_suites'])
        self.assertEqual(rec['superseded_candidate_suites'], GREEN)
        # The review carries over: it is keyed to the reviewed candidate.
        self.assertEqual(rec['check_evidence'], drain.check_evidence_id(rec))

        def bar(suites):
            rec['test_evidence'] = work.evidence_id([rec['patch'], suites])
            return drain.meets_landing_bar(card, rec, True, suites, repo=checkout)

        self.assertEqual(bar(GREEN), (True, ''))
        # The old tree's green candidate suites never stand in for the landing suites.
        rec['candidate_suites'] = GREEN
        self.assertFalse(bar(None)[0])
        self.assertIn('not run', bar(None)[1])
        red = {'unit': {'ok': True}, 'integration': {'ok': False}}
        self.assertFalse(bar(red)[0])
        # Nor does a rebuild whose files are not the reviewed ones.
        rec['candidate']['files'] = {'another.txt': '100644 blob ' + '0' * 40}
        self.assertEqual(bar(GREEN), (False, "the rebuilt candidate's files differ from the ones that were reviewed"))

    def test_a_file_changed_on_main_is_never_rebuilt(self):
        base = self.git('rev-parse', 'main')
        rec = self.candidate('wtest', 'sample.txt', base)
        self.advance('sample.txt', 'overlap\n')
        self.assertEqual(drain.prepare_integration(rec, rebuild=True)[1], 'stale_base')
        self.assertNotIn('rebuilt_from', rec['candidate'])

    def test_crash_after_committing_a_rebuilt_candidate_recovers_without_a_model(self):
        _base, rec = self.rebuilt()
        card = self.card('wtest')
        rec['suites'] = GREEN
        rec['test_evidence'] = work.evidence_id([rec['patch'], GREEN])
        original = drain.sh

        def interrupted(args, **kwargs):
            got = original(args, **kwargs)
            if args[:2] == ['git', 'commit']:
                raise Crash()
            return got

        with patch.object(drain, 'sh', side_effect=interrupted):
            with self.assertRaises(Crash):
                drain.write_back(card, rec, True, '', GREEN, ORG)
        saved = work.load_item('wtest')
        self.assertIn('rebuilt_from', saved['pending_landing']['candidate'])
        sha = self.git('rev-parse', 'HEAD', cwd=rec['integration_checkout'])
        with patch.object(drain, 'do_item', side_effect=AssertionError('No model')):
            self.assertEqual(work.recover_completion_work(), ['wtest'])
        got = work.load_item('wtest')
        self.assertEqual(got['state'], 'landed')
        self.assertEqual(got['completion']['sha'], sha)
        self.assertEqual(self.git('rev-parse', 'main'), sha)
        self.assertEqual(self.git('rev-list', '--count', 'main'), '3')

    def test_interrupted_verified_rebuild_lands_from_its_checkpoint(self):
        _base, rec = self.rebuilt()
        card = self.card('wtest')
        rec['applied'], rec['suites'] = True, GREEN
        rec['test_evidence'] = work.evidence_id([rec['patch'], GREEN])
        drain.checkpoint(card, rec, 'verified')
        path = Path(drain.TRANSACTIONS) / 'byhand' / 'wtest.json'
        tx = json.loads(path.read_text())
        tx['pid'] = 99999999
        path.write_text(json.dumps(tx))
        self.assertEqual(drain.recover_interrupted_transactions(ORG), 1)
        got = work.load_item('wtest')
        self.assertEqual(got['state'], 'landed')
        self.assertEqual(self.git('rev-parse', 'main^{tree}'), rec['candidate']['tree'])


if __name__ == '__main__':
    unittest.main()
