#!/usr/bin/env python3
"""Completion is verified once; failed repairs and legacy records cannot loop."""
import copy
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import work
import drain
import server
from test_drain import fake_host, ORG


def result(status='complete', items=None):
    return 'The requested reading is finished.\n' + work.FOLLOW_MARK + '\n' + json.dumps({
        'outcome': {'status': status, 'reason': 'A dependency is missing.' if status == 'blocked' else ''},
        'items': items or []})


def record(**over):
    r = {'id': 'wtest', 'attempt_id': 'attempt1', 'seat': 'sam', 'model': 'fixture', 'usage': [],
         'result': result(), 'patch': '', 'files': [], 'stat': '', 'error': '', 'limited': False,
         'check': {'verdict': 'pass', 'complete': True, 'read': True, 'findings': []}}
    r.update(over)
    r['candidate'] = {'tree':'fixture-tree','files':{},'base_files':{}}
    r['candidate_unchanged'] = True
    r['candidate_suites'] = {'unit':{'ok':True},'integration':{'ok':True}} if r['files'] else None
    r['candidate_test_evidence'] = work.evidence_id([r['candidate'],r['candidate_suites']])
    r['check_evidence'] = work.evidence_id([r['result'], r['patch'],r['candidate']])
    return r


class Completion(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        host = fake_host(self.tmp.name)
        host.load_json = lambda path: json.loads(Path(path).read_text())
        work.bind(host)
        (Path(host.DATA) / 'completion_reconciliation.json').write_bytes(
            (Path(work.__file__).parent / 'data/completion_reconciliation.json').read_bytes())
        self.card = {'id': 'wtest', 'title': 'Read the records', 'owner': 'sam', 'tier': 0,
                     'state': 'doing', 'ask': 'Read', 'first_action': 'Read', 'attempts': 0}
    def tearDown(self):
        self.tmp.cleanup()

    def test_reading_completion_and_repeat_are_idempotent(self):
        fu = {'title': 'Fix the image', 'owner': 'sam', 'level': 'task', 'tier': 1,
              'first_action': 'Fix it', 'why': 'The reading found a defect'}
        self.card['follow_ups'] = [dict(fu,title='Obsolete follow-up')]
        r = record(result=result(items=[fu]))
        got = drain.write_back(self.card, r, False, 'nothing changed', None, ORG)
        self.assertEqual(got['state'], 'landed')
        self.assertEqual(work.completion_assessment(got)[0], 'completed')
        child = [i for i in work.items() if i['id'] != 'wtest'][0]
        self.assertEqual(child['title'],'Fix the image')
        child['state'] = 'accepted'; work.save_item(child)
        drain.write_back(got, r, False, '', None, ORG)
        self.assertEqual(len(work.items()), 2)
        self.assertEqual(got['attempts'], 1)
        self.assertEqual(len(got['spawned']), 1)

    def test_completion_replays_after_followup_filing_is_interrupted(self):
        fu = {'title': 'Fix the image', 'owner': 'sam', 'level': 'task', 'tier': 1,
              'first_action': 'Fix it', 'why': 'The reading found a defect'}
        r = record(result=result(items=[fu]))
        original = work._file_follow_ups
        def interrupted(*args, **kwargs):
            original(*args, **kwargs)
            raise RuntimeError('interrupted before parent save')
        with patch.object(work, '_file_follow_ups', side_effect=interrupted):
            with self.assertRaises(RuntimeError):
                drain.write_back(self.card,r,False,'nothing changed',None,ORG)
        saved = json.loads(Path(work._item_path('wtest')).read_text())
        stamp = saved['completion']['at']
        got = drain.write_back(saved,r,False,'nothing changed',None,ORG)
        self.assertEqual(len(work.items()),2)
        self.assertEqual(len(got['spawned']),1)
        self.assertEqual(got['completion']['at'],stamp)

    def test_tier_zero_uses_the_checked_worker_path(self):
        with patch.object(work.execution,'launch_allowed',return_value=True), \
             patch.object(drain,'do_item',return_value=record()) as runner:
            self.assertTrue(work._process_item(self.card,ORG))
            runner.assert_called_once()
            self.assertEqual(self.card['state'],'landed')

    def test_incomplete_error_envelope_and_stale_check_rejected(self):
        for r in [record(result=result('blocked')), record(result=result('unfinished')),
                  record(error='exhausted'), record(limited=True), record(result='{"result":"raw"}'),
                  record(result=''), record(check={'verdict':'pass','complete':True,'read':True,'findings':[{'what':'defect'}]})]:
            self.assertFalse(drain.meets_landing_bar(self.card, r, False, None)[0])
        r = record();r['result'] += 'changed'
        self.assertFalse(drain.meets_landing_bar(self.card, r, False, None)[0])

    def test_checker_failure_is_the_recorded_landing_reason(self):
        r = record(check={'verdict': 'fail', 'read': True, 'complete': False,
                          'findings': [{'what': 'The assertion is wrong.'}]})
        self.assertEqual(drain.meets_landing_bar(self.card, r, False, None)[1],
                         'the read of it says this should not go in as it stands')
        got = drain.write_back(self.card, r, False, '', None, ORG)
        self.assertEqual(got['diff']['why_not_landed'],
                         'the read of it says this should not go in as it stands')

    def test_checker_failure_outweighs_disproved_owner_blocker(self):
        r = record(result=result('blocked'), check={
            'verdict': 'fail', 'read': True, 'complete': False,
            'findings': [{'what': 'The missing dependency is already present.'}]})
        got = drain.write_back(self.card, r, False, '', None, ORG)
        self.assertEqual(got['diff']['why_not_landed'],
                         'the read of it says this should not go in as it stands')
        self.assertEqual(got['repair_hold'], got['diff']['why_not_landed'])

    def test_new_attempt_keeps_previous_checker_result(self):
        first = record(result=result('blocked'), check={
            'verdict': 'fail', 'read': True, 'complete': False,
            'findings': [{'what': 'Remove the unrelated change.',
                          'where': 'docs/writing_verdicts.json:2911',
                          'fix': 'Remove the unrelated change.'}]})
        got = drain.write_back(self.card, first, False, '', None, ORG)
        self.assertNotIn('prior_checks', got)
        second = record(attempt_id='attempt2', result=result('blocked'), check={
            'verdict': 'fail', 'read': True, 'complete': False,
            'findings': [{'what': 'The run count is missing.'}]})
        got = drain.write_back(got, second, False, '', None, ORG)
        self.assertEqual([row['attempt_id'] for row in got['prior_checks']], ['attempt1'])
        self.assertEqual(got['prior_checks'][0]['findings'], first['check']['findings'])
        self.assertEqual(got['check']['attempt_id'], 'attempt2')
        drain.write_back(got, second, False, '', None, ORG)
        self.assertEqual(len(got['prior_checks']), 1)

    def test_one_repair_then_hold(self):
        r = record(check={'verdict':'concerns','read':True,'complete':False,'findings':[{'what':'missing answer'}]})
        got = drain.write_back(self.card, r, False, '', None, ORG)
        self.assertEqual(got['state'], 'waiting_session')
        self.assertEqual(got['owner'], 'sam')
        self.assertEqual(len(got['prior_results']), 1)
        self.assertEqual(len(got['prior_checks']), 1)
        r['attempt_id'] = 'attempt2'
        got = drain.write_back(got, r, False, '', None, ORG)
        self.assertEqual(got['state'], 'for_review')
        self.assertTrue(got['repair_hold'])
        with patch.object(work, 'items', return_value=[got]):
            self.assertEqual(drain.queued(), [])
        self.assertFalse(drain.auto_resume_reason(got, {'error':'it used all 60 of its turns','files':['x']}))

    def test_blocked_is_not_repaired(self):
        r = record(result=result('blocked'), check={'verdict':'fail','read':True,'findings':[]})
        got = drain.write_back(self.card,r,False,'',None,ORG)
        self.assertEqual(got['state'],'for_review')
        self.assertNotIn('automatic_repairs',got)

    def test_applied_diff_evidence_and_failed_commit(self):
        self.card['tier'] = 1
        r = record(files=['sample.txt'], patch='test patch')
        r['integration_checkout'] = self.tmp.name  # The commit boundary is mocked here.
        suites = {'unit':{'ok':True},'integration':{'ok':True}}
        with patch.object(server, 'REPO', self.tmp.name):
            Path(self.tmp.name,'sample.txt').write_text('tested')
            r['candidate']['files'] = drain.git_blobs(self.tmp.name,'',r['files'])
            r['candidate_test_evidence'] = work.evidence_id([r['candidate'],r['candidate_suites']])
            r['check_evidence'] = work.evidence_id([r['result'],r['patch'],r['candidate']])
            r['tree_evidence'] = drain.tree_evidence(r['files'])
            r['test_evidence'] = work.evidence_id([r['patch'],suites])
            self.assertTrue(drain.meets_landing_bar(self.card,r,True,suites)[0])
            self.assertFalse(drain.meets_landing_bar(self.card,r,True,{'unit':{'ok':True}})[0])
            Path(self.tmp.name,'sample.txt').write_text('changed')
            self.assertFalse(drain.meets_landing_bar(self.card,r,True,suites)[0])
            Path(self.tmp.name,'sample.txt').write_text('tested')
            with patch.object(drain,'land',return_value=('', 'commit failed')):
                got=drain.write_back(self.card,r,True,'',suites,ORG)
            self.assertNotIn('completion',got)
            self.assertEqual(got['diff']['why_not_landed'],'commit failed')
            r['attempt_id'] = 'new-attempt'
            def commit(current, attempt, **_kwargs):
                self.assertEqual(current['result'],'The requested reading is finished.')
                self.assertEqual(current['follow_ups'],[])
                self.assertEqual(current['check']['attempt_id'],'new-attempt')
                return 'fixture-commit', ''
            with patch.object(drain,'land',side_effect=commit):
                got=drain.write_back(got,r,True,'',suites,ORG)
            self.assertEqual(got['state'],'landed')
            self.assertEqual(got['completion']['sha'],'fixture-commit')
            self.assertEqual(got['completion']['kind'],'change')

    def test_frozen_legacy_set_is_not_ready_and_reconciliation_is_idempotent(self):
        records=json.loads((Path(__file__).parent/'fixtures'/'reconciliation_records.json').read_text())
        self.assertEqual({c['id'] for c in records},set(work.LEGACY_COMPLETION_IDS))
        for card in records:
            self.assertNotEqual(work.completion_assessment(card)[0],'ready_to_apply')
            work._write_json(work._item_path(card["id"]),card)
        before={p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')}
        report = work.reconcile_legacy_completion()
        self.assertTrue(report['applicable'])
        self.assertEqual(report['totals'], {'safe_to_close':8,'return_to_owner':9,
                         'superseded/duplicate':1,'needs_operator_judgment':1})
        self.assertEqual(before,{p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')})
        self.assertTrue(work.reconcile_legacy_completion(apply=True)['applied'])
        first={p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')}
        self.assertEqual(sum(i['state']=='landed' for i in work.items() if i['id'] in work.LEGACY_COMPLETION_IDS),8)
        self.assertEqual(sum(i['state']=='waiting_session' for i in work.items() if i['id'] in work.LEGACY_COMPLETION_IDS),9)
        work.reconcile_legacy_completion(apply=True)
        self.assertEqual(first,{p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')})

    def test_reconciliation_resumes_after_closure_record_before_landed_state(self):
        records=json.loads((Path(__file__).parent/'fixtures'/'reconciliation_records.json').read_text())
        for card in records: work._write_json(work._item_path(card["id"]),card)
        with patch.object(work,'land_item',side_effect=RuntimeError('interrupted')):
            with self.assertRaises(RuntimeError):work.reconcile_legacy_completion(apply=True)
        self.assertTrue(work.reconcile_legacy_completion(apply=True)['applied'])
        self.assertEqual(sum(i['state']=='landed' for i in work.items() if i['id'] in work.LEGACY_COMPLETION_IDS),8)
        self.assertFalse(any(i.get('pending_followups') for i in work.items()))

    def test_scope_and_pending_reply_changes_block_reconciliation(self):
        records=json.loads((Path(__file__).parent/'fixtures'/'reconciliation_records.json').read_text())
        for card in records: work._write_json(work._item_path(card["id"]),card)
        for field,value in [('ask','new instruction'),('first_action','new step'),('tier',2),
                            ('conversation',[{'role':'daniel','text':'Wait'}]),('awaiting_reply',True),
                            ('new_reply_instruction','different scope')]:
            changed=copy.deepcopy(records[0]);changed[field]=value;work.save_item(changed)
            before={p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')}
            self.assertFalse(work.reconcile_legacy_completion(apply=True)['applied'],field)
            self.assertEqual(before,{p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')})
            work._write_json(work._item_path(records[0]["id"]),records[0])
        changed=copy.deepcopy(records[0]);changed['awaiting_reply']=True;work.save_item(changed)
        manifest=json.loads((Path(work.__file__).parent/'data/completion_reconciliation.json').read_text())
        manifest['cards'][0]['expected_fingerprint']=work.reconciliation_fingerprint(changed)
        self.assertFalse(work.reconcile_legacy_completion(manifest,apply=True)['applied'])

    def test_second_preflight_catches_change_before_any_write(self):
        records=json.loads((Path(__file__).parent/'fixtures'/'reconciliation_records.json').read_text())
        for card in records: work._write_json(work._item_path(card["id"]),card)
        before={p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')}
        read=work.HOST.load_json;counts={}
        def changed_during_read(path):
            counts[path]=counts.get(path,0)+1
            if path.endswith(records[0]['id']+'.json') and counts[path]==2:
                changed=copy.deepcopy(records[-1]);changed['ask']='Changed outside the writer protocol'
                Path(work._item_path(changed['id'])).write_text(json.dumps(changed))
            return read(path)
        with patch.object(work.HOST,'load_json',side_effect=changed_during_read):
            self.assertFalse(work.reconcile_legacy_completion(apply=True)['applied'])
        for name,data in before.items():
            if name!=records[-1]['id']+'.json':self.assertEqual(Path(work.WORK,name).read_bytes(),data)

    def test_shared_lock_blocks_another_process_saving_a_scope_change(self):
        import multiprocessing
        ctx=multiprocessing.get_context('fork');attempted=ctx.Event();finished=ctx.Event()
        work.save_item(self.card)
        def write_scope():
            attempted.set()
            changed=dict(self.card,ask='A new instruction')
            work.save_item(changed)
            finished.set()
        with work.mutation_lock():
            child=ctx.Process(target=write_scope);child.start()
            self.assertTrue(attempted.wait(2))
            self.assertFalse(finished.wait(0.1))
            self.assertEqual(work.HOST.load_json(work._item_path(self.card['id']))['ask'],'Read')
        child.join(3)
        self.assertEqual(child.exitcode,0)
        self.assertTrue(finished.is_set())
        self.assertEqual(work.HOST.load_json(work._item_path(self.card['id']))['ask'],'A new instruction')

    def test_two_processes_apply_reconciliation_only_once(self):
        import multiprocessing
        records=json.loads((Path(__file__).parent/'fixtures'/'reconciliation_records.json').read_text())
        for card in records:work._write_json(work._item_path(card["id"]),card)
        ctx=multiprocessing.get_context('fork');start=ctx.Event();results=ctx.Queue()
        def apply_once():
            start.wait(5)
            try:results.put(work.reconcile_legacy_completion(apply=True)['applied'])
            except BaseException as error:results.put(str(error))
        children=[ctx.Process(target=apply_once) for _ in range(2)]
        for child in children:child.start()
        start.set()
        for child in children:
            child.join(5)
            self.assertFalse(child.is_alive())
            self.assertEqual(child.exitcode,0)
        self.assertEqual([results.get(timeout=1) for _ in children],[True,True])
        returned=[i for i in work.items() if i['id'] in work.LEGACY_COMPLETION_IDS and i['state']=='waiting_session']
        original={i['id']:i for i in records}
        self.assertEqual(len(returned),9)
        for item in returned:
            self.assertEqual(len(item['prior_results']),len(original[item['id']].get('prior_results',[]))+1)

    def test_changed_reconciliation_target_blocks_entire_apply(self):
        records=json.loads((Path(__file__).parent/'fixtures'/'reconciliation_records.json').read_text())
        for card in records: work._write_json(work._item_path(card["id"]),card)
        records[-1]['state']='accepted';work.save_item(records[-1])
        before={p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')}
        report=work.reconcile_legacy_completion(apply=True)
        self.assertFalse(report['applied'])
        self.assertTrue(report['errors'])
        self.assertEqual(before,{p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')})

if __name__ == '__main__':
    unittest.main()
