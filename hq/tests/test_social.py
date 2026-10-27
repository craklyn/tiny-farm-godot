#!/usr/bin/env python3
"""Social review and publication invariants, using only scratch media and stores."""
import concurrent.futures
import io
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

HQ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HQ))
import social
import server
import work
from test_drain import fake_host


class SocialTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="hq-social-test-")
        self.base = Path(self.tmp.name)
        self.media = self.base / "media"
        self.media.mkdir()
        data = self.base / "data"
        data.mkdir()
        self.host = fake_host(str(data))
        self.host.load_json = lambda p: json.loads(Path(p).read_text())
        self.host.HQ_DIR = str(HQ)
        self.host.REPO = str(self.base)
        self.host.cfg = lambda name: str(HQ / "data" / name)
        self.host.work = work
        work.bind(self.host, sanitize=False)
        social.bind(self.host)
        self.env = patch.dict(os.environ, {"HQ_SOCIAL_MEDIA_ROOT": str(self.media)})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def file(self, ident="sheep", version="v1", content=b"a private movie"):
        record = social._load(ident)
        path = self.media / record["folder"] / "renders" / (record["render_prefix"] + "_" + version + ".mp4")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def detail(self, ident="sheep"):
        return social.content_detail(ident)

    def mutate(self, command, ident="sheep", detail=None, **args):
        d = detail or self.detail(ident)
        cut = d["current_cut"]
        return social.mutate(command, {"id": ident, "revision": d["revision"],
                                      "version": cut["version"] if cut else None,
                                      "sha256": cut["sha256"] if cut else None, **args})

    def assertError(self, status, fn):
        with self.assertRaises(social.SocialError) as e:
            fn()
        self.assertEqual(e.exception.status, status)

    def test_recording_reader_exact_current_source_and_saved_precedence(self):
        rel = "video/2026-10-14_tiktok_sheep/edit/script-v2.md"
        expected = (HQ.parent / rel).read_text().split("\n\n", 1)[1].strip().split("\n\n")
        reader = self.detail()["recording_script"]
        self.assertEqual(reader, {"origin":"source", "paragraphs":expected})
        self.assertEqual(len(expected), 14)
        saved = "<img src=x onerror=alert(1)>\n\nMy own closing line."
        self.mutate("save", brief={"script":saved})
        self.assertEqual(self.detail()["recording_script"],
                         {"origin":"saved", "paragraphs":saved.split("\n\n")})
        self.assertEqual(social._load("sheep")["brief"]["script"], saved)

    def test_recording_reader_missing_and_changed_source_are_honest(self):
        record = social._load("sheep")
        with patch.object(social, "_inside", return_value=self.base / "missing.md"):
            self.assertEqual(social._recording_script(record), {"origin":None,"paragraphs":[]})
        source = self.base / "script.md"
        source.write_text("# Not spoken\n\nFirst exact line.\n\nSecond exact line.")
        with patch.object(social, "_inside", return_value=source):
            self.assertEqual(social._recording_script(record)["paragraphs"], ["First exact line.","Second exact line."])
            source.write_text("# Not spoken\n\nChanged at request time.")
            self.assertEqual(social._recording_script(record)["paragraphs"], ["Changed at request time."])
        self.assertEqual(self.detail("creamery")["recording_script"], {"origin":None,"paragraphs":[]})

    def test_seed_is_two_publications_and_one_draft_with_evidence(self):
        listing = social.list_content()["projects"]
        self.assertEqual(len(listing), 3)
        self.assertEqual([p["published"] for p in listing], [True, True, False])
        self.assertEqual(listing[0]["publication"]["version"], "v4")
        self.assertEqual(listing[1]["publication"]["date"], "2026-10-12")
        self.assertIsNone(listing[0]["published_cut"])
        self.assertFalse(listing[0]["publication"]["sha256"])
        self.assertTrue(all(p["evidence"] for p in listing))

    def test_media_discovery_is_numeric_and_explicit_root(self):
        self.file(version="v2")
        self.file(version="v10")
        self.file(version="v5")
        d = self.detail()
        self.assertEqual([c["version"] for c in d["cuts"]], ["v2", "v5", "v10"])
        self.assertEqual(d["current_cut"]["version"], "v10")

    def test_note_persists_at_exact_cut_and_time(self):
        self.file()
        d = self.mutate("note", text="Let the bird settle.", seconds=12.4)
        self.file(version="v2", content=b"next cut")
        latest = self.detail()
        self.assertEqual(latest["notes"][0]["sha256"], d["cuts"][0]["sha256"])
        self.assertEqual(latest["notes"][0]["seconds"], 12.4)
        self.assertNotEqual(latest["current_cut"]["sha256"], latest["notes"][0]["sha256"])
        social.bind(self.host)
        self.assertEqual(self.detail()["notes"], latest["notes"])

    def test_approval_requires_resolved_notes_and_current_file(self):
        path = self.file()
        d = self.mutate("note", text="Fix timing.", seconds=3)
        self.assertError(409, lambda: self.mutate("approve"))
        d = self.mutate("resolve", note_id=d["notes"][0]["id"])
        approved = self.mutate("approve")
        self.assertTrue(approved["approved"])
        path.write_bytes(b"changed movie same filename")
        self.assertFalse(self.detail()["approved"])
        self.assertError(409, lambda: self.mutate("approve", detail=approved))
        self.assertError(409, lambda: self.mutate("note", detail=approved, text="Stale click", seconds=1))

    def test_new_cut_does_not_inherit_approval(self):
        self.file()
        approved = self.mutate("approve")
        self.file(version="v2", content=b"next version")
        self.assertFalse(self.detail()["approved"])
        self.assertError(409, lambda: self.mutate("publication", detail=approved, url="https://www.tiktok.com/@farm/video/123"))

    def test_general_note_before_cut_blocks_approval(self):
        n = self.mutate("note", text="Check the ending.", seconds=None)
        self.assertIsNone(n["notes"][0]["sha256"])
        self.file()
        self.assertError(409, lambda: self.mutate("approve"))
        self.mutate("resolve", note_id=n["notes"][0]["id"])
        self.assertTrue(self.mutate("approve")["approved"])

    def test_publication_freezes_hash_caption_brief_and_media(self):
        self.file()
        self.mutate("save", brief={"caption":"The sheep have arrived."})
        self.mutate("approve")
        pub = self.mutate("publication", url="https://www.tiktok.com/@farm/video/123", date="2026-10-22")
        self.assertEqual(pub["publication"]["caption"], "The sheep have arrived.")
        self.assertEqual(pub["publication"]["sha256"], pub["current_cut"]["sha256"])
        self.assertError(409, lambda:self.mutate("save", brief={"title":"Rewritten"}))
        self.assertError(409, lambda:self.mutate("request", submission_id="request-fixed"))
        self.file(version="v2", content=b"later cut")
        current = self.detail()
        self.assertEqual(current["published_cut"]["version"], "v1")
        self.assertEqual(current["publication"], pub["publication"])
        self.file(content=b"different bytes")
        self.assertIsNone(self.detail()["published_cut"])
        self.assertError(404, lambda: social.serve_media(self.handler(), "sheep", "v2", "video", current["current_cut"]["sha256"]))

    def test_seed_posting_details_append_without_rewriting_history(self):
        before = self.detail("creamery")
        after = self.mutate("publication", "creamery", url="https://www.tiktok.com/@farm/video/456", date="2026-10-12")
        self.assertEqual(before["publication"], after["publication"])
        self.assertEqual(len(after["posting_details"]), 1)
        self.assertError(409, lambda:self.mutate("save", "creamery", brief={"title":"Replace history"}))

    def test_idea_output_receives_cut_and_followup_context(self):
        d = social.mutate("idea", {"brief":{"title":"A reply", "promise":"Answer a viewer", "source_comment":"Please add shears."}, "source_project":"creamery"})
        self.assertRegex(d["id"], r"^idea-[0-9a-f]{16}$")
        self.assertEqual(d["source_project"], "creamery")
        self.assertEqual(d["output_path"], f'video/drafts/{d["id"]}/renders/{d["id"]}_vN.mp4')
        self.file(d["id"])
        self.assertTrue(self.mutate("approve", d["id"])["approved"])

    def test_revision_conflict_and_concurrent_writes_cannot_overwrite(self):
        d = self.detail()
        self.mutate("save", brief={"title":"Saved first"})
        self.assertError(409, lambda:self.mutate("save", detail=d, brief={"title":"Stale"}))
        self.assertEqual(self.detail()["brief"]["title"], "Saved first")
        d = self.detail()
        def save(n):
            try:
                self.mutate("save", detail=d, brief={"hook":str(n)})
                return 200
            except social.SocialError as e:
                return e.status
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            self.assertEqual(sorted(pool.map(save, range(2))), [200,409])
        self.assertTrue(list((Path(self.host.DATA) / "social/backups").glob("*.json")))

    def test_request_has_full_snapshot_real_owner_and_durable_idempotency(self):
        self.file()
        self.mutate("save", brief={"script":"long script " * 1200,"shots":"a long shot list " * 500})
        self.mutate("note",text="A complete long note " * 250,seconds=4)
        first = self.mutate("request",submission_id="submission-one")
        req = first["requests"][0]
        self.assertEqual(req["owner"], "claude")
        self.assertEqual(req["state"], "Filed for routing to Jordan")
        self.assertGreater(len(req["snapshot"]["brief"]["script"]), 10000)
        self.assertEqual(len(req["snapshot"]["notes"]),1)
        self.assertLessEqual(len(req["intake_payload"]["words"]),4000)
        social.bind(self.host)
        retry = social.mutate("request", {**req["payload"], "revision":0})
        self.assertEqual(retry["requests"][0]["work_id"],req["work_id"])
        again = self.mutate("request",submission_id="submission-two")
        self.assertEqual(len(again["requests"]),1)
        self.assertEqual(len(work.items()),1)

    def test_request_owner_and_state_are_read_from_live_work_card(self):
        self.file()
        d=self.mutate("request",submission_id="live-work-owner")
        request=d["requests"][0]
        item=work.load_item(request["work_id"])
        item.update(owner="sam",state="for_review")
        work.save_item(item)
        latest=self.detail()["requests"][0]
        self.assertEqual(latest["work_owner"],"sam")
        self.assertEqual(latest["work_state"],"for_review")
        self.assertEqual(latest["owner"],"claude")
        Path(work._item_path(request["work_id"])).unlink()
        self.assertFalse(self.detail()["requests"][0]["work_available"])

    def test_intake_partial_failure_reconciles_same_durable_arguments(self):
        self.file()
        original = work.api_post
        def lost_response(*args):
            original(*args)
            raise OSError("response lost after filing")
        with patch.object(work,"api_post",side_effect=lost_response):
            self.assertError(502, lambda:self.mutate("request",submission_id="lost-response"))
        pending = self.detail()["requests"][0]
        self.assertEqual(len(work.items()),1)
        self.mutate("save",brief={"title":"A later direction"})
        result = social.mutate("request",{**pending["payload"],"revision":0})
        self.assertEqual(len(work.items()),1)
        self.assertEqual(result["requests"][0]["snapshot"],pending["snapshot"])
        self.assertEqual(result["requests"][0]["intake_payload"],pending["intake_payload"])

    def test_returned_cut_note_decisions_retain_original_note(self):
        self.file()
        first=self.mutate("note",text="Hold the bird shot.",seconds=8)
        original=first["notes"][0].copy()
        sent=self.mutate("request",submission_id="returned-cut")
        self.assertEqual(sent["production"]["mode"],"active")
        self.assertEqual(sent["production"]["owner"],"claude")
        self.file(version="v2",content=b"returned movie")
        carried=self.mutate("resolve",note_id=original["id"],disposition="carry_forward")
        self.assertEqual(carried["notes"][0],original)
        self.assertEqual(carried["notes"][1]["version"],"v2")
        self.assertIsNone(carried["notes"][1]["seconds"])
        self.assertError(409,lambda:self.mutate("approve"))
        self.mutate("resolve",note_id=carried["notes"][1]["id"])
        self.assertTrue(self.mutate("approve")["approved"])
        self.assertEqual(self.detail()["notes"][0],original)

    def test_returned_cut_addressed_event_does_not_rewrite_source_note(self):
        first=self.mutate("note",text="Write an ending.",seconds=None)
        original=first["notes"][0].copy()
        self.mutate("request",submission_id="new-first-cut")
        self.file()
        current=self.mutate("resolve",note_id=original["id"],disposition="addressed")
        self.assertEqual(current["notes"][0],original)
        self.assertTrue(self.mutate("approve")["approved"])

    def test_posting_date_can_be_added_without_url(self):
        before=self.detail("feature-tour")["publication"]
        result=self.mutate("publication","feature-tour",date="2026-10-07",url="")
        self.assertEqual(result["publication"],before)
        self.assertEqual(result["posting_details"][-1]["date"],"2026-10-07")
        self.assertEqual(result["posting_details"][-1]["url"],"")

    def test_primary_action_tracks_live_work_transitions_with_and_without_cut(self):
        for with_cut in (False, True):
            ident = social.mutate("idea", {"brief":{"title":"A production idea"}})["id"]
            if with_cut:
                self.file(ident)
            sent = self.mutate("request", ident, submission_id="primary-action-" + str(with_cut))
            self.assertFalse(sent["production"]["can_request"])
            self.assertEqual(sent["production"]["mode"], "active")
            item = work.load_item(sent["requests"][0]["work_id"])
            item.update(owner="sam")
            work.save_item(item)
            d = self.detail(ident)
            self.assertIn("Sam Ortega", d["status"])
            self.assertEqual(d["production"]["owner"], "sam")
            for state, mode in (("dropped","dropped"),("accepted","completed"),("landed","completed")):
                item = work.load_item(item["id"])
                item["state"] = state
                work.save_item(item)
                d = self.detail(ident)
                self.assertEqual(d["production"]["mode"],mode)
                self.assertFalse(d["production"]["can_request"])
                self.assertNotIn("assigned", d["status"])
                self.assertIn("request",d["next_action"].lower())
            Path(work._item_path(item["id"])).unlink()
            d=self.detail(ident)
            self.assertEqual(d["production"]["mode"],"missing")
            self.assertFalse(d["production"]["can_request"])
            changed=self.mutate("save",ident,brief={"script":"A genuinely revised script."})
            self.assertTrue(changed["production"]["can_request"])

    def test_blank_optional_fields_and_file_touch_do_not_duplicate_request(self):
        ident=social.mutate("idea",{"brief":{"title":"One idea"}})["id"]
        movie=self.file(ident)
        first=self.mutate("request",ident,submission_id="first-normalized")
        self.mutate("save",ident,brief={"script":"","shots":"","caption":""})
        os.utime(movie,None)
        self.assertFalse(self.detail(ident)["production"]["can_request"])
        again=self.mutate("request",ident,submission_id="second-normalized")
        self.assertEqual(len(again["requests"]),1)
        self.assertEqual(again["requests"][0]["work_id"],first["requests"][0]["work_id"])
        self.assertEqual(len(work.items()),1)

    def test_request_level_disposition_without_notes_is_durable_and_linked(self):
        self.file(version="v5")
        self.mutate("save",brief={"script":"A revised ending.","shots":"Close on the birds."})
        sent=self.mutate("request",submission_id="brief-only-request")
        request=sent["requests"][0]
        original=json.loads(json.dumps(request["snapshot"]))
        self.file(version="v6",content=b"new cut")
        carried=self.mutate("resolve",request_id=request["request_id"],disposition="carry_forward")
        self.assertEqual(carried["requests"][0]["snapshot"],original)
        self.assertEqual(carried["notes"][0]["carried_request_id"],request["request_id"])
        self.assertEqual(carried["notes"][0]["version"],"v6")
        self.assertIsNone(carried["notes"][0]["seconds"])
        self.assertEqual(carried["request_reviews"][0]["disposition"],"carry_forward")
        self.assertError(409,lambda:self.mutate("approve"))
        self.mutate("resolve",note_id=carried["notes"][0]["id"])
        self.file(version="v7",content=b"another cut")
        addressed=self.mutate("resolve",request_id=request["request_id"],disposition="addressed")
        self.assertEqual(addressed["request_reviews"][-1]["version"],"v7")
        social.bind(self.host)
        self.assertEqual(self.detail()["request_reviews"],addressed["request_reviews"])
        self.assertTrue(self.mutate("approve")["approved"])

    def test_returned_decisions_reject_earlier_and_non_latest_cuts(self):
        self.file(version="v4")
        self.file(version="v5")
        self.mutate("note",text="Change the ending.",seconds=1)
        sent=self.mutate("request",submission_id="strict-newer-cut")
        request=sent["requests"][0]
        self.file(version="v6")
        self.file(version="v7")
        d=self.detail()
        for version in ("v4","v5","v6"):
            c=next(c for c in d["cuts"] if c["version"]==version)
            for args in ({"request_id":request["request_id"]},{"request_id":request["request_id"],"note_id":d["notes"][0]["id"]}):
                self.assertError(409,lambda:self.mutate("resolve",version=c["version"],sha256=c["sha256"],disposition="addressed",**args))
        self.mutate("resolve",request_id=request["request_id"],disposition="addressed")

    def test_corrected_posting_date_is_identical_in_collection_and_detail(self):
        before=self.detail("creamery")["publication"].copy()
        d=self.mutate("publication","creamery",date="2026-10-13",url="")
        card=next(p for p in social.list_content()["projects"] if p["id"]=="creamery")
        self.assertEqual(card["posting_record"],d["posting_record"])
        self.assertEqual(card["posting_record"]["date"],"2026-10-13")
        self.assertEqual(card["publication"],before)

    def test_nested_private_production_artifacts_are_ignored_but_sources_trackable(self):
        for folder in ("video/2026-10-14_tiktok_sheep","video/drafts/idea-0123456789abcdef"):
            for name in ("footage/raw/take.MP4","footage/transcripts/take.json","gameplay/raw/sheep.mp4","gameplay/timeline-v1.mp4","renders/video_v1.mp4","renders/video_v1.plan.json","work/frame.png","assets/titlecard/card-v1.mp4","assets/card-v1.mp4","edit/auto-take.yaml"):
                result=subprocess.run(["git","check-ignore","--no-index","-q",folder+"/"+name],cwd=HQ.parent)
                self.assertEqual(result.returncode,0,folder+"/"+name)
            for name in ("edit/script-v1.md","edit/edl-v1.yaml","edit/gameplay-v1.yaml","edit/captions-v1.txt","decisions.md"):
                result=subprocess.run(["git","check-ignore","--no-index","-q",folder+"/"+name],cwd=HQ.parent)
                self.assertEqual(result.returncode,1,folder+"/"+name)

    def test_invalid_payloads_dates_urls_and_ids(self):
        for ident in ("../sheep", "sheep/", "%2e%2e", "a"*65):
            self.assertError(400,lambda:social.content_detail(ident))
        for brief in ({"title":""},{"title":"a"*161},{"title":"yes","evil":"x"},None):
            self.assertError(400,lambda:social.mutate("idea",{"brief":brief}))
        for url in ("http://www.tiktok.com/@a/video/12","https://evil.example/12","https://tiktok.com.evil/@a/video/12","javascript:alert(1)","https://a:b@www.tiktok.com/@a/video/12"):
            self.assertError(400,lambda:self.mutate("publication","creamery",url=url))
        self.assertError(400,lambda:self.mutate("publication","creamery",url="https://www.tiktok.com/@a/video/12",date="2026-02-30"))
        self.assertError(400,lambda:self.mutate("note",text="note",seconds=float("nan")))

    def test_symlinks_and_traversal_never_serve_media(self):
        p=self.file(); outside=self.base/"outside.mp4";outside.write_bytes(b"outside")
        p.unlink();p.symlink_to(outside)
        self.assertEqual(self.detail()["cuts"],[])
        self.assertError(403,lambda:social.resolve_media("sheep","v1","video"))
        self.assertError(404,lambda:social.resolve_media("sheep","../outside","video"))
        p.unlink();p.parent.rmdir();p.parent.symlink_to(self.base)
        self.assertEqual(self.detail()["cuts"],[])

    def handler(self, **headers):
        h=types.SimpleNamespace(headers=headers,wfile=io.BytesIO(),client_address=("127.0.0.1",1),connection=object())
        h.status=None;h.sent_headers={}
        h.send_response=lambda status:setattr(h,"status",status)
        h.send_header=lambda k,v:h.sent_headers.update({k:v})
        h.end_headers=lambda:None
        return h

    def test_streaming_ranges_and_missing_hash(self):
        self.file(content=b"0123456789")
        sha=self.detail()["current_cut"]["sha256"]
        for value,code,expected in [(None,200,b"0123456789"),("bytes=2-5",206,b"2345"),("bytes=7-",206,b"789"),("bytes=-3",206,b"789"),("bytes=0-1000",206,b"0123456789"),("bytes=100-",416,b""),("bytes=-0",416,b""),("bytes=1-2,4-5",416,b""),("garbage",416,b""),("bytes="+"9"*5000+"-",416,b"")]:
            h=self.handler(**({"Range":value} if value else {}))
            social.serve_media(h,"sheep","v1","video",sha)
            self.assertEqual((h.status,h.wfile.getvalue()),(code,expected),value)
            self.assertEqual(h.sent_headers["Cache-Control"],"private, no-store")
        self.assertError(409,lambda:social.serve_media(self.handler(),"sheep","v1","video",""))

    def test_origin_json_size_guards_precede_body_read(self):
        valid={"Content-Type":"application/json","Content-Length":"2","Host":"localhost:8643","Origin":"http://localhost:8643"}
        self.assertEqual(social.guard_write(self.handler(**valid)),2)
        for update,status in [({"Content-Type":"text/plain"},415),({"Origin":"https://localhost:8643"},403),({"Origin":"http://localhost:8642"},403),({"Content-Length":"100001"},413),({"Content-Length":"-1"},413),({"Transfer-Encoding":"chunked"},400),({"Origin":"null"},403),({"X-Forwarded-Host":"evil","Origin":"https://evil"},403)]:
            self.assertError(status,lambda:social.guard_write(self.handler(**{**valid,**update})))
        proxy={**valid,"Host":"daniel-maco.tail445099.ts.net","Origin":"https://daniel-maco.tail445099.ts.net","X-Forwarded-Proto":"https"}
        self.assertEqual(social.guard_write(self.handler(**proxy)),2)
        proxy["Host"]="evil.example";proxy["Origin"]="https://evil.example"
        self.assertError(403,lambda:social.guard_write(self.handler(**proxy)))

    def test_http_write_guard_and_errors(self):
        request=object.__new__(server.Handler)
        request.path="/api/social/save";request.connection=object();request.client_address=("127.0.0.1",1)
        request.headers={"Content-Type":"text/plain","Content-Length":"999999","Host":"localhost"}
        class NoRead:
            def read(self,*args): raise AssertionError("body read before guard")
        request.rfile=NoRead();sent=[];request._send=lambda status,data:sent.append((status,data))
        request.do_POST();self.assertEqual(sent[-1][0],415)
        request.headers={"Content-Type":"application/json","Content-Length":"2","Host":"localhost"};request.rfile=io.BytesIO(b"[]")
        request.do_POST();self.assertEqual(sent[-1][0],400)

    def test_observations_are_dated_and_followup_remains_linked(self):
        d=self.mutate("observation","creamery",text="More animals please.",url="https://example.com/comment")
        self.assertTrue(d["observations"][-1]["created_at"])
        self.assertEqual(d["observations"][-1]["text"],"More animals please.")
        self.assertError(400,lambda:self.mutate("observation",text="Not posted"))


if __name__ == "__main__":
    unittest.main()
