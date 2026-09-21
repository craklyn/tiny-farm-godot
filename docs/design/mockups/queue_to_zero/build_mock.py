#!/usr/bin/env python3
"""Render the proposed queue reader as a static page from today's real cards.

A design mock, not the Work page: it applies the arrival policy and the spawn
policy in docs/QUEUE_TO_ZERO.md to hq/data/work/*.json and the open decision
cards, and draws what Daniel would see afterwards — the shape band, the
question list grouped by subject, and the briefing pane for one item. The
"Talk" button runs the thirty-second hand-back on a real timer so the
behaviour can be judged, but nothing here writes anywhere.

    python3 docs/design/mockups/queue_to_zero/build_mock.py
    -> docs/design/mockups/queue_to_zero/queue_reader.html
"""
import glob
import html
import json
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
WORK = os.path.join(ROOT, "hq", "data", "work")
DECISIONS = os.path.join(ROOT, "hq", "data", "decisions")
RULINGS = os.path.join(ROOT, "hq", "data", "rulings")
ORG = os.path.join(ROOT, "hq", "data", "org.json")
OUT = os.path.join(os.path.dirname(__file__), "queue_reader.html")


def load_dir(path):
    out = []
    for f in sorted(glob.glob(os.path.join(path, "*.json"))):
        try:
            out.append(json.load(open(f)))
        except ValueError:
            pass
    return out


def people():
    org = json.load(open(ORG))
    names = {}
    for e in org.get("employees", []):
        names[e["id"]] = e.get("name", e["id"]).split()[0]
    names["vp-engineering"] = "Elena"
    return names


# --- the arrival policy, applied to a finished card ---------------------------
# Mirrors docs/QUEUE_TO_ZERO.md §4. Returns (bucket, reason). Buckets:
#   his      — reaches Daniel (a question with a recommendation)
#   landed   — lands on its own, reported in the digest
#   studio   — goes back to the studio (verification, a revise round, or closing
#              a card whose work is already on main)


def green(card):
    s = card.get("suites")
    return isinstance(s, dict) and bool(s) and all(
        (v.get("ok") if isinstance(v, dict) else v) for v in s.values())


def classify(card):
    tier = card.get("tier", 2)
    fus = card.get("follow_ups") or []
    max_fu = max([f.get("tier", 1) for f in fus], default=0)
    check = card.get("check") or {}
    if card.get("decision"):
        return "studio", "filed off a decision already ruled and built; the card outlived its question"
    if card.get("source") == "chief-of-staff" and card.get("created", "")[:10] == "2026-09-10":
        return "studio", "the work is on main since 10–11 September; the card was never closed"
    if tier == 2:
        return "his", "hard to walk back, or a matter of taste"
    if tier == 0 and max_fu == 2:
        return "his", "the answer recommends something hard to walk back"
    if tier == 0:
        return "landed", "a reading; what follows from it is all revertable"
    if check.get("verdict") == "fail":
        return "studio", "the checker found it not done; the owner revises"
    if green(card) and max_fu <= 1:
        return "landed", "revertable, and the suites are green on record"
    if green(card) and max_fu == 2:
        return "his", "revertable work, but one thing it proposes is not"
    if card.get("diff"):
        return "studio", "revertable, but the suites were never run on a clean checkout"
    return "studio", "a write-up with no diff; verified by the drain before it lands"


# --- subject groups for what remains ----------------------------------------
THEMES = [
    ("How the game opens", ["Q-103", "Q-104", "w449aff92129", "w4b54fa114f0"]),
    ("What a harvest is worth", ["Q-113", "wa8ea2ed3df8"]),
    ("The home's rooms", ["Q-109"]),
    ("The seeder robot's animation", ["wr17889769879f89", "wr1788991284fa19"]),
    ("Walking through a door", ["w2b7e51c9d0af"]),
    ("The store page", ["wadf051cd6c7"]),
    ("HQ itself", ["w3e5997f5065"]),
]
DUPLICATE_OF = {"wr1788991284fa19": "wr17889769879f89"}


