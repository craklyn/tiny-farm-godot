# Social videos in Tiny Farm HQ

## Purpose and design rules

Daniel asked on 2026-10-22 for a place to manage, design and build social media content, beginning with the two published videos and the almost-finished sheep video. He explicitly wants the published work and the changing work to be different kinds of records.

He also asked: “Can you show a in-development-but-whenpossible-working preview while you work? On the HQ page in its designed location, linked to the page in the designed manner?” Show evolving HQ pages through their intended navigation on the normal HQ address while they are being built. Mark preview state clearly, isolate production effects, preserve useful preview edits, and provide a reversible local installation. An isolated developer address alone does not fulfill this request.

This page closes a loop: audience response → a content idea → a brief and script → footage and cuts → Daniel's review → a published post → audience response. The feature tour, creamery and sheep already trace that loop. The page must make that relationship visible.

Daniel supplies direction, records his performance, judges the cut and decides what goes public. Jordan Lee owns TikTok content strategy and production; Carmen Ortiz owns marketing strategy. They are HQ personas, not independent employees who can be credited with activity that has not happened. A saved brief is not a started job. A queued request is not a finished edit.

The daily question is “What needs my attention to get the next good video out?” The working cut leads. Published work is easy to revisit beneath it. Avoid a calendar, follower counters, empty channel columns and invented targets until there are facts or a task that make them useful.

## Record model

A **content project** is mutable: idea, audience promise, hook, script, planned shots, source comment, production requests, render versions and review notes.

A **publication** records what actually went out: platform, fixed render version, original evidence, post URL and posting date when known. It never follows the newest render automatically. More than one publication can eventually point at one project. Editing a published video's idea produces a follow-up project, rather than changing its history.

Statuses are derived from evidence: publication records, actual files, saved direction, recorded review events and real work requests. There is no editable status selector. Missing media, unknown posting dates, unavailable account metrics and unknown build recipes stay explicit.

Approval is a recorded human decision, tied to the SHA-256 of the current file. A new cut or a changed file requires another review. A note belongs to a specific file hash and optional playback time; it must never silently move onto a later cut. Approval does not post anything externally.

## First version

### Collection: `#/social`

Add “Social videos” to HQ's navigation and a doorway from Marketing. Use HQ's typography and spacing, with actual available artwork and video frames. Make it responsive.

Show the sheep video prominently under “In the making”: current cut, latest file activity, next action, owner and link to review. List all three projects on arrival, with the feature tour and creamery visibly grouped under “Published”. Published cards open publication pages; the sheep card opens the working review. New idea opens a short form for title, audience promise, hook, source comment/link and what viewers should be asked.

Do not assume a folder's date is its posting date. Do not use a thumbnail from a different cut without labeling it. The feature-tour end-card image can be identified as artwork if the movie is absent.

### Working video: `#/social/<id>`

Lead with the real, seekable vertical video and the next decision. Show the current version by default, with earlier cuts available in a selector. “Add note at 00:12” captures the current playback time; clicking a note seeks the player. Explicit general notes are allowed when no cut exists.

Beside the player, show the editable content brief and review notes. The brief includes an editable script/outline and planned shots, so an idea can be designed before footage exists. For a new idea these lead the detail page, with “Develop with Jordan” and “Send production brief”. Show any existing recorded script and decisions in a folded source section as read-only source material. Editing the planning outline is direction for the next production pass, not a silent rewrite of the recorded script.

“Send revision brief” saves a concrete production request containing the project, exact cut, open notes and saved brief into HQ's existing work system. Its existing intake assigns the chief of staff; include Jordan's production responsibility in the brief and label the result “Filed for routing to Jordan”. Link the returned work card and actual owner. Repeated submissions of the same request must not duplicate work.

“Approve this cut” records approval only for the current hash and only when the current cut has no unresolved review notes. Notes can be explicitly marked addressed; retain their record. Earlier-cut notes remain discoverable on that cut. A new cut does not inherit approval or silently resolve notes.

When a newer cut arrives after a revision request, display “You asked for these changes” beside it, using the submitted request snapshot. Let Daniel explicitly mark an earlier request addressed or carry it forward as a linked note on the new cut. Preserve its original version and timestamp. This avoids making him reconstruct the review by switching between old cuts.

The primary action follows actual responsibility: before handoff, send the brief; after handoff, show the linked task, actual owner and current state; when a different cut arrives, review the new cut; after approval, prepare the post. A queued revision is not still an untouched request for Daniel to review the same cut.

After approval, offer posting preparation: an editable post caption, the source comment/reply context, a download of that exact approved file, and “Record published post”. Recording publication requires a valid HTTPS post URL and the current approved render hash. This records an event; it does not upload or post. Snapshot the approved hash, caption and version. Later changes cannot alter that publication. Missing or modified files must never be served as the published copy.

### Published video

Lead with the posted version and a link to the actual post when recorded. If the movie or URL is unavailable, say so in place and keep the evidence and final version visible. Do not fall back to a newer cut.

Show the audience promise, the posting record, source comment, subsequent video links and audience responses. The creamery page links back to the feature tour and forward to the sheep response. A follow-up action carries the source video/comment into a new idea brief.

Allow adding the missing post URL/date as a new record without changing historical creative facts. Allow dated audience-response notes with an optional source link. Do not invent analytics or imply live account access. At this scale, a useful comment and the next experiment are more useful than an empty analytics chart.

### Planning and production

New ideas are real persisted projects, with safe generated identifiers. Reserve their working artifact location as `video/drafts/<generated-id>/`, with renders named `renders/<generated-id>_vN.mp4`. This is a planned working folder, separate from the recording-date folders of the three existing videos; creation of an idea need not create media files. Include that exact output path in every production brief and discover numerically versioned files there on refresh, so a newly planned video can receive its first real cut. Document this additional planning layout in `video/README.md`.

A saved brief can be sent into the existing production queue. The page must show the returned task, actual owner and honest request state. No renderer is offered in this first version. Main's sheep folder lacks composition inputs, while the open editing PR contains them and still needs generated intermediates rebuilt on its matching tool version.

