#!/usr/bin/env python3
"""Record revisions reject stale requests without discarding newer lifecycle state."""
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import work, server
from test_drain import fake_host

class Revisions(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        host=fake_host(self.tmp.name)
        host.load_json=lambda path:json.loads(Path(path).read_text())
        work.bind(host)
    def tearDown(self):self.tmp.cleanup()
    def test_legacy_migration_and_repeated_saves_update_the_caller(self):
        legacy={'id':'wtest','state':'for_review','owner':'sam'}
        work._write_json(work._item_path('wtest'),legacy)
        self.assertEqual(work.items()[0]['_revision'],0)
        item=work.load_item('wtest')
        work.save_item(item);self.assertEqual(item['_revision'],1)
        item['ask']='New request';work.save_item(item)
        self.assertEqual(item['_revision'],2)
        self.assertEqual(work.load_item('wtest'),item)
    def test_new_record_cannot_overwrite_an_existing_legacy_record(self):
        work._write_json(work._item_path('wtest'),{'id':'wtest','state':'for_review'})
        with self.assertRaises(work.RecordConflict):work.save_item({'id':'wtest','state':'doing'})
        self.assertEqual(work.load_item('wtest')['state'],'for_review')
    def test_stale_request_cannot_erase_reconciliation(self):
        records=json.loads((Path(__file__).parent/'fixtures/reconciliation_records.json').read_text())
        for item in records:work._write_json(work._item_path(item['id']),item)
        stale=[work.load_item(ident) for ident in ('w59c6ab05678','w2d226ab695b')]
        self.assertTrue(work.reconcile_legacy_completion(apply=True)['applied'])
        before={p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')}
        for item in stale:
            item['ask']='A request that read the old record'
            with self.assertRaises(work.RecordConflict):work.save_item(item)
        self.assertIn('completion',work.load_item(stale[0]['id']))
        repaired=work.load_item(stale[1]['id'])
        self.assertEqual(repaired['automatic_repairs'],1)
        self.assertIn('completion_reconciliation',repaired)
        self.assertTrue(work.reconcile_legacy_completion(apply=True)['applied'])
        self.assertEqual(before,{p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')})
    def test_stale_acceptance_has_no_child_or_parent_side_effects(self):
        records=json.loads((Path(__file__).parent/'fixtures/reconciliation_records.json').read_text())
        for item in records:work._write_json(work._item_path(item['id']),item)
        ident='w59c6ab05678'
        stale=work.load_item(ident)
        self.assertTrue(work.reconcile_legacy_completion(apply=True)['applied'])
        before={p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')}
        # A delayed request resumes with the snapshot it loaded before reconciliation.
        with patch.object(work,'load_item',return_value=copy.deepcopy(stale)), \
                patch.object(work,'_file_follow_ups',side_effect=AssertionError('stale child filing')):
            with self.assertRaises(work.RecordConflict):
                work.api_post('/api/work/accept',{'id':ident,'comment':'Accepted'})
        # A stale browser revision is also refused even when the server loads fresh data.
        with self.assertRaises(work.RecordConflict):
            work.api_post('/api/work/accept',{'id':ident,'_revision':stale['_revision']})
        self.assertEqual(before,{p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')})
        self.assertTrue(work.reconcile_legacy_completion(apply=True)['applied'])
        self.assertEqual(before,{p.name:p.read_bytes() for p in Path(work.WORK).glob('*.json')})

    def test_http_conflict_returns_409(self):
        request=object.__new__(server.Handler)
        body=b'{"id":"wtest"}'
        request.path='/api/work/drop';request.headers={'Content-Length':str(len(body))}
        request.rfile=io.BytesIO(body)
        sent=[];request._send=lambda status,data:sent.append((status,data))
        with patch.object(work,'api_post',side_effect=work.RecordConflict('wtest',1,2)):
            request.do_POST()
        self.assertEqual(sent[0][0],409)
        self.assertEqual(sent[0][1]['revision'],2)

if __name__=='__main__':unittest.main()