def md_plain(s, n=None):
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s or "")
    s = re.sub(r"`(.+?)`", r"\1", s)
    s = s.replace("\n\n", " ").replace("\n", " ").strip()
    return s if n is None else s[:n]


def question_for(card, names):
    rec = card.get("recommend") or {}
    if rec.get("question"):
        return rec["question"], rec.get("answer", ""), rec.get("why", ""), rec.get("instead", "")
    owner = names.get(card.get("owner"), card.get("owner"))
    return (f"{owner} built “{card['title']}”. Does it stand?",
            "It does what was asked." if card.get("diff") else "",
            "", "")


def decision_item(d, ruling):
    opts = d.get("options") or []
    rec = next((o for o in opts if o.get("recommended") or "(Recommended)" in o.get("label", "")), None)
    turns = len((ruling or {}).get("earlier") or []) + len(d.get("replies") or [])
    return {
        "id": d["id"], "kind": "pick", "title": d.get("title", d["id"]),
        # The card's question field is the whole setup; the one-line question the
        # reader shows is the title, and the setup is the first piece of evidence.
        "question": d.get("title", d["id"]),
        "answer": (rec or {}).get("label", "").replace(" (Recommended)", ""),
        "why": md_plain((rec or {}).get("detail", ""), 500),
        "options": [{"label": o.get("label", ""), "detail": md_plain(o.get("detail", ""))} for o in opts],
        "yes_causes": "Records your pick; the seat that opened the card works it into the design that day.",
        "walk_back": "A ruling can be changed until it is worked in; after that it is one more ruling.",
        "evidence": [{"label": "How this started", "text": md_plain(d.get("question", ""))}] +
                    [{"label": "Why now", "text": md_plain(d.get("why_now", ""))}] +
                    [{"label": a.get("caption") or a.get("label") or a.get("type", "attachment"), "text": a.get("src") or a.get("path") or ""}
                     for a in (d.get("attachments") or [])],
        "conversation": [{"who": "you", "text": e.get("judgment") or e.get("option_label") or "", "at": e.get("ruled_at", "")}
                         for e in ((ruling or {}).get("earlier") or [])] +
                        [{"who": r.get("by", "the studio"), "text": md_plain(r.get("text", ""), 600), "at": r.get("at", "")}
                         for r in (d.get("replies") or [])],
        "owner": "the seat that opened the card", "seconds": 30 if rec else 60, "turns": turns,
        "source": f"decision card {d['id']}",
    }


def work_item(card, names, bucket_reason):
    q, a, why, instead = question_for(card, names)
    fus = card.get("follow_ups") or []
    check = card.get("check") or {}
    suites = card.get("suites") or {}
    kind = "pick" if a else "read"
    ev = []
    if card.get("result"):
        ev.append({"label": "What came back", "text": md_plain(card["result"])})
    if card.get("diff"):
        ev.append({"label": "Files changed", "text": md_plain(card.get("diff") if isinstance(card.get("diff"), str) else json.dumps(card.get("diff")), 600)})
    if suites:
        ev.append({"label": "Test suites", "text": ", ".join(f"{k}: {'green' if (v.get('ok') if isinstance(v, dict) else v) else 'RED'}" for k, v in suites.items())})
    if check:
        ev.append({"label": f"Checker: {check.get('verdict', '')}", "text": md_plain(check.get("summary", ""), 500)})
    ev.append({"label": f"The brief written for {names.get(card.get('owner'), card.get('owner'))}", "text": md_plain(card.get("ask", ""))})
    t2 = [f for f in fus if f.get("tier") == 2]
    causes = []
    if fus:
        causes.append((f"{len(fus)} pieces of work start: " if len(fus) > 1 else "One piece of work starts: ") + "; ".join(
            f"{f['title']} ({names.get(f.get('owner'), f.get('owner') or card['owner'])})" for f in fus))
    if t2:
        causes.append(f"{len(t2)} of them would come back to you as a question, because they are hard to walk back.")
    if not fus:
        causes.append("It closes. Nothing else starts.")
    return {
        "id": card["id"], "kind": kind, "title": card["title"], "question": q, "answer": a, "why": why,
        "instead": instead, "options": [],
        "yes_causes": " ".join(causes),
        "walk_back": ("One git revert." if card.get("diff") else "Nothing to walk back; it is a reading.") if card.get("tier", 2) < 2
        else "This is the reason it is in front of you: " + bucket_reason + ".",
        "evidence": ev,
        "conversation": [{"who": "you" if m.get("role") == "daniel" else names.get(m.get("role"), m.get("role")),
                          "text": md_plain(m.get("text", ""), 600), "at": m.get("at", "")} for m in (card.get("conversation") or [])],
        "owner": names.get(card.get("owner"), card.get("owner")), "seconds": 30 if kind == "pick" else 120,
        "turns": len(card.get("conversation") or []), "source": f"work card {card['id']}",
        "follow_ups": [{"title": f["title"], "owner": names.get(f.get("owner"), f.get("owner")), "tier": f.get("tier", 1)} for f in fus],
    }


