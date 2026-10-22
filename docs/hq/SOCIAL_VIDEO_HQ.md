# Social videos in Tiny Farm HQ

## Purpose and design rules

Daniel asked on 2026-10-22 for a place to manage, design and build social media content, beginning with the two published videos and the almost-finished sheep video. He explicitly wants the published work and the changing work to be different kinds of records.

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

Beside the player, show the editable content brief and review notes. Show the existing script and decisions in a folded source section as read-only source material. The brief is direction for the next production pass, not a silent rewrite of the recorded script.

“Send revision brief” saves a concrete production request containing the project, exact cut, open notes and saved brief into HQ's existing work system. Its existing intake assigns the chief of staff; include Jordan's production responsibility in the brief and label the result “Filed for routing to Jordan”. Link the returned work card and actual owner. Repeated submissions of the same request must not duplicate work.

“Approve this cut” records approval only for the current hash and only when the current cut has no unresolved review notes. Notes can be explicitly marked addressed; retain their record. Earlier-cut notes remain discoverable on that cut. A new cut does not inherit approval or silently resolve notes.

After approval, offer posting preparation: an editable post caption, the source comment/reply context, a download of that exact approved file, and “Record published post”. Recording publication requires a valid HTTPS post URL and the current approved render hash. This records an event; it does not upload or post. Snapshot the approved hash, caption and version. Later changes cannot alter that publication. Missing or modified files must never be served as the published copy.

### Published video

Lead with the posted version and a link to the actual post when recorded. If the movie or URL is unavailable, say so in place and keep the evidence and final version visible. Do not fall back to a newer cut.

Show the audience promise, the posting record, source comment, subsequent video links and audience responses. The creamery page links back to the feature tour and forward to the sheep response. A follow-up action carries the source video/comment into a new idea brief.

Allow adding the missing post URL/date as a new record without changing historical creative facts. Allow dated audience-response notes with an optional source link. Do not invent analytics or imply live account access. At this scale, a useful comment and the next experiment are more useful than an empty analytics chart.

### Planning and production

New ideas are real persisted projects, with safe generated identifiers. Reserve their working artifact location as `video/drafts/<generated-id>/`, with renders named `renders/<generated-id>_vN.mp4`. This is a planned working folder, separate from the recording-date folders of the three existing videos; creation of an idea need not create media files. Include that exact output path in every production brief and discover numerically versioned files there on refresh, so a newly planned video can receive its first real cut. Document this additional planning layout in `video/README.md`.

A saved brief can be sent into the existing production queue. The page must show the returned task, actual owner and honest request state. No renderer is offered until a complete reproducible recipe is available: the sheep folder currently lacks its composition EDL and captions despite containing v1–v5 renders.

Production briefs should include the video-editing workflow and source paths so an executing session can make the next cut. Every build must retain earlier renders, document the new inputs and return a version for review. A source comment is creative context, not permission to change the game design or publish publicly.

## Initial evidence

| Project | Initial record | Evidence |
|---|---|---|
| Feature tour | Published; v4 is the posted version; posting URL/date not yet recorded; final MP4 absent locally | Daniel's request; `video/2026-10-06_tiktok_feature-tour/decisions.md`, “v4” and “After v4” |
| Creamery | Published; v2 posted 2026-10-12; posting URL not yet recorded; final MP4 absent locally | `video/2026-10-12_tiktok_creamery/decisions.md`, “Posted” |
| Sheep | In production; available cuts v1–v5; current cut needs Daniel's review; no recorded approval/publication | Daniel's request; actual `renders/` files in the main checkout; `video/2026-10-14_tiktok_sheep/decisions.md` |

The sheep response came from A. A. Nahi's creamery comment, “Ar ethere sheep 🐑?”. The proposed delivery is a TikTok video reply; that remains a recommendation, not a settled instruction. Historical open questions inside published videos' decisions files are historical, not new blockers.

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