Production briefs should include the video-editing workflow and source paths so an executing session can make the next cut. Every build must retain earlier renders, document the new inputs and return a version for review. A source comment is creative context, not permission to change the game design or publish publicly.

## Initial evidence

| Project | Initial record | Evidence |
|---|---|---|
| Feature tour | Published; v4 is the posted version; posting URL/date not yet recorded; final MP4 absent locally | Daniel's request; `video/2026-10-06_tiktok_feature-tour/decisions.md`, “v4” and “After v4” |
| Creamery | Published; v2 posted 2026-10-12; posting URL not yet recorded; final MP4 absent locally | `video/2026-10-12_tiktok_creamery/decisions.md`, “Posted” |
| Sheep | In production; available cuts v1–v5; current cut needs Daniel's review; no recorded approval/publication | Daniel's request; actual `renders/` files in the main checkout; open editing [PR #31](https://github.com/craklyn/tiny-farm-godot/pull/31), head `c8fee07b84aa1dbbee8376a31db5a22a8bdebb22` |

The sheep response came from A. A. Nahi's creamery comment, “Ar ethere sheep 🐑?”. The proposed delivery is a TikTok video reply; that remains a recommendation, not a settled instruction. Historical open questions inside published videos' decisions files are historical, not new blockers.

The newer sheep source is on the open edit branch `claude/sheep-tiktok-edit`. Its [version-pinned decisions](https://github.com/craklyn/tiny-farm-godot/blob/c8fee07b84aa1dbbee8376a31db5a22a8bdebb22/video/2026-10-14_tiktok_sheep/decisions.md#L152) record Daniel's voice-over-only direction (no face), and lines 182–207 record v4/v5: “Buddyo Vlogs” spelling; re-staged growth so the sheep stops; neck stretch removed. Link the real editing PR on the draft and distinguish its source from main's older notes. Do not merge it as part of building HQ.

The actual v5 MP4 is 36.8368 seconds at 1080×1920 (measured by ffprobe). The `.plan.json` total 34.635 covers only voice/gameplay, excluding the end card. Do not treat that value as the full movie duration; browser media metadata is authoritative for playback and duration. PR inputs are `edl-v1.yaml`, `captions-v4.txt`, `gameplay-v5.yaml`; all required raw sources are present, but generated `timeline-v5.mp4` and `card-v1.mp4` are absent. This is an unmerged production recipe, not a missing recipe everywhere.

## Ground rules for implementation

- Use the existing stdlib HQ server and frontend. No runtime dependencies or network calls are required for this page.
- Keep main's running checkout clean. Implement in `/tmp/tiny-farm-social-hq`, branch `codex/social-video-hq`, based on main `408053746f3ebf2b38a084538c455d98805b6f78`.
- Curated import facts belong in repository configuration; new briefs, notes, approvals and posting records belong in HQ's independent live store under `social/`, through its existing storage helpers. Register the new store directory with existing migration/classification logic if required. Never commit work cards or live social records.
- Resolve actual media separately from HQ's old user workspace: the sheep media is in `/home/daniel/dev/tiny-farm-godot-main/video/`. Support explicitly configured content roots and tests; restrict serving to known project render files and known artwork. Do not expose raw camera footage or arbitrary paths.
- Validate every write server-side; escape all text; enforce bounded fields, valid URLs and safe identifiers. Existing server writes have no general origin guard: social mutations must explicitly require JSON and reject a supplied Origin that differs from the actual request origin, including scheme/host/port (respect the existing trusted tailnet proxy deployment without allowing arbitrary forwarded hosts). Reject oversized bodies before reading them. Use atomic writes, automatic backups and compare-and-swap revision tokens. A stale tab receives 409 and preserves its unsaved text.
- Range requests must support seeking without reading a movie into memory. Missing files are a clear unavailable state. Reject traversal, symlink escapes and malformed/unsatisfiable ranges appropriately. Serve private media with appropriate content type and no shared cache.
- Never overwrite source footage, renders or scripts. A user cannot revise a published creative snapshot through a draft endpoint. Verify approval/publication against current file hash on the server, not a filename or client claim. Cache hashes against sufficient file identity metadata.
- Keep review writes serialized and durable across restart. Production request idempotency must survive repeated clicks/retries. Report failures without a success message.
- No external posting, upload, credentials or automatic metrics scraping. No costly jobs or unattended production are started by page load or saving a note.

## Source map

Cite this survey rather than re-surveying. Line numbers refer to base `40805374`; read only the integration points needed to implement.

| Concern | Source and established behavior |
|---|---|
| Server integration | `hq/server.py:45,50,57,7249,7434`: stdlib threaded HTTP server, sibling imports, explicit GET/POST routing; `HQ_DIR`, `REPO`, `USER_WORKSPACE`, `DATA` are distinct |
| Config and live roots | `hq/roots.py:27,38,72`; `hq/server.py:84,96`: classify `social/` as live, seed catalog as repo-owned; `cfg()` reads curated config from code when store is external |
| Store history | `hq/store.py:12,20,35,193`: external store commits settled changes; no MP4s in that Git store |
| Safe mutation precedent | `hq/work.py:225,282,355`: atomic JSON replace, process-safe flock plus thread lock, optimistic revision checks |
| Safe prose/frontend | `hq/static/app.js:42,239,254,265,375`: shared globals `h`, `esc`, `md`, `mdi`, `$view`, `routes`; marked + DOMPurify; `design.js:42` has `mdDoc()` for source documents |
| Frontend integration | `hq/static/index.html:24,71`: primary nav, classic script includes after app.js; `app.js:386,462,473`: active section plus detail routing; `design.js:15`: module registration and initial deep-link routing |
| Cache warning | `hq/static/app.js:8`: `api()` retains GETs; use fresh direct fetch for changing social data and invalidate after mutations |
| Parked Marketing | `hq/data/surface.json:9`; `hq/static/surface.js:25`: `/pillar/marketing` descendants parked, so route independently at `/social`; add doorway only if an existing visible Marketing surface supports it |
| Existing file sender | `hq/server.py:7214,7234`: whole-file 200 responses, no Range support; implement a separate bounded streaming media route |
| Work intake | `hq/work.py:4744–4776`: `work.request` via existing `/api/work/request` accepts words 1–4000 chars, kind `work`, request_id 8–100 safe chars; same ID/payload returns same record; actual owner `claude`; preserve exact arguments after reading function signature |
| Persona discussion | `hq/static/app.js:1792,1814`: set `sessionStorage['hq-chat-draft']`, navigate `#/chat/jordan`; send nothing automatically |
| Tests | `hq/tests/test_record_revisions.py:15` temporary fake host; `test_live_records.py:27` storage classification; `test_navigation.js:10` asserts primary nav; `test_dashboard_browser.js:11,52` browser checks |
| Publication evidence | Feature-tour decisions `:74,84`; creamery decisions `:139`; sheep decisions `:3,14,22,53`; org Jordan `:518,525,527`, Carmen `:479` |
| Unsupported renderer | `video/tools/compose.py:25,173,233,274` private helpers, mandatory EDL/gameplay, caption-only plan, ffmpeg overwrite flag; `video/tools/record_shot.sh:6,14,19` modifies config and requires display |

## Implementation work item

One worker implements the whole cohesive page in the prepared worktree, with focused tests, so backend and frontend contracts stay together. Use these interfaces unless the review identifies a concrete reason to revise them:

```python
social.bind(server_module)
social.list_content()
social.content_detail(content_id)
social.mutate(command, payload)  # command whitelist; revision checked
social.resolve_media(content_id, version, kind)  # no client filesystem paths
```

Expose `GET /api/social`, `GET /api/social/<id>`, `POST /api/social/{idea,save,note,resolve,approve,publication,observation,request}` and `GET /social-media/<id>/<version>/{video,subtitles}`. Use a separate known artwork route if necessary. API responses carry a revision token; command payloads carry the last observed revision. Media-bound commands additionally carry the exact version and SHA-256 displayed to the user; validate those against the same selected file, and for approval/publication against the current latest cut as well. External media changes do not change the social record revision, so neither approval nor notes may silently bind to whichever file is latest at click time. Commands return updated detail or a typed error. A new idea has no existing revision. Errors use appropriate non-200 HTTP status, including 409 for stale edits.

Keep editable records under the independent store's `social/`; seed catalog facts under `hq/data/` are curated configuration, not live records. A published seed may have no render hash because its movie is absent; label its version as documented and do not claim byte identity. Newly recorded publications require the actual approved hash. Add missing seed post URLs/dates through an append-only posting detail event, without needing unavailable historical hashes. Allow only HTTPS supported social-platform post URLs for publications; audience sources may be ordinary safe HTTPS URLs.

The work request adapter calls the existing supported work intake, with a deterministic safe request ID derived from content ID and the submitted cut/brief/notes snapshot. Persist the complete production snapshot under the social record and send a concise request of at most 4000 characters linking to it; do not silently truncate notes or brief fields. Record the returned work ID only after success. To avoid partial failure and duplicate tasks across retries, use the intake's durable idempotency and reconcile by the same request ID. Preserve the original request payload for retries. “Develop with Jordan” only prefills chat.

Read in order: this plan, project instructions, then named server/frontend integration points, root/store helpers and the existing request function. The actual source decisions/script can be read to seed concise accurate content. Do not redesign or activate the parked marketing campaign or its posting schedule.

## Verification and acceptance

1. The page initially shows exactly the two known publications and one changing project, with different detail views and source-backed facts. Published missing media does not hide a video or turn a later render into the posted copy.
2. Sheep v5 plays and seeks from its real location. Version selection and timestamped notes work. Notes survive reload, stay attached to their render, and do not mutate an older cut's record.
3. Approve, add a newer cut/change a file, and observe the prior approval no longer applies. Approval and publishing reject stale hashes or unresolved current-cut notes. Publication retains its version/hash/caption after later draft edits.
4. New idea → brief save → production request creates a real linked HQ work item, once. Failure leaves the brief and notes available. Follow-up preserves its source relationship. Place a versioned test cut at the new idea's reserved output path and confirm it becomes playable, reviewable and approvable.
5. Concurrent edits cannot overwrite a newer record. Traversal, symlinks, invalid payloads, published draft writes and invalid ranges are covered by focused tests using temporary roots/store only.
6. Check the actual desktop and narrow-screen layout, page navigation, player controls and note/approval interactions in a headless browser if available. Save screenshots for review. Live writes during QA must use an isolated store.
7. Run appropriate HQ tests, gateway, both Godot suites, required writing/CI checks and JavaScript syntax checks. Follow the existing repository gates; do not weaken an assertion to pass.

Exact required commands (with root overrides unset for the test aggregate):

```bash
python3 hq/tests/test_social.py
node hq/tests/test_social_browser.js
python3 tools/check_frontend.py
python3 hq/run_tests.py
python3 tools/check_gateway.py
python3 tools/run_godot_test.py -- godot --headless --path . --script res://tests/test_runner.gd
python3 tools/run_godot_test.py -- godot --headless --path . res://tools/test_runner.tscn
python3 tools/check_writing.py --verify
```

The HQ aggregate discovers new test files; expected final line is `HQ tests: N/N files passed; 0 failed; 0 skipped.` Import Godot first if fresh checkout assets require it. Report baseline/environment failures separately and never call a failed gate passed. Record screenshots under `/tmp`, and test mutations against isolated store roots only.

Worker completion: commit explicit feature/test/doc paths on `codex/social-video-hq`, do not push until the parent has reviewed. Return a report under 300 words with changed files, actual test counts/results, screenshot paths, worktree/branch/commit, and anything in the plan that was wrong or needed judgment. Do not loosen assertions to pass; report the measurement and stop if a requirement cannot be met.

## Execution status

- 2026-10-22: Read the HQ and video workflows, role records and seat notes. Confirmed three projects and publication evidence. Created an isolated worktree. Read-only integration survey complete and incorporated above. Design is a first reviewable proposal; Daniel has not approved a new ongoing cadence, content strategy or external publication.
- Pre-build review found four gaps, now incorporated: displayed render hash is required independently of record revision; social writes need their own origin/JSON/body-size guard; complete request snapshots must fit through a concise 4000-character intake request; new ideas need a reserved production output folder and a tested path back into review. Public branch push is blocked pending Daniel's permission; all implementation and QA remain local.
- Product review identified three refinements for the review pass: an editable pre-footage script/outline and planned shots; the previous revision request beside a newly arrived cut with explicit addressed/carry-forward actions; and a primary action that changes as responsibility moves from Daniel to production and back. These are requirements to check in the implementation review.
- Additional source review found the open sheep edit PR and v5 changes documented above. Verify that seed copy links it, describes voice-over rather than talking head, and uses actual movie metadata for duration. This changes the initial “no recipe” finding to “recipe is on the unmerged editing branch”.
- First implementation review found a lost-edit case: unsaved browser buffers must retain the revision they were edited against. Restoring a buffer after navigating away must not attach the server's newer revision and overwrite another tab's saved brief. Test this exact two-tab/navigate-back case.
- First implementation review found that `#/design/doc/video/...` source links cannot work: the existing document API allows only `docs/*.md`. Use supported read-only source viewing or local source controls, never a broken link.
- The first implementation must receive a correction pass for the product-review requirements above: planning leads a no-cut idea; the action changes after a real production handoff; a returned cut shows prior requests with explicit addressed/carry-forward actions; seed copy reflects the open sheep editing work.
- Existing published videos may receive a known posting date while their post URL remains unknown. Append-only metadata corrections must accept a date alone or a URL alone; newly recorded publications still require a valid post URL and the approved current movie.

### Correction pass briefing

For the active worker's source question, the exact already-verified source is PR **31**, `https://github.com/craklyn/tiny-farm-godot/pull/31`, branch **claude/sheep-tiktok-edit**, head **c8fee07b84aa1dbbee8376a31db5a22a8bdebb22**. No new network query is needed. Pinned source URL: `https://github.com/craklyn/tiny-farm-godot/blob/c8fee07b84aa1dbbee8376a31db5a22a8bdebb22/video/2026-10-14_tiktok_sheep/decisions.md`. Lines **152–168** record Daniel's voice-over-only, no-face direction. Lines **182–187** correct the channel spelling to **Buddyo Vlogs**. Lines **189–207** record v5: re-stage growth so she stops; omit the neck stretch; the bald ring plays under “They graze the grass”. Lines **206–207** name `edit/edl-v1.yaml`, `edit/captions-v4.txt`, `edit/gameplay-v5.yaml`. This source is in an **open, unmerged editing PR**, not main. The actual v5 is **36.8368 seconds**, 1080×1920. Do not mark it approved or published.

The read-only implementation reviewer identified seven corrections in the first pass:

1. Keep an unsaved buffer's original revision across navigation, not the freshly fetched server revision (`social.js` remember/change/detail). Cover two tabs and leaving/returning before saving.
2. Derive the next action from a submitted revision request and its actual linked work-card state. After handoff, do not keep asking Daniel to approve that same cut. Read current task status; distinguish a missing task from a waiting task.
3. On a different returned cut, show the previous submitted changes and explicit addressed/carry-forward controls, preserving old cut/hash/timestamp. Carrying forward creates a linked current-cut note, rather than rewriting the old note.
4. Correct the sheep seed using the pinned facts above; link its editing work; describe current layout accurately.
5. Fix source links: the design-doc API only accepts `docs/*.md`; do not link video sources into it. Existing inline sources can have working expand/scroll controls instead.
6. No-cut ideas lead with editable outline/script and shot planning. The empty-player review state belongs after a cut arrives.
7. Permit date-only or URL-only append-only corrections to imported publication metadata.

The “no egress” hold applies to publishing the design/code on public GitHub and external uploads/posting. Normal project quality checks, including the **existing configured writing judge**, are authorized by the repository's required-gate instructions; the root's local commit hooks have already invoked that configured check. Register the new frontend/catalog writing surfaces and run the actual required judge as appropriate; do not fabricate verdicts. If automatic approval review rejects the configured judge, report the action and stated reason, and leave its verdict honestly unjudged. No public pushes, external content uploads or posts are authorized.

Parent's screenshot review: the first `social-published-desktop.png` clips the missing-movie explanatory line at the bottom of the artwork panel. Give that text natural layout outside any fixed-height/overflow-hidden media crop; do not clip messages. On a narrow screen, unavailable artwork should stay compact enough that the posting record is readily reachable. The first `social-review-desktop.png` catches the player at 12 seconds with a black buffering spinner. Re-capture after a decoded frame is actually available (`seeked`/readyState/video-frame callback), and confirm actual playback/seek visually before reporting it works. This may be capture timing, but the screenshot alone does not prove a decoded movie frame.

Posting preparation should surface the existing sheep soundtrack credit, rather than leaving the known requirement buried in source notes: `Music: Wholesome by Kevin MacLeod (incompetech.com), licensed under CC BY 4.0.` The pinned editing decisions record the soundtrack at lines 142–143; later versions retain it. Present this as a posting note/copyable line, not a claim about an already published sheep caption. TikTok's native comment reply remains a recommendation awaiting Daniel's choice.

### Verification follow-through

The correction reviewer confirmed original revision retention is fixed, but found these remaining cases in the next pass:

- `social.py` detail still treats saved `work_id` as current work ownership/state. Read the actual linked card on detail refresh; surface reassignment/completion/drop/missing state honestly. No-cut ideas must also switch their main action after a real handoff.
- Returned-cut disposition currently requires a source note. A request containing only changed brief/script/shots also needs request-level addressed/carry-forward controls; a carried-forward request can become a linked general note on the new cut.
- Earlier cuts are incorrectly labeled “Returned from production” and given actions the server rejects. Only a cut genuinely newer than the request's selected cut qualifies; action availability must match latest-cut server eligibility.
- The collection still reads the frozen seed posting date instead of merged append-only posting details. A date correction must appear consistently on both collection and detail.

The nested-folder compatibility survey confirmed the actual production helpers accept nested content folders if `edit/` remains directly below the content folder. However, the existing one-level `.gitignore` media patterns miss `video/drafts/<id>/...`. Extend them recursively or add explicit nested equivalents for footage, gameplay, renders, scratch work, generated movie assets and automatic edits. Verify with `git check-ignore` against representative old and nested paths; editable script/EDL/shot source files must stay trackable.

Update README examples to use repository-based absolute `PY`, helper and music paths so both old and nested folders work; update its discovery globs for nested drafts. Add a production-brief sentence to use repository-root/absolute helper paths. No production-helper code change is needed.

The final functional run reported HQ **93/93** test files, **21** focused backend tests, Godot unit **3780/0**, integration **1451/0**, plus browser/gateway/frontend checks. The writing gate now discovers **90** unjudged pieces; run the **existing configured writing judge** to produce genuine required evidence. The parent authorizes that required quality-check command under the existing repository instructions, just as the configured commit hook was authorized. The public-GitHub push hold remains. A failed or automatically rejected judge stays explicitly unjudged; never synthesize verdicts.

Writing authorization outcome: automatic approval review rejected the judge. A read-only inspection then established the exact destination as **OpenAI's Codex service, gpt-5.6-luna**, and the payload as the writing guide, prior wording rulings, review instructions and batches of up to 25 uncached displayed prose strings. The parent requested review again with that new evidence; it was **rejected again** because trusted human approval of that specific payload/destination is required. Do not retry the judge or invoke it through hooks until Daniel explicitly authorizes it. Complete local functional/privacy checks and preserve unjudged results. Public GitHub publication separately requires Daniel's explicit approval. These holds supersede the parent's earlier interpretation of the normal quality-gate authorization.


### Final correction implementation (2026-10-22)

The final correction pass derives the main action from the live linked card (including reassignment,
cancellation, completion without a new cut, and an unavailable card), and removes unchanged duplicate
send controls after handoff. Whole-request review decisions now retain their own events; carrying a
brief forward creates a linked general note on the latest cut without rewriting the submitted snapshot.
Both the frontend and server restrict returned-cut decisions to numerically newer cuts and writes to
the latest cut. Collection and detail use the same append-only posting-date corrections.

Nested footage, gameplay, renders, scratch work, movie assets and automatic edits are now ignored at
all video folder depths. Regression checks prove that script, EDL, caption and shot source remain
trackable in both folder layouts. README and routing briefs use repository-root helper paths. Posting
preparation displays the known Wholesome credit as a copyable posting note; it does not replace the
editable caption or assert that sheep is published.

Verification: 28 focused backend tests passed; the expanded real-browser test passed; the HQ aggregate
reported `HQ tests: 93/93 files passed; 0 failed; 0 skipped.` Frontend globals, syntax and diff checks
passed. Godot was unchanged in this pass; its preceding results remain 3780 unit and 1451 integration
checks passed, zero failures. The isolated preview remains at `http://127.0.0.1:8643/#/social`, with data
under `/tmp/social-hq-preview-data` and read-only media from main's `video/`.

The actual configured writing check was requested, but automatic approval review rejected it before
execution: it said the transcript lacked trusted user authorization to send the new prose to the
writing service. Local routing evidence identifies that service as OpenAI's Codex service using
`gpt-5.6-luna`, receiving uncached HQ wording together with the writing guide and existing rulings.
No external judge or indirect hook workaround ran after that rejection. Offline verification currently
reports 95 unjudged pieces. The final correction commit is pending the required writing authorization
and genuine verdicts. The earlier local implementation subjects also need their normal subject checks
once authorized: "Add a social video workspace to HQ" and "Keep planned video folders and long titles clear".
No public push, PR, content upload, social post or live-store change occurred.


### Linked preview isolation review

Before the normal HQ installation, the independent reviewer found two configuration failure cases. A present but empty `HQ_SOCIAL_PREVIEW_UPSTREAM` must produce a handled 503 for Social routes, never fall through to the live writer; only an absent variable permits ordinary production routing. A previously marked preview store must reject symlinks anywhere in its writable content, including `social`, `work`, nested directories and record files. A resolved root alone does not establish isolation. Add focused regression checks before installation.

Daniel explicitly authorized the reversible local preview in the normal HQ navigation. The separate holds on the external writing check and public GitHub publication remain. Preview notes and requests belong to the persistent private preview store; all other HQ routes retain their original live store.


### Linked local preview installation (2026-10-22)

Daniel asked: “Can you show a in-development-but-whenpossible-working preview while you work? On the HQ
page in its designed location, linked to the page in the designed manner?” That authorizes this
reversible local preview/restart. It does not authorize the rejected writing judge or public publication.

The regular HQ now serves the feature static files and designed Social videos navigation at
`http://localhost:8642/#/social` (also the existing private tailnet HQ URL). Its persistent service file
is unchanged. A runtime-only drop-in selects `/tmp/tiny-farm-social-hq/hq/server.py` and sets
`HQ_SOCIAL_PREVIEW_UPSTREAM=http://127.0.0.1:8644`:

`/run/user/1000/systemd/user/tiny-farm-hq.service.d/90-social-preview.conf`

Only `/api/social`, its descendants, `/social-media/` and `/social-art/` go to the isolated sidecar.
Other HQ routes retain normal handlers and live roots: data `/home/daniel/tiny-farm-hq-data`, user
workspace `/home/daniel/dev/tiny-farm-godot`, and main `/home/daniel/dev/tiny-farm-godot-main`. A present
invalid or empty upstream fails closed; it never falls back to live social writes. The fixed loopback
proxy preserves range/status/private headers and the actual Host/Origin, with bounded request bodies
and streamed movie copying.

The transient user unit `tiny-farm-social-preview.service` runs the no-background-worker helper on
8644. Its persistent private records live at:

`/home/daniel/.codex/visualizations/2026/10/22/01a16582-dcb4-7080-8391-f604fac11ed4/social-preview-data`

The helper requires an explicit persistent-preview option, a fresh or correctly marked private
directory, and no overlap with live stores, code/media roots or their ancestors. It rejects symlinks
throughout existing records and writable folders before binding writers. Preview receipts open the
full saved brief inline and never navigate scratch work IDs into live Work pages. The earlier
independent 8643 preview may remain; the regular HQ uses only the persistent 8644 sidecar.

Both runtime units/overrides disappear at reboot, returning the unchanged stable HQ service definition.
The private edits remain. Original unit snapshots, installation metadata and the rollback script are in
`/home/daniel/.codex/visualizations/2026/10/22/01a16582-dcb4-7080-8391-f604fac11ed4/social-preview-install/`.
To roll back now, run its `rollback.sh`: it removes only the runtime preview drop-in, reloads/restarts
normal HQ, then stops the sidecar. Refresh HQ afterward. No persistent service file, main source file,
source media or live card was edited for the preview.

Actual normal-HQ browser verification passed: designed nav/deep links, real decoded sheep v5 at 00:22,
same-origin preview notes and work intake, inline request receipts, and normal Overview/Work/health.
All 376 live work-card byte hashes were unchanged before/after QA; the preview request ID was absent
from live work. Only temporary QA records were moved into the private `qa-artifacts/` folder afterward,
so the visible library still contains the intended three projects. Actual tailnet GET returned preview
data; a non-mutating same-origin validation POST reached its expected missing-record 404 rather than an
origin rejection. Screenshots and the verification record are under `/tmp/social-hq-linked-review/`.
The proxy/store regressions cover range serving, foreign-origin/body guards, failure isolation,
persistent-store marking, root overlap, empty configuration and nested symlink rejection. Writing
verification remains honestly unjudged; no new judge, hook workaround, public push, upload or post ran.


Linked-preview gate results: the complete HQ aggregate passed **94/94 files, zero failures or skips**;
focused social behavior passed **28 tests** and proxy/store isolation passed **12 tests**. The formal
browser regression also passed with inline-preview receipt assertions. Frontend globals, JavaScript
syntax, gateway and diff checks passed. Offline writing verification reports **97 unjudged pieces**;
the rejected judge/public-publishing holds remain. The uncommitted feature is also backed up privately
as `social-preview-install/feature-preview.patch`, beside the unit backup, so `/tmp` loss does not lose
the reviewable changes. No writing hook was used to bypass the rejected quality check.


### Recording script reader — Daniel's request, October 22

Daniel said: “I think I still want to re-record it. Let's add that script sub-page to the sheep page in HQ so I can read it while recording.” The sheep video chat owns the narration and supplies its exact source; this HQ work owns only the recording reader.

Add `#/social/sheep/script`, reached by a prominent “Read script” link on the Sheep page. Use the current saved content-brief script when nonempty, otherwise the exact source narration supplied by the video chat. Never overwrite an existing user-edited brief/script during seeding. The reader must disclose whether it shows the saved working script or the supplied source. Preserve script text and paragraph breaks; safely render text, never raw HTML.

Keep the recording view focused: the full narration in large readable text, comfortable line width/spacing, a title, a clear back link to Sheep, and simple text-size controls. It must work at the normal localhost and tailnet HQ addresses, by both link and direct deep link, on desktop and narrow screens. No automatic scrolling, microphone/camera access, upload system, animations or recording integration. Do not embed production notes or timecodes in the spoken script. An unavailable script is an honest empty state linking back to edit the brief; it is not fabricated narration.

Keep the existing local-preview boundary and persistent edits intact. No main checkout edits or service reconfiguration are needed for this frontend/data refinement; restart only the isolated preview backend if its catalog cache requires it. No source movie or edit recipe changes. The external writing judge, commit hooks invoking it, and public push/PR remain held pending explicit human approval. New wording remains unjudged honestly.

Acceptance: observe the Sheep link and direct reader URL in the actual normal HQ, confirm large text and text-size controls visibly work, verify return navigation, and confirm an isolated saved-script override wins over the fallback without changing existing user records. Add only focused browser coverage for the new route/source selection where meaningful; run the affected frontend/browser checks, then the HQ aggregate for this route change. Capture desktop/narrow reader screenshots. Preserve private patch backups and stage only the known feature files; do not commit through a held hook.


The video chat supplied the exact source: `/home/daniel/dev/tiny-farm-godot-main/video/2026-10-14_tiktok_sheep/edit/script-v2.md` (local, untracked; 14 spoken paragraphs). It corrects “Buddyo Vlogs”, uses Daniel's “when they got to that point”, and removes the neck-stretch line. That chat owns the words; do not rewrite them or publish this file. Prefer the saved working script if Daniel has entered one; otherwise read this source at request time through the existing source/media root boundary. No production notes or timecodes belong in the read-aloud body. Record source selection outside the spoken text, without exposing filesystem paths in the reading flow. Add an optional native fullscreen control if supported; manual scrolling remains sufficient. Text size may be remembered in browser storage. The source owner asks for the live route, source location, changed files and actual verification when ready.


Source-owner clarification: copy the exact `script-v2.md` into the matching feature-checkout path and stage it as part of the HQ feature. Existing source-document resolution uses the feature checkout, so this keeps the reader independent of PR31. Do not change the original main-checkout file. Only its heading is non-spoken; retain all 14 narration paragraphs verbatim. The source owner's survey found the saved working script empty; later saved user edits still take precedence.


Recording reader implementation (October 22): `#/social/sheep/script` is linked by the Sheep page's
Read script button. The exact supplied `video/2026-10-14_tiktok_sheep/edit/script-v2.md` is copied into
this feature checkout byte-for-byte and staged; the main source is unchanged. Detail reads the current
source on each request and removes only its non-spoken title. A nonempty saved brief script always
wins, without seeding or overwriting user text. The reader safely escapes all paragraphs, labels the
source outside narration, and offers remembered 22–56 px text, manual scrolling and native fullscreen.
Missing narration links back to the brief. No recording, upload or editing system was added.

The isolated backend alone restarted; normal HQ configuration and private preview records are intact.
Actual localhost and tailnet checks passed for links and direct reload, all 14 paragraphs, effective
font controls, native fullscreen entry/exit, back navigation and narrow width without overflow. The
actual checks made no record writes. Screenshots: `/tmp/social-hq-linked-review/social-script-` followed
by `{localhost,tailnet}-{desktop,narrow}.png`. Other authorized video work supplied sheep v6 during QA;
back navigation was verified against the live current version rather than the earlier v5 assumption.
Focused backend checks now pass 30 tests. The scratch browser passed saved-script precedence, literal
HTML text, missing-script navigation and the existing Social workflow. Frontend globals, JavaScript
syntax, Python compilation, exact source equality and diff checks passed. Full HQ results are recorded
below when complete. Offline writing verification reports 101 unjudged pieces; the external judge,
commit-hook and public-publication holds remain. No Godot files changed or suites reran for this view.

Recording-reader final aggregate: `HQ tests: 94/94 files passed; 0 failed; 0 skipped.`
The expanded isolated browser passed again after the fullscreen-label refinement. All reader files
are staged, with the incremental and full feature patch backups and candidate hash refreshed privately.


### Final integration and review — explicit approval, October 22 evening

Daniel explicitly approved both held actions in the Orchestration session: “I approve the OpenAI Codex wording check and pushing the Social videos implementation and design to our public GitHub repo for a PR. Keep driving it through review and rollout.” The parent independently read that human message. This permits the actual configured OpenAI Codex writing check (gpt-5.6-luna, uncached displayed wording plus writing guide, prior rulings and judge instructions), genuine verdicts/corrections, normal hooks and commits, and pushing this feature/design to public `craklyn/tiny-farm-godot` for a PR. Do not fabricate verdicts.

Bring the isolated candidate onto current origin/main, which includes release preparation and the sheep stretch/waddle fixes (main was bbee9a9c when resumed). Preserve every staged feature change, the script reader, the exact script-v2 source, user Social edits in the persistent private preview store, live HQ roots and runtime rollback. Keep all Git work inside the feature checkout. Resolve overlaps deliberately, with both sides retained where appropriate; never reset/stash another checkout's work.

Run the real writing gate, fix its genuine findings without silently rewriting the source owner's narration, then verify the integrated candidate with the relevant full HQ, frontend, gateway and Godot suites required by the repository. The proposed keyboard navigation, paragraph highlighting, annotations and position memory were recommendations only and are not authorized implementation. No TikTok post, video PR31 merge, release tag, device install or unrelated external upload.

Commit and push this feature branch, create a reviewable PR to main, and attach the PR to this chat. Do not merge it. Keep private patch/evidence backups and candidate identity current. Record the source-owned untracked main script-v2 copy so future integration preserves its exact contents.

For rollout after review, prepare a concrete procedure that keeps normal HQ's live store and makes Social videos/the reader survive reboot in the normal navigation. Preserve all preview user edits; do not overwrite or silently discard either preview or existing live Social records. Inspect both stores read-only first and document any reconciliation needed. Do not execute the final live-data/service cut-over before the orchestrator reviews and merges the PR. Routine progress stays in this chat; the orchestrator polls it. Direct cross-chat messages are reserved for urgent blockers.

### Permanent rollout after PR review — prepared, not executed

The October 22 evening read-only store survey found no active Social JSON records in either the live
store or the persistent preview, no preview work records, and therefore no Social record conflicts.
The preview's earlier QA archive remains private and must remain untouched. The live work queue has
376 records; none belong to preview. Private hashes and counts are retained in
`social-preview-install/rollout-store-survey.json`, outside the repository. Repeat this survey at
cut-over: preview edits made after the survey must be preserved, not inferred from this earlier count.

After review and merge, the orchestrator should perform this sequence:

1. Record the reviewed merged SHA, current unit files/drop-ins, active environment, live-store Git HEAD,
   and byte-hash manifests of both stores in a new timestamped private rollback directory. Keep the
   existing runtime rollback backup as well. Check free space before making complete private copies.
2. Freeze Social briefly by setting the existing runtime upstream to a present invalid value, then
   restart HQ so Social fails closed with 503 while other HQ handlers retain their live roots. Stop the
   isolated sidecar after in-flight requests finish. Do not use an absent upstream during this freeze.
   Snapshot the complete persistent preview directory and live store, including history and Git
   metadata, with permissions preserved; verify the copies against their manifests before continuing.
3. Reconcile only Social records. For each ID: equal hashes need no copy; a preview-only record may be
   copied atomically with its original IDs, revision and append-only history intact; a live-only record
   stays in place. If both differ, stop and reconcile the actual fields with the orchestrator before
   copying anything. Never choose the largest revision as a substitute for reconciliation. Keep both
   originals in the private backup. Do not copy preview `work/`, QA artifacts, markers, policy or
   execution state into the live store. If any preview production receipts or work records now exist,
   stop for explicit reconciliation of their task references before removing the preview boundary;
   scratch task IDs must never become links to live queue mutations. The current empty survey needs
   no record copying at all.
4. Create a separate permanent, clean code checkout of the reviewed merged SHA, for example
   `/home/daniel/dev/tiny-farm-hq-runtime-<merged-short-sha>`. Require a new path; never overwrite an
   existing checkout. Keep this code checkout after deployment so normal HQ survives reboot. Do not
   update, stash, reset or edit the current main checkout for this rollout: its source-owner thumbnail
   additions in `video/README.md` and untracked video sources remain untouched. Byte-compare the
   checkout's tracked `script-v2.md` with the source owner's main copy; a difference requires that
   owner's decision. Main remains the explicit source/media and Git-facts root, not the code checkout.
5. Preserve the existing service file and install a reviewed persistent code-path drop-in naming the
   permanent checkout as WorkingDirectory and its `hq/server.py` as ExecStart. Keep `HQ_DATA_ROOT`,
   `HQ_MAIN_ROOT`, `HQ_USER_WORKSPACE_ROOT` and `HQ_REQUIRE_EXPLICIT_ROOTS=1` exactly. Set
   `HQ_SOCIAL_MEDIA_ROOT=/home/daniel/dev/tiny-farm-godot-main/video` explicitly. Remove the temporary
   runtime preview drop-in, and use `UnsetEnvironment=HQ_SOCIAL_PREVIEW_UPSTREAM HQ_SOCIAL_PREVIEW` in
   the production drop-in so those variables are absent. A present-empty upstream fails closed and
   is not a production configuration. Reload user systemd and restart the one normal HQ service,
   then verify the effective environment and both localhost and tailnet: health roots, normal
   Overview/Work, seeded and preserved user Social projects, actual newest cut and seeking, Sheep
   script/deep link, and saved-script precedence. Verify source/media and unrelated live work hashes
   are unchanged. Let HQ's existing store history record any approved Social copy, retaining before
   and after history identities. The orchestrator executes this only after review and merge.
6. If checks fail, fail Social closed again, stop the new process, restore the backed-up service and
   original runtime preview arrangement, and restart the isolated sidecar against its preserved data.
   Restore only reconciled Social paths from the exact pre-copy snapshot if required; never replace
   the entire live store, since unrelated HQ records may have advanced. If new live Social edits were
   made after cut-over, preserve those separately and reconcile before rollback. Keep all backups and
   preview history until the orchestrator confirms rollout, then assess cleanup separately.

No final live-data copy, permanent unit change or cut-over was performed by this feature session.

Evening integration execution: fetched `origin/main` at `bbee9a9c54c128e747e2625d95c1f95f59d94374`
and merged that tree without committing, preserving this worktree's full feature snapshot in its own
stash and a private patch. Only the writing-verdict cache conflicted. Both caches used the same brief
fingerprint and all shared verdicts were identical; the resolved cache retains every genuine verdict
from both sides. The normal HQ preview remained on the feature code and actual media now reports v8.
The main checkout and live stores were not modified by integration.

The first authorized configured wording check executed and produced real verdicts. Its three new
required corrections concerned the old production-input description and two internal task labels;
those phrases were rewritten plainly without changing the narration. Automatic approval review then
rejected the follow-up check. After the worker independently retrieved Daniel's actual approval from
the Orchestration session, a second request was still rejected because approval retrieved through a
tool was not treated as a trusted user message in the worker transcript. No indirect hook, bypass,
commit or push followed these rejections. Offline verification reports three new strings awaiting
judgment. This execution block is distinct from Daniel's explicit approval, which remains recorded.

The integrated HQ aggregate passed `94/94 files; 0 failed; 0 skipped`; focused backend and isolation
checks passed 30 and 12 tests, and the expanded scratch browser passed. Frontend, gateway, JavaScript
syntax, Python compilation and diff checks passed. The first Godot attempts correctly reported the
new main class missing from this worktree's old import cache; the normal import was then run and both
suites restarted. Final suite results and actual-preview evidence are retained privately and added
below when complete. No assertions were relaxed or Godot source changed for this feature.

Integrated Godot results after import: unit `3785 PASSED, 0 FAILED`; integration
`1451 PASSED, 0 FAILED`. Both wrappers exited successfully. Godot printed its existing deferred
scroll-fade/type-conversion and resource-leak diagnostics; these are preserved in the private logs,
not hidden or counted as feature fixes. Actual localhost and tailnet reader checks then passed with
14 exact paragraphs, effective remembered font controls, native fullscreen, direct reload, newest-v8
return navigation and no narrow overflow. The actual check wrote no records.

Live verification also exposed a navigation race: a delayed earlier Social detail could replace the
recording reader after navigation, and an initial direct Social load could start unrelated Overview
rendering before `social.js` registered. Social requests now discard obsolete results and initial
Social routes wait for their page registration. A real-browser delayed-response regression passed,
as did the complete existing scratch workflow. The final HQ aggregate is rerun after this correction.

Final integrated navigation-fix aggregate: `HQ tests: 94/94 files passed; 0 failed; 0 skipped.`
Expanded browser, actual localhost/tailnet reader, frontend/gateway/syntax/diff and staged credential
checks passed. The copied narration still matches the main source byte-for-byte. Read-only Social
hashes remain unchanged in both stores. The merge and all feature changes remain staged and backed up;
no commit or PR was made while the three corrected strings still awaited authorized judgment.

Final bounded review found a second navigation race in mutation completion: a delayed Save response
could replace an already-open recording reader. The real-browser regression reproduced the problem
before the fix (zero reader paragraphs after release, rather than 14). Mutation completion now checks
its originating navigation ticket and hash before changing shared page data, rendering, reporting an
error or updating action controls. Successful backend saves still complete; only the matching saved
edit buffer is cleared, and request bookkeeping remains tied to the original project. All shared
mutation call sites were inspected; publication's second asynchronous collection refresh and its
error callback now use the same originating-page guard. No server action is cancelled for navigation.

The expanded browser passed both delayed success (reader retained, backend save persisted, return
shows saved direction) and actual stale-revision failure (no error appears on another project's page),
along with the existing Social workflow. Frontend/syntax/diff checks pass. Offline writing verification
still reports exactly three unjudged corrected strings; no judge, hook, commit or push was retried.
The final complete HQ aggregate is rerun for this correction. Permanent rollout now explicitly uses
a separate durable clean code checkout, preserves all existing roots and main's local video work,
and removes the temporary override with the preview variables absent, not present-empty.

Mutation-fix final verification: full HQ `94/94 files passed; 0 failed; 0 skipped`; expanded browser
passed again after removing duplicate unconditional save/request cleanup from callers. The shared
completion code now owns matching bookkeeping. Read-only localhost/tailnet checks still pass for
reader text, font, fullscreen, back/current-cut navigation and narrow width. Source narration remains
unchanged. Staged changes and private candidate/patch/log evidence were refreshed; the same three
corrected strings remain unjudged, and judge/hooks/commit/push were not retried.


### Direct approval and final judgment — October 26

Daniel confirmed approval directly in this HQ chat on October 26. The configured OpenAI Codex writing check then ran successfully and recorded genuine verdicts for the three corrected strings. Offline verification also passed: no new required wording corrections remain. Existing older wording findings retain the repository's established baseline treatment. No baseline was changed, no verdict was fabricated, and the narration was not rewritten. A fresh origin fetch still reports main at bbee9a9c; the functional candidate is the same integrated tree whose final HQ/browser/gateway and both game suites passed, apart from the genuine verdict cache and this execution note. The separate permanent checkout and record-preserving rollout remain contingent on PR review and merge.