def main():
    names = people()
    cards = [c for c in load_dir(WORK) if c.get("state") == "for_review"]
    decisions = {d["id"]: d for d in load_dir(DECISIONS)}
    rulings = {r["id"]: r for r in load_dir(RULINGS)}
    # Open means nobody has ruled: no option picked in a ruling file, no ruling
    # written onto the card itself, and no comment of his still waiting on the
    # studio's answer (that card is the studio's move, not his).
    def is_open(i, d):
        r = rulings.get(i, {})
        if r.get("option") or d.get("ruled"):
            return False
        return not (r.get("judgment") and r.get("status") == "pending_integration")
    open_decisions = [d for i, d in decisions.items() if is_open(i, d)]
    answered = [d for i, d in decisions.items() if not is_open(i, d) and not d.get("ruled")
                and rulings.get(i, {}).get("judgment") and rulings.get(i, {}).get("status") == "pending_integration"]

    his, landed, studio = [], [], []
    for c in cards:
        b, reason = classify(c)
        {"his": his, "landed": landed, "studio": studio}[b].append((c, reason))

    items = {}
    for c, reason in his:
        if c["id"] in DUPLICATE_OF:
            continue
        items[c["id"]] = work_item(c, names, reason)
    for d in open_decisions:
        items[d["id"]] = decision_item(d, rulings.get(d["id"]))

    themes = []
    placed = set()
    for name, ids in THEMES:
        rows = [items[i] for i in ids if i in items]
        placed.update(i for i in ids if i in items)
        if rows:
            themes.append({"name": name, "items": rows})
    rest = [it for i, it in items.items() if i not in placed]
    if rest:
        themes.append({"name": "Everything else", "items": rest})

    digest = [{"title": c["title"], "owner": names.get(c["owner"], c["owner"]), "reason": r,
               "follow_ups": len(c.get("follow_ups") or [])} for c, r in landed]
    back = [{"title": c["title"], "owner": names.get(c["owner"], c["owner"]), "reason": r} for c, r in studio]
    back += [{"title": d.get("title", d["id"]), "owner": "the seat that opened the card",
              "reason": "you answered with a comment; the studio owes you the next word"} for d in answered]

    n_items = sum(len(t["items"]) for t in themes)
    picks = sum(1 for t in themes for i in t["items"] if i["kind"] == "pick")
    reads = n_items - picks
    minutes = round(sum(i["seconds"] for t in themes for i in t["items"]) / 60)
    dup_note = len([c for c, _ in his if c["id"] in DUPLICATE_OF])

    data = {"themes": themes, "digest": digest, "back": back, "n": n_items, "picks": picks,
            "reads": reads, "minutes": minutes, "before": len(cards) + len(open_decisions),
            "dups": dup_note, "follow_ups_before": sum(len(c.get("follow_ups") or []) for c in cards)}
    page = TEMPLATE.replace("__DATA__", json.dumps(data).replace("</", "<\\/"))
    open(OUT, "w").write(page)
    print(f"wrote {os.path.relpath(OUT, ROOT)}: {n_items} questions for him ({picks} picks, {reads} reads, ~{minutes} min); "
          f"{len(digest)} land on their own; {len(back)} go back to the studio; {len(cards) + len(open_decisions)} before")


