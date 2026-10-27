#!/usr/bin/env python3
"""Linked social preview stays private while ordinary HQ routes keep their roots."""
import http.client
import json
import os
from pathlib import Path
import selectors
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from http.server import ThreadingHTTPServer

HQ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HQ))
import preview_store
import server
import social_proxy


class PreviewStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix="social-preview-store-test-")
        self.root=Path(self.tmp.name)
        self.live=self.root/"live"
        self.repo=self.root/"repository"
        self.live.mkdir();self.repo.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def prepare(self,path,**args):
        return preview_store.prepare_data(path,protected=[self.live,self.repo],temporary_root=self.root/"temporary",**args)

    def test_persistent_requires_opt_in_and_preserves_marked_private_records(self):
        data=self.root/"private"
        with self.assertRaises(ValueError):self.prepare(data)
        self.assertFalse(data.exists())
        self.prepare(data,persistent=True)
        (data/"kept.json").write_text('{"note":"Keep my review"}')
        self.prepare(data,persistent=True)
        self.assertEqual((data/"kept.json").read_text(),'{"note":"Keep my review"}')
        self.assertEqual(data.stat().st_mode & 0o777,0o700)

    def test_live_roots_ancestors_and_descendants_are_rejected_even_with_preview_marker(self):
        (self.live/preview_store.MARKER).write_text(preview_store.PURPOSE)
        (self.live/".hq-store").write_text(preview_store.STORE_MARKER)
        for path in (self.live,self.live/"social-preview",self.repo,self.repo/"preview",self.root,Path("/"),Path.home()):
            with self.assertRaises(ValueError,msg=str(path)):self.prepare(path,persistent=True)

    def test_unmarked_nonempty_store_and_symlink_are_rejected(self):
        data=self.root/"other"
        data.mkdir();(data/".hq-store").write_text("A live HQ store")
        with self.assertRaises(ValueError):self.prepare(data,persistent=True)
        linked=self.root/"linked";linked.symlink_to(self.live,target_is_directory=True)
        with self.assertRaises(ValueError):self.prepare(linked,persistent=True)

    def test_marked_preview_rejects_symlinked_writable_folders_and_record_files(self):
        data=self.root/"private"
        self.prepare(data,persistent=True)
        target=self.live/"records";target.mkdir()
        (target/"record.json").write_text('{"keep":"live"}')
        for name in ("social","work","captures"):
            link=data/name;link.symlink_to(target,target_is_directory=True)
            with self.assertRaises(ValueError,msg=name):self.prepare(data,persistent=True)
            link.unlink()
        nested=data/"social"/"backups";nested.mkdir(parents=True)
        record=nested/"old.json";record.symlink_to(target/"record.json")
        with self.assertRaises(ValueError):self.prepare(data,persistent=True)
        self.assertEqual((target/"record.json").read_text(),'{"keep":"live"}')

    def test_temporary_directory_uses_the_same_preview_marker_guard(self):
        data=self.root/"temporary"/"preview"
        self.prepare(data)
        self.assertEqual((data/preview_store.MARKER).read_text(),preview_store.PURPOSE)
        (data/".hq-store").write_text("Wrong store")
        with self.assertRaises(ValueError):self.prepare(data)


class LinkedPreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory(prefix="social-preview-proxy-test-")
        cls.base=Path(cls.tmp.name)
        cls.live=cls.base/"live";cls.live.mkdir()
        (cls.live/"work").mkdir();(cls.live/"work"/"sentinel.json").write_text('{"keep":"live work"}')
        cls.data=cls.base/"preview"
        media=cls.base/"media"
        folder="2026-10-14_tiktok_sheep"
        movie=media/folder/"renders"/(folder+"_v5.mp4")
        movie.parent.mkdir(parents=True);movie.write_bytes(b"0123456789")
        env={k:v for k,v in os.environ.items() if k not in ("HQ_DATA_ROOT","HQ_MAIN_ROOT","HQ_USER_WORKSPACE_ROOT","HQ_REQUIRE_EXPLICIT_ROOTS",social_proxy.ENV)}
        cls.sidecar=subprocess.Popen([sys.executable,str(HQ/"tests/social_preview.py"),"--data",str(cls.data),"--media",str(media),"--port","0"],cwd=HQ.parent,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        sel=selectors.DefaultSelector();sel.register(cls.sidecar.stdout,selectors.EVENT_READ)
        if not sel.select(15):raise RuntimeError("Preview did not start")
        line=cls.sidecar.stdout.readline();sel.close()
        try:info=json.loads(line)
        except ValueError:raise RuntimeError("Preview startup failed: "+line)
        cls.upstream=info["url"].split("/#")[0]
        cls.patch=patch.object(server,"DATA",str(cls.live));cls.patch.start()
        cls.httpd=ThreadingHTTPServer(("127.0.0.1",0),server.Handler)
        cls.thread=threading.Thread(target=cls.httpd.serve_forever,daemon=True);cls.thread.start()
        cls.port=cls.httpd.server_port
        cls.env=patch.dict(os.environ,{social_proxy.ENV:cls.upstream});cls.env.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown();cls.httpd.server_close();cls.thread.join()
        cls.sidecar.terminate();cls.sidecar.wait(timeout=5);cls.sidecar.stdout.close()
        cls.env.stop();cls.patch.stop();cls.tmp.cleanup()

    def request(self,method,path,payload=None,headers=None):
        connection=http.client.HTTPConnection("127.0.0.1",self.port,timeout=10)
        body=json.dumps(payload).encode() if payload is not None else None
        request_headers={"Content-Type":"application/json","Origin":f"http://127.0.0.1:{self.port}"} if method=="POST" else {}
        request_headers.update(headers or {})
        connection.request(method,path,body=body,headers=request_headers)
        response=connection.getresponse();raw=response.read();status=response.status;sent=dict(response.getheaders());connection.close()
        return status,sent,json.loads(raw) if sent.get("Content-Type","").startswith("application/json") else raw

    def test_only_social_routes_are_proxied_and_normal_health_keeps_live_root(self):
        self.assertFalse(social_proxy.forward(object(),"/api/work/request"))
        self.assertFalse(social_proxy.forward(object(),"/api/social-unrelated"))
        status,headers,health=self.request("GET","/api/health")
        self.assertEqual(status,200);self.assertEqual(health["roots"]["data"],str(self.live))
        self.assertNotIn("X-HQ-Social-Preview",headers)
        status,headers,listing=self.request("GET","/api/social")
        self.assertEqual(status,200);self.assertTrue(listing["preview"])
        self.assertEqual(headers["X-HQ-Social-Preview"],"isolated")

    def test_sidecar_health_does_not_read_execution_or_account_policy(self):
        from urllib.parse import urlsplit
        connection=http.client.HTTPConnection("127.0.0.1",urlsplit(self.upstream).port,timeout=5)
        connection.request("GET","/api/health")
        response=connection.getresponse();body=json.loads(response.read());connection.close()
        self.assertEqual(response.status,200)
        self.assertTrue(body["preview"])
        self.assertEqual(body["roots"]["data"],str(self.data))
        self.assertFalse((self.data/"execution_policy.json").exists())

    def test_same_origin_note_and_request_write_only_the_private_store(self):
        before=(self.live/"work/sentinel.json").read_bytes()
        status,_,idea=self.request("POST","/api/social/idea",{"brief":{"title":"A private preview idea"}})
        self.assertEqual(status,200)
        status,_,noted=self.request("POST","/api/social/note",{"id":idea["id"],"revision":idea["revision"],"text":"Keep this private note.","seconds":None,"version":None,"sha256":None})
        self.assertEqual(status,200)
        status,_,requested=self.request("POST","/api/social/request",{"id":idea["id"],"revision":noted["revision"],"submission_id":"private-linked-preview","version":None,"sha256":None})
        self.assertEqual(status,200)
        request=requested["requests"][0]
        self.assertTrue((self.data/"work"/(request["work_id"]+".json")).is_file())
        self.assertEqual((self.live/"work/sentinel.json").read_bytes(),before)
        self.assertEqual([p.name for p in (self.live/"work").iterdir()],["sentinel.json"])
        self.assertFalse((self.live/"social").exists())

    def test_range_and_private_headers_survive_proxy(self):
        status,_,detail=self.request("GET","/api/social/sheep")
        self.assertEqual(status,200)
        status,headers,body=self.request("GET",detail["current_cut"]["url"],headers={"Range":"bytes=2-5"})
        self.assertEqual((status,body),(206,b"2345"))
        self.assertEqual(headers["Content-Range"],"bytes 2-5/10")
        self.assertEqual(headers["Cache-Control"],"private, no-store")
        status,headers,_=self.request("GET",detail["current_cut"]["url"],headers={"Range":"bytes=200-"})
        self.assertEqual(status,416);self.assertEqual(headers["Content-Range"],"bytes */10")

    def test_foreign_origin_and_oversized_body_are_rejected_before_proxying(self):
        before=set((self.data/"social").glob("*.json")) if (self.data/"social").exists() else set()
        status,_,_=self.request("POST","/api/social/idea",{"brief":{"title":"Reject"}},headers={"Origin":"https://elsewhere.example"})
        self.assertEqual(status,403)
        status,_,_=self.request("POST","/api/social/idea",headers={"Content-Length":"100001"})
        self.assertEqual(status,413)
        after=set((self.data/"social").glob("*.json")) if (self.data/"social").exists() else set()
        self.assertEqual(before,after)

    def test_documented_tailnet_origin_is_preserved_without_arbitrary_forwarded_hosts(self):
        authority="daniel-maco.tail445099.ts.net"
        status,_,_=self.request("POST","/api/social/idea",{"brief":{"title":"Tailnet preview"}},headers={"Host":authority,"Origin":"https://"+authority,"X-Forwarded-Proto":"https"})
        self.assertEqual(status,200)
        status,_,_=self.request("POST","/api/social/idea",{"brief":{"title":"Reject host spoof"}},headers={"Host":"localhost","Origin":"https://elsewhere.example","X-Forwarded-Host":"elsewhere.example","X-Forwarded-Proto":"https"})
        self.assertEqual(status,403)

    def test_unavailable_or_invalid_upstream_fails_closed_without_live_fallback(self):
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1",0))
            closed_port=reservation.getsockname()[1]
        for url in ("", "http://127.0.0.1:1",f"http://127.0.0.1:{closed_port}","http://elsewhere.example:8644",f"http://127.0.0.1:{self.port}"):
            with patch.dict(os.environ,{social_proxy.ENV:url}):
                status,_,body=self.request("POST","/api/social/idea",{"brief":{"title":"Do not fall back"}})
                self.assertEqual(status,503)
                self.assertEqual(body["code"],"preview_unavailable")
        self.assertFalse((self.live/"social").exists())


if __name__=="__main__":unittest.main()
