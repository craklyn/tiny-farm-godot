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
import work, drain, server
from test_completion import record, result
from test_drain import fake_host, ORG

class Crash(BaseException):
    pass

class Recovery(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.repo=Path(self.tmp.name)/'repo';self.repo.mkdir()
        self.git('init','-q')
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
        self.r=record(files=['sample.txt'],patch=self.git('diff','--cached'))
        self.r['candidate']={'tree':self.git('write-tree'),'base':base,
                             'files':drain.git_blobs(str(self.repo),'',['sample.txt']),
                             'base_files':drain.git_blobs(str(self.repo),base,['sample.txt'])}
        self.r['candidate_test_evidence']=work.evidence_id([self.r['candidate'],self.r['candidate_suites']])
        self.r['check_evidence']=work.evidence_id([self.r['result'],self.r['patch'],self.r['candidate']])
        self.r['test_evidence']=work.evidence_id([self.r['patch'],self.suites])
        self.r['tree_evidence']=drain.tree_evidence(['sample.txt'])
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
        self.assertEqual(drain.queued(),[])

    def test_crash_after_commit_finalizes_from_selector_without_relaunch(self):
        original=drain.sh
        def interrupted(args,**kwargs):
            got=original(args,**kwargs)
            if args[:2]==['git','commit']: raise Crash()
            return got
        with patch.object(drain,'sh',side_effect=interrupted):
            with self.assertRaises(Crash):self.write()
        sha=self.git('rev-parse','HEAD')
        with patch.object(drain,'do_item',side_effect=AssertionError('No model')):
            self.assertEqual(work.recover_completion_work(),['wtest'])
            self.assertEqual(work.recover_completion_work(),[])
        got=self.saved()
        self.assertEqual(got['completion']['sha'],sha)
        self.assertEqual(got['state'],'landed')
        self.assertEqual(self.git('rev-list','--count','HEAD'),'2')

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

    def test_intervening_edit_invalidates_candidate(self):
        (self.repo/'sample.txt').write_text('another edit\n')
        self.assertFalse(drain.meets_landing_bar(self.card,self.r,True,self.suites)[0])
        got=self.write()
        self.assertNotIn('completion',got)
        self.assertEqual(self.git('rev-list','--count','HEAD'),'1')

    def test_base_commit_movement_refuses_landing_before_commit(self):
        self.git('reset','-q','HEAD','--','sample.txt')
        (self.repo/'other.txt').write_text('intervening change\n')
        self.git('add','other.txt');self.git('commit','-qm','Another change')
        got=self.write()
        self.assertNotIn('completion',got)
        self.assertIn('repository changed',got['diff']['why_not_landed'])
        self.assertEqual(self.git('rev-list','--count','HEAD'),'2')

    def test_two_disjoint_cards_land_against_successive_parents(self):
        self.git('reset','--hard','HEAD')
        cards=[dict(self.card,id='wfirst'),dict(self.card,id='wsecond')]
        for card in cards:work.save_item(card)
        bases=[]
        def candidate(item,*args):
            base=self.git('rev-parse','HEAD');bases.append(base)
            name='sample.txt' if item['id']=='wfirst' else 'another.txt'
            (self.repo/name).write_text(item['id']+'\n')
            self.git('add',name)
            r=record(id=item['id'],attempt_id=item['id'],files=[name],patch=self.git('diff','--cached'))
            r['candidate']={'base':base,'tree':self.git('write-tree'),
                            'files':drain.git_blobs(str(self.repo),'',[name]),
                            'base_files':drain.git_blobs(str(self.repo),base,[name])}
            r['candidate_test_evidence']=work.evidence_id([r['candidate'],r['candidate_suites']])
            r['check_evidence']=work.evidence_id([r['result'],r['patch'],r['candidate']])
            self.git('reset','--hard','HEAD')
            return r
        def apply(text,files):
            subprocess.run(['git','apply','-'],input=text+'\n',cwd=self.repo,text=True,check=True)
            return True,''
        with patch.object(drain,'do_item',side_effect=candidate), patch.object(drain,'apply_patch',side_effect=apply), \
             patch.object(drain,'run_suites',return_value=self.suites):
            _,done=drain.run_verified_batch(cards,ORG,'fixture',lambda message:None)
        self.assertEqual([i['state'] for i in done],['landed','landed'])
        self.assertNotEqual(bases[0],bases[1])
        self.assertEqual(self.git('rev-list','--count','HEAD'),'3')

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

    def test_batch_rejects_stale_overlapping_candidate_without_applying(self):
        work.save_item(self.card)
        self.git('reset','--hard','HEAD')
        (self.repo/'sample.txt').write_text('intervening overlap\n')
        self.git('add','sample.txt');self.git('commit','-qm','Overlap')
        with patch.object(drain,'do_item',return_value=self.r), \
             patch.object(drain,'apply_patch',side_effect=AssertionError('Must not apply a stale patch')):
            records,done=drain.run_verified_batch([self.card],ORG,'fixture',lambda message:None)
        self.assertFalse(records['wtest']['applied'])
        self.assertNotIn('completion',done[0])
        self.assertIn('stale',records['wtest']['why_not'])
        self.assertEqual((self.repo/'sample.txt').read_text(),'intervening overlap\n')

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