TEMPLATE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Your queue — reader mock</title>
<style>
:root{--bg:#f6f4ee;--pane:#fffdf8;--ink:#1f1c17;--mute:#6b665c;--line:#e2ddd2;--accent:#2f6f4f;--accent-ink:#fff;--warn:#a05a1c;--you:#e9f0ff;--sel:#efe9dc;--chip:#ece7db}
@media (prefers-color-scheme: dark){:root{--bg:#171512;--pane:#1f1c18;--ink:#ece7dc;--mute:#a39c8e;--line:#332e27;--accent:#69b58c;--accent-ink:#0f1a14;--warn:#e0a060;--you:#25304a;--sel:#2a2620;--chip:#2c2822}}
*{box-sizing:border-box}html,body{margin:0;height:100%}body{background:var(--bg);color:var(--ink);font:15px/1.45 system-ui,sans-serif}
.app{display:grid;grid-template-columns:minmax(360px,44%) 1fr;height:100vh}
.list{overflow:auto;border-right:1px solid var(--line);padding:18px 18px 40px}
.pane{overflow:auto;padding:22px 28px 60px;background:var(--pane)}
h1{font-size:20px;margin:0 0 6px}h2{font-size:13px;letter-spacing:.04em;text-transform:uppercase;color:var(--mute);margin:22px 0 8px}
.band{border:1px solid var(--line);border-radius:10px;padding:12px 14px;background:var(--pane)}
.band b{font-size:17px}.band p{margin:6px 0 0;color:var(--mute)}
.strip{margin-top:10px;padding:10px 12px;border-radius:8px;background:var(--you);font-size:14px}
.strip:empty{display:none}
.row{display:grid;grid-template-columns:1fr auto;gap:8px;padding:10px 10px;border-radius:8px;cursor:pointer;border:1px solid transparent}
.row:hover{background:var(--sel)}.row.sel{background:var(--sel);border-color:var(--line)}
.row .q{font-weight:600}.row .r{color:var(--mute);font-size:14px;margin-top:2px}
.row .acts{display:flex;gap:6px;align-self:start}
button{font:inherit;padding:5px 10px;border-radius:7px;border:1px solid var(--line);background:var(--pane);color:var(--ink);cursor:pointer}
button.yes{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
.chip{display:inline-block;font-size:12px;padding:1px 7px;border-radius:999px;background:var(--chip);color:var(--mute);margin-left:6px;vertical-align:middle}
.pane .title{font-size:22px;font-weight:700;margin:0 0 4px}.pane .src{color:var(--mute);font-size:13px;margin-bottom:16px}
.sec{margin:16px 0}.sec h3{font-size:13px;text-transform:uppercase;letter-spacing:.04em;color:var(--mute);margin:0 0 6px}
.rec{border-left:4px solid var(--accent);padding:8px 12px;background:var(--bg);border-radius:0 8px 8px 0}
.rec b{display:block;font-size:16px}
details{border:1px solid var(--line);border-radius:8px;padding:8px 12px;margin:6px 0}summary{cursor:pointer;font-weight:600}
details p{white-space:pre-wrap;margin:8px 0 0;color:var(--ink)}
.opt{padding:6px 0;border-top:1px solid var(--line)}.opt b{display:block}
.convo .m{padding:8px 10px;border-radius:8px;margin:6px 0;background:var(--bg)}.convo .m.you{background:var(--you)}.convo .who{font-weight:600;font-size:13px;color:var(--mute)}
.talk{margin-top:14px}.talk textarea{width:100%;min-height:70px;font:inherit;padding:8px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--ink)}
.talk .st{margin-top:8px;color:var(--mute)}
.acts-big{display:flex;gap:8px;margin-top:18px}.acts-big button{padding:9px 16px;font-size:15px}
.digest li,.back li{margin:4px 0}.digest small,.back small{color:var(--mute)}
.done{padding:40px;color:var(--mute);text-align:center}
@media (max-width:900px){.app{grid-template-columns:1fr;height:auto}.list{border-right:0;border-bottom:1px solid var(--line)}}
</style></head><body>
<div class="app">
<div class="list">
  <h1>Your queue</h1>
  <div class="band" id="band"></div>
  <div class="strip" id="owed"></div>
  <div id="themes"></div>
  <h2>Landed without you</h2>
  <details><summary id="digest-sum"></summary><ul class="digest" id="digest"></ul></details>
  <h2>Back with the studio</h2>
  <details><summary id="back-sum"></summary><ul class="back" id="back"></ul></details>
</div>
<div class="pane" id="pane"><div class="done">Pick a question on the left.</div></div>
</div>
<script>
const DATA = __DATA__;
const owed = []; // items handed back: {item, since, who}
let sel = null;
const $ = s => document.querySelector(s);
const esc = s => (s||'').replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
function remaining(){ return DATA.themes.flatMap(t=>t.items).filter(i=>!i.done && !owed.some(o=>o.item===i)); }
function band(){
  const items = remaining();
  const picks = items.filter(i=>i.kind==='pick').length, reads = items.length-picks;
  const mins = Math.round(items.reduce((a,i)=>a+i.seconds,0)/60);
  if(!items.length){ $('#band').innerHTML = '<b>Nothing is waiting on you.</b><p>'+owed.length+' answer'+(owed.length===1?' is':'s are')+' on the way back; the rest of the studio is working.</p>'; return; }
  $('#band').innerHTML = '<b>'+items.length+' question'+(items.length===1?'':'s')+' · about '+mins+' minute'+(mins===1?'':'s')+' at your usual pace</b>'
    +'<p>'+picks+' '+(picks===1?'is a pick':'are picks')+' between prepared options, about 30 seconds each. '+reads+' need'+(reads===1?'s':'')+' you to read what came back, about two minutes each.</p>'
    +'<p>Yesterday this list had '+DATA.before+' items on it and accepting them would have filed '+DATA.follow_ups_before+' more.</p>';
}
function strip(){
  if(!owed.length){ $('#owed').innerHTML=''; return; }
  $('#owed').innerHTML = '<b>Coming back to you:</b> ' + owed.map(o=>o.who+' on “'+esc(o.item.title.slice(0,50))+'” <span class="chip" data-since="'+o.since+'">just now</span>').join(' · ');
}
function themes(){
  $('#themes').innerHTML = DATA.themes.map(t=>{
    const rows = t.items.filter(i=>!i.done && !owed.some(o=>o.item===i));
    if(!rows.length) return '';
    return '<h2>'+esc(t.name)+' <span class="chip">'+rows.length+'</span></h2>' + rows.map(i=>
      '<div class="row'+(sel===i?' sel':'')+'" data-id="'+i.id+'"><div><div class="q">'+esc(i.question)+'</div>'
      +(i.answer?'<div class="r">Recommended: '+esc(i.answer)+'</div>':'<div class="r">No recommendation yet — '+esc(i.owner)+' owes you one.</div>')
      +'</div><div class="acts">'+(i.answer?'<button class="yes" data-act="yes">Yes</button>':'')+'<button data-act="talk">Talk</button><span class="chip">'+(i.seconds<60?'30 s':'2 min')+'</span></div></div>').join('');
  }).join('') || '<div class="done">Nothing is waiting on you.</div>';
}
function pane(i){
  if(!i){ $('#pane').innerHTML='<div class="done">Pick a question on the left.</div>'; return; }
  const fu = (i.follow_ups||[]);
  $('#pane').innerHTML =
    '<div class="title">'+esc(i.question)+'</div><div class="src">'+esc(i.title)+' · '+esc(i.source)+' · '+esc(i.owner)+'</div>'
    +'<div class="sec"><h3>What I recommend</h3>'+(i.answer?'<div class="rec"><b>'+esc(i.answer)+'</b>'+esc(i.why)+(i.instead?'<div style="margin-top:6px;color:var(--mute)">Instead: '+esc(i.instead)+'</div>':'')+'</div>':'<div class="rec"><b>No recommendation on this one.</b>It should not have reached you without one; '+esc(i.owner)+' owes it.</div>')+'</div>'
    +(i.options.length?'<div class="sec"><h3>The options</h3>'+i.options.map(o=>'<div class="opt"><b>'+esc(o.label)+'</b>'+esc(o.detail)+'</div>').join('')+'</div>':'')
    +'<div class="sec"><h3>What yes starts</h3><p>'+esc(i.yes_causes)+'</p>'+(fu.length?'<ul>'+fu.map(f=>'<li>'+esc(f.title)+' — '+esc(f.owner)+(f.tier===2?' <span class="chip">would come back as a question</span>':' <span class="chip">lands on its own</span>')+'</li>').join('')+'</ul>':'')+'</div>'
    +'<div class="sec"><h3>What you would be walking back</h3><p>'+esc(i.walk_back)+'</p></div>'
    +(i.conversation.length?'<div class="sec convo"><h3>So far</h3>'+i.conversation.map(m=>'<div class="m'+(m.who==='you'?' you':'')+'"><div class="who">'+esc(m.who)+' · '+esc(m.at)+'</div>'+esc(m.text)+'</div>').join('')+'</div>':'')
    +'<div class="sec"><h3>The evidence</h3>'+i.evidence.map(e=>'<details><summary>'+esc(e.label)+'</summary><p>'+esc(e.text)+'</p></details>').join('')+'</div>'
    +'<div class="acts-big">'+(i.answer?'<button class="yes" data-act="yes">Yes — '+esc(i.answer.slice(0,40))+'</button>':'')+'<button data-act="no">No</button><button data-act="talk">Talk to '+esc(i.owner)+'</button></div>'
    +'<div class="talk" id="talk" hidden><textarea placeholder="Say what is wrong, or ask. '+esc(i.owner)+' answers here if it takes under thirty seconds, otherwise it comes back to you and you move on."></textarea><div><button data-act="send">Send</button></div><div class="st" id="talk-st"></div></div>';
}
function render(){ band(); strip(); themes(); }
function next(){ const r = remaining(); sel = r[0]||null; pane(sel); render(); }
document.addEventListener('click', e=>{
  const b = e.target.closest('button'); const row = e.target.closest('.row');
  const act = b && b.dataset.act;
  if(row && !act){ sel = DATA.themes.flatMap(t=>t.items).find(i=>i.id===row.dataset.id); pane(sel); render(); return; }
  if(!act) return;
  const i = row ? DATA.themes.flatMap(t=>t.items).find(x=>x.id===row.dataset.id) : sel;
  if(!i) return;
  if(act==='yes'||act==='no'){ i.done = act; next(); return; }
  if(act==='talk'){ sel=i; pane(i); render(); const t=$('#talk'); t.hidden=false; t.querySelector('textarea').focus(); return; }
  if(act==='send'){
    const st = $('#talk-st'); let left = 30; const who = i.owner;
    st.textContent = who+' is answering… 30 s';
    const tick = setInterval(()=>{ left--; if(left>0){ st.textContent = who+' is answering… '+left+' s'; return; }
      clearInterval(tick); owed.push({item:i, since:Date.now(), who});
      st.textContent = who+' needs longer than thirty seconds. This is back with the studio and will come back to you at the top of the list.';
      setTimeout(next, 1200);
    }, 1000);
  }
});
setInterval(()=>{ document.querySelectorAll('[data-since]').forEach(c=>{ const s=Math.round((Date.now()-c.dataset.since)/1000); c.textContent = s<60? s+' s ago' : Math.round(s/60)+' min ago'; }); }, 1000);
$('#digest-sum').textContent = DATA.digest.length+' pieces of finished work landed on their own since yesterday';
$('#digest').innerHTML = DATA.digest.map(d=>'<li>'+esc(d.title)+' — '+esc(d.owner)+' <small>· '+esc(d.reason)+(d.follow_ups?' · started '+d.follow_ups+' more':'')+'</small> <button>Undo</button></li>').join('');
$('#back-sum').textContent = DATA.back.length+' cards went back to the studio instead of to you';
$('#back').innerHTML = DATA.back.map(d=>'<li>'+esc(d.title)+' — '+esc(d.owner)+' <small>· '+esc(d.reason)+'</small></li>').join('');
next();
</script></body></html>
"""

if __name__ == "__main__":
    main()
