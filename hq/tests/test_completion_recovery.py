#!/usr/bin/env python3
"""Real temporary Git repos exercise commit interruptions and automatic recovery."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import work, drain, integration, server
from test_completion import record, result
from test_drain import fake_host, ORG

class Crash(BaseException):
    pass

class Recovery(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.repo=Path(self.tmp.name)/'repo';self.repo.mkdir()
        self.git('init','-q','-b','main')
        self.git('config','user.email','fixture@example.invalid')
        self.git('config','user.name','Fixture')
        self.git('config','core.hooksPath',str(self.repo/'.git/hooks'))
        (self.repo/'sample.txt').write_text('before\n')
        self.git('add','sample.txt');self.git('commit','-qm','Initial')
        base=self.git('rev-parse','HEAD')
        (self.repo/'sample.txt').write_text('checked\n')
        self.git('add','sample.txt')
        host=fake_host(str(Path(self.tmp.name)/'data'))
        host.REPO=str(self.repo)
        host.load_json=lambda path:json.loads(Path(path).read_text())
        work.bind(host)
        self.repo_patch=patch.object(server,'REPO',str(self.repo));self.repo_patch.start()
        self.worktrees_patch=patch.object(drain,'WORKTREES',str(Path(self.tmp.name)/'worktrees'));self.worktrees_patch.start()
        self.card={'id':'wtest','title':'Finish the file','owner':'sam','tier':1,'state':'waiting_session',
                   'ask':'Finish','first_action':'Edit','attempts':0}
        self.suites={'unit':{'ok':True},'integration':{'ok':True}}
        self.r=record(files=['sample.txt'],patch=self.git('diff','--cached')+'\n')
        self.r['candidate']={'tree':self.git('write-tree'),'base':base,
                             'files':drain.git_blobs(str(self.repo),'',['sample.txt']),
                             'base_files':drain.git_blobs(str(self.repo),base,['sample.txt'])}
        self.r['candidate_test_evidence']=work.evidence_id([self.r['candidate'],self.r['candidate_suites']])
        self.r['check_evidence']=work.evidence_id([self.r['result'],self.r['patch'],self.r['candidate']])
        self.r['test_evidence']=work.evidence_id([self.r['patch'],self.suites])
        self.assertEqual(integration.handoff_main(str(self.repo), 'codex/fixture-user',
                                                  confirmed_idle=True), (True, ''))
        checkout, kind, reason = drain.prepare_integration(self.r)
        self.assertEqual((kind, reason), ('', ''))
        self.r['integration_checkout'] = checkout
        self.r['tree_evidence']=drain.tree_evidence(['sample.txt'], repo=checkout)
    def tearDown(self):
        self.repo_patch.stop();self.worktrees_patch.stop();self.tmp.cleanup()
    def git(self,*args):
        return subprocess.run(['git',*args],cwd=self.repo,capture_output=True,text=True,check=True).stdout.strip()
    def saved(self):
        return json.loads(Path(work._item_path('wtest')).read_text())
    def write(self):
        return drain.write_back(self.card,self.r,True,'',self.suites,ORG)

    def test_crash_before_commit_is_held_without_relaunch(self):
        original=drain.sh
        def interrupted(args,**kwargs):
            if args[:2]==['git','commit']: raise Crash()
            return original(args,**kwargs)
        with patch.object(drain,'sh',side_effect=interrupted):
            with self.assertRaises(Crash):self.write()
        self.assertIn('pending_landing',self.saved())
        lock=drain.take_lock()
        try:
            self.assertEqual(work.recover_completion_work(),[])
            self.assertIn('pending_landing',self.saved())
        finally:
            lock.close()
        with patch.object(drain,'do_item',side_effect=AssertionError('No model')):
            self.assertEqual(work.recover_completion_work(),['wtest'])
        got=self.saved()
        self.assertNotIn('completion',got)
        self.assertIn('did not happen',got['repair_hold'])
        self.assertEqual(got['workflow']['actions'][-1]['type'],'reconcile')
        self.assertEqual(drain.queued(),[])

    def test_crash_after_commit_finalizes_from_selector_without_relaunch(self):
        original=drain.sh
        def interrupted(args,**kwargs):
            got=original(args,**kwargs)
            if args[:2]==['git','commit']: raise Crash()
            return got
        with patch.object(drain,'sh',side_effect=interrupted):
            with self.assertRaises(Crash):self.write()
        sha=subprocess.run(['git','rev-parse','HEAD'],cwd=self.r['integration_checkout'],
                           capture_output=True,text=True,check=True).stdout.strip()
        with patch.object(drain,'do_item',side_effect=AssertionError('No model')):
            self.assertEqual(work.recover_completion_work(),['wtest'])
            self.assertEqual(work.recover_completion_work(),[])
        got=self.saved()
        self.assertEqual(got['completion']['sha'],sha)
        self.assertEqual(got['state'],'landed')
        self.assertEqual(self.git('rev-list','--count','main'),'2')

    def test_hook_changes_committed_blob_so_completion_is_refused(self):
        hook=self.repo/'.git/hooks/pre-commit'
        hook.write_text('#!/bin/sh\nprintf "hook changed it\\n" > sample.txt\ngit add sample.txt\n')
        hook.chmod(0o755)
        got=self.write()
        self.assertNotIn('completion',got)
        self.assertIn('differ',got['diff']['why_not_landed'])
        work.recover_completion_work()
        self.assertNotIn('completion',self.saved())
        self.assertIn('differs',self.saved()['repair_hold'])

    def test_user_checkout_edit_does_not_change_clean_candidate_or_get_overwritten(self):
        (self.repo/'sample.txt').write_text('another edit\n')
        self.assertTrue(drain.meets_landing_bar(self.card,self.r,True,self.suites,
                                               repo=self.r['integration_checkout'])[0])
        got=self.write()
        self.assertEqual(got['state'],'landed')
        self.assertEqual(self.git('rev-list','--count','main'),'2')
        self.assertEqual((self.repo/'sample.txt').read_text(),'another edit\n')

    def test_base_commit_movement_refuses_landing_before_commit(self):
        other=Path(self.tmp.name)/'other'
        self.git('worktree','add','--detach',str(other),'main')
        (other/'other.txt').write_text('intervening change\n')
        subprocess.run(['git','add','other.txt'],cwd=other,check=True)
        subprocess.run(['git','commit','-qm','Another change'],cwd=other,check=True)
        new=subprocess.run(['git','rev-parse','HEAD'],cwd=other,capture_output=True,text=True,check=True).stdout.strip()
        self.assertTrue(integration.advance_main(str(self.repo),new,self.r['candidate']['base']))
        got=self.write()
        self.assertNotIn('completion',got)
        self.assertIn('repository changed',got['diff']['why_not_landed'])
        self.assertEqual(self.git('rev-list','--count','main'),'2')

    def test_two_disjoint_cards_land_against_successive_parents(self):
        cards=[dict(self.card,id='wfirst'),dict(self.card,id='wsecond')]
        for card in cards:work.save_item(card)
        bases=[]
        def candidate(item,*args):
            base=self.git('rev-parse','main');bases.append(base)
            name='sample.txt' if item['id']=='wfirst' else 'another.txt'
            worker=Path(self.tmp.name)/('worker-'+item['id'])
            self.git('worktree','add','--detach',str(worker),base)
            (worker/name).write_text(item['id']+'\n')
            subprocess.run(['git','add',name],cwd=worker,check=True)
            def from_worker(*args):
                return subprocess.run(['git',*args],cwd=worker,capture_output=True,
                                      text=True,check=True).stdout
            r=record(id=item['id'],attempt_id=item['id'],files=[name],
                     patch=from_worker('diff','--cached','--binary'))
            r['candidate']={'base':base,'tree':from_worker('write-tree').strip(),
                            'files':drain.git_blobs(str(worker),'',[name]),
                            'base_files':drain.git_blobs(str(worker),base,[name])}
            r['candidate_test_evidence']=work.evidence_id([r['candidate'],r['candidate_suites']])
            r['check_evidence']=work.evidence_id([r['result'],r['patch'],r['candidate']])
            self.git('worktree','remove','--force',str(worker))
            return r
        with patch.object(drain,'do_item',side_effect=candidate), \
             patch.object(drain,'run_suites',return_value=self.suites):
            _,done=drain.run_verified_batch(cards,ORG,'fixture',lambda message:None)
        self.assertEqual([i['state'] for i in done],['landed','landed'])
        self.assertNotEqual(bases[0],bases[1])
        self.assertEqual(self.git('rev-list','--count','main'),'3')

    def test_batch_reassesses_if_instructions_change_during_execution(self):
        work.save_item(self.card)
        def changed(item,*args):
            latest=work.load_item(item['id']);latest['ask']='Changed while the worker ran'
            work.save_item(latest)
            return self.r
        with patch.object(drain,'do_item',side_effect=changed), \
             patch.object(drain,'apply_patch',side_effect=AssertionError('No stale result application')):
            records,done=drain.run_verified_batch([self.card],ORG,'fixture',lambda message:None)
        self.assertEqual(done,[])
        self.assertTrue(records['wtest']['held'])
        self.assertEqual(work.load_item('wtest')['ask'],'Changed while the worker ran')

    def test_unowned_main_stops_before_any_owner_model_call(self):
        work.save_item(self.card)
        with patch.object(integration,'handoff_status',return_value=(False,'Handoff required')), \
             patch.object(drain,'do_item',side_effect=AssertionError('No worker before handoff')):
            for _ in range(2):
                records,done=drain.run_verified_batch([self.card],ORG,'fixture',lambda message:None)
                self.assertEqual(done,[])
                self.assertTrue(records['wtest']['held'])
        saved=work.load_item('wtest')
        self.assertEqual([a['type'] for a in saved['workflow']['actions']],['handoff'])
        self.assertEqual(len(saved['workflow']['blockers']),1)

    def test_failed_prospective_suite_keeps_main_and_creates_one_recovery_action(self):
        integration.remove_candidate(str(self.repo),self.r['integration_checkout'],drain.WORKTREES)
        work.save_item(self.card)
        red={'unit':{'ok':True},'integration':{'ok':False}}
        with patch.object(drain,'do_item',return_value=self.r), \
             patch.object(drain,'run_suites',return_value=red):
            records,done=drain.run_verified_batch([self.card],ORG,'fixture',lambda message:None)
        self.assertEqual(records['wtest']['suites'],red)
        self.assertEqual(done[0]['state'],'for_review')
        self.assertEqual(self.git('rev-parse','main'),self.r['candidate']['base'])
        self.assertEqual(work.load_item('wtest')['workflow']['actions'][-1]['type'],'reconcile')

    def test_untracked_test_output_invalidates_prospective_tree(self):
        integration.remove_candidate(str(self.repo),self.r['integration_checkout'],drain.WORKTREES)
        work.save_item(self.card)
        def polluted(cwd=None):
            (Path(cwd)/'surprise.txt').write_text('not in candidate\n')
            return self.suites
        with patch.object(drain,'do_item',return_value=self.r), \
             patch.object(drain,'run_suites',side_effect=polluted):
            records,done=drain.run_verified_batch([self.card],ORG,'fixture',lambda message:None)
        self.assertFalse(records['wtest']['applied'])
        self.assertIn('changed while its tests ran',records['wtest']['why_not'])
        self.assertEqual(self.git('rev-parse','main'),self.r['candidate']['base'])

    def test_batch_rejects_stale_overlapping_candidate_without_applying(self):
        work.save_item(self.card)
        other=Path(self.tmp.name)/'overlap'
        self.git('worktree','add','--detach',str(other),'main')
        (other/'sample.txt').write_text('intervening overlap\n')
        subprocess.run(['git','add','sample.txt'],cwd=other,check=True)
        subprocess.run(['git','commit','-qm','Overlap'],cwd=other,check=True)
        new=subprocess.run(['git','rev-parse','HEAD'],cwd=other,capture_output=True,text=True,check=True).stdout.strip()
        self.assertTrue(integration.advance_main(str(self.repo),new,self.r['candidate']['base']))
        with patch.object(drain,'do_item',return_value=self.r), \
             patch.object(drain,'apply_patch',side_effect=AssertionError('Must not apply a stale patch')):
            records,done=drain.run_verified_batch([self.card],ORG,'fixture',lambda message:None)
        self.assertFalse(records['wtest']['applied'])
        self.assertNotIn('completion',done[0])
        self.assertIn('stale',records['wtest']['why_not'])
        self.assertEqual(self.git('show','main:sample.txt'),'intervening overlap')
        self.assertEqual((self.repo/'sample.txt').read_text(),'checked\n')
        self.assertEqual(len(work.load_item('wtest')['workflow']['actions']),1)

    def test_selector_resumes_followups_on_a_landed_card(self):
        fu={'title':'Finish another file','owner':'sam','tier':1,'level':'task','first_action':'Edit','why':'Next'}
        self.r['result']=result(items=[fu])
        self.r['check_evidence']=work.evidence_id([self.r['result'],self.r['patch'],self.r['candidate']])
        original=work._file_follow_ups
        # Seed a real pending obligation by interrupting between child and parent saves.
        def interrupted(item,items,*args,**kwargs):
            original(item,items,*args,**kwargs)
            raise Crash()
        with patch.object(work,'_file_follow_ups',side_effect=interrupted):
            with self.assertRaises(Crash):self.write()
        got=self.saved()
        self.assertEqual(got['state'],'landed')
        with patch.object(drain,'do_item',side_effect=AssertionError('No model')):
            work.recover_completion_work()
            work.recover_completion_work()
        self.assertEqual(len(work.items()),2)
        self.assertNotIn('pending_followups',self.saved())

if __name__=='__main__':unittest.main()
