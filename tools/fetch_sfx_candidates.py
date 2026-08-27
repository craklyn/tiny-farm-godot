#!/usr/bin/env python3
"""Fetch CC0-licensed sound candidates from Freesound for in-game auditioning.

Why: four synthesis attempts established that naive synthesis handles percussive
impacts and UI ticks well (till, click, cluck, squawk all passed a listen) and
reward foley badly — every pitched take landed somewhere in the arcade-reward
vocabulary. Harvest needs a real recording.

Licensing discipline (Q-7c): this refuses to keep anything that is not CC0, and
writes a provenance record for every file it does keep, so nothing enters the
repo without its source, author, and licence already written down. Freesound
licences are per-upload, so the filter is not trusted on its own — each result's
licence field is re-checked before the file is written.

Preview files (128kbps mp3) are used deliberately: a plain API key covers them,
they are the same CC0 work as the original, and they are more than adequate
downsampled to 22kHz mono. Originals would need an OAuth handshake.

    python3 tools/fetch_sfx_candidates.py harvest "pulling plant from soil"
    python3 tools/fetch_sfx_candidates.py --list
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://freesound.org/apiv2"
CC0_URL = "http://creativecommons.org/publicdomain/zero/1.0/"
CC0_FILTER = 'license:"Creative Commons 0"'
OUT_DIR = "assets/audio/sfx"
PROVENANCE = "assets/audio/sfx/CANDIDATES.json"
SR = 22050

# Queries per slot, tried in order until enough candidates are gathered.
# Freesound ANDs query terms strictly, so long natural-language phrases return
# nothing. Short terms work; "harvest" alone surfaces a Plant_Harvest series.
SEARCHES = {
    "harvest": ["harvest", "rustling grass", "bush cut"],
    "water": ["watering can", "water pour", "sprinkle"],
    "till": ["shovel dirt", "digging"],
}


def api_key():
    env = os.path.expanduser("~/dev/tiny-farm-godot/.env")
    if os.environ.get("FREESOUND_API_KEY"):
        return os.environ["FREESOUND_API_KEY"]
    if os.path.isfile(env):
        for line in open(env):
            if line.startswith("FREESOUND_API_KEY="):
                return line.split("=", 1)[1].strip()
    sys.exit("FREESOUND_API_KEY not found in the project .env")


def get(url, key, binary=False, timeout=60):
    req = urllib.request.Request(url, headers={"Authorization": f"Token {key}"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read() if binary else json.load(r)


def search(key, query, max_dur=3.0, limit=6):
    q = urllib.parse.urlencode({
        "query": query,
        "filter": f"{CC0_FILTER} duration:[0.1 TO {max_dur}]",
        "fields": "id,name,license,duration,username,previews,url",
        "sort": "score",
        "page_size": limit,
    })
    return get(f"{API}/search/text/?{q}", key).get("results", [])


MAX_DUR = 1.5  # a per-tile action wants a short sound; longer takes get trimmed


def convert(src, dst, gain_db=-1.0, max_dur=MAX_DUR):
    """Downmix to the project's format, trim leading silence, cap the length with
    a short fade so a cut pour does not end abruptly, and normalise."""
    fade_at = max(0.05, max_dur - 0.15)
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src,
        "-af", f"silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02,"
               f"afade=t=out:st={fade_at:.2f}:d=0.15,"
               f"loudnorm=I=-16:TP={gain_db}:LRA=11",
        "-t", str(max_dur),
        "-ar", str(SR), "-ac", "1", "-acodec", "pcm_s16le", dst,
    ], check=True)
    _assert_audible(src, dst, max_dur)


def _assert_audible(src, dst, max_dur):
    """A candidate that comes out silent must fail loudly rather than ship.

    silenceremove strips everything from a quiet source, which produced a
    zero-length file that reached the tablet as "does not make a sound".
    Retry once without the silence trim before giving up.
    """
    import wave
    def peak(path):
        with wave.open(path) as w:
            frames = w.getnframes()
            if frames == 0:
                return 0.0
            import array
            a = array.array("h")
            a.frombytes(w.readframes(frames))
            return max(abs(v) for v in a) / 32768.0
    if peak(dst) >= 0.02:
        return
    print(f"    (silent after trim; retrying without silenceremove)")
    fade_at = max(0.05, max_dur - 0.15)
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src,
        "-af", f"afade=t=out:st={fade_at:.2f}:d=0.15,loudnorm=I=-16:TP=-1.0:LRA=11",
        "-t", str(max_dur), "-ar", str(SR), "-ac", "1", "-acodec", "pcm_s16le", dst,
    ], check=True)
    if peak(dst) < 0.02:
        raise RuntimeError("still silent after retry")


def fetch_ids(slot, ids, key):
    """Fetch specific sounds by Freesound ID, for when a search has already been
    eyeballed and only certain results are worth auditioning."""
    record = json.load(open(PROVENANCE)) if os.path.isfile(PROVENANCE) else []
    seen = {r["freesound_id"] for r in record}
    kept = 0
    for sid in ids:
        if sid in seen:
            print(f"  skip #{sid}: already fetched")
            continue
        s = get(f"{API}/sounds/{sid}/?fields=id,name,license,duration,username,previews,url", key)
        if s.get("license", "").rstrip("/") != CC0_URL.rstrip("/"):
            print(f"  skip #{sid}: licence is {s.get('license')}")
            continue
        name = f"{slot}_cc0_{sid}"
        tmp, dst = f"/tmp/{name}.mp3", os.path.join(OUT_DIR, f"{name}.wav")
        try:
            open(tmp, "wb").write(get(s["previews"]["preview-hq-mp3"], key, binary=True))
            convert(tmp, dst)
        except Exception as exc:
            print(f"  skip #{sid}: {exc}")
            continue
        finally:
            if os.path.exists(tmp):
                os.remove(tmp)
        record.append({"slot": slot, "file": os.path.basename(dst), "freesound_id": s["id"],
                       "title": s["name"], "author": s["username"],
                       "license": "CC0 1.0 Universal (public domain dedication)",
                       "source": s.get("url", f"https://freesound.org/s/{sid}/"), "query": "by-id"})
        kept += 1
        print(f"  kept {name}.wav  (src {s['duration']:.2f}s -> capped {MAX_DUR}s, by {s['username']})")
    json.dump(record, open(PROVENANCE, "w"), indent=2)
    return kept


def fetch(slot, queries, key, want=3):
    os.makedirs(OUT_DIR, exist_ok=True)
    record = []
    if os.path.isfile(PROVENANCE):
        record = json.load(open(PROVENANCE))
    seen = {r["freesound_id"] for r in record}
    kept = 0
    for query in queries:
        if kept >= want:
            break
        try:
            results = search(key, query)
        except urllib.error.HTTPError as e:
            print(f"  search failed ({e.code}) for {query!r}")
            continue
        for s in results:
            if kept >= want or s["id"] in seen:
                continue
            # Never trust the filter alone — verify the licence on the result.
            if s.get("license", "").rstrip("/") != CC0_URL.rstrip("/"):
                print(f"  skip #{s['id']}: licence is {s.get('license')}")
                continue
            name = f"{slot}_cc0_{s['id']}"
            tmp = f"/tmp/{name}.mp3"
            dst = os.path.join(OUT_DIR, f"{name}.wav")
            try:
                open(tmp, "wb").write(get(s["previews"]["preview-hq-mp3"], key, binary=True))
                convert(tmp, dst)
            except Exception as exc:
                print(f"  skip #{s['id']}: {exc}")
                continue
            finally:
                if os.path.exists(tmp):
                    os.remove(tmp)
            record.append({
                "slot": slot,
                "file": os.path.basename(dst),
                "freesound_id": s["id"],
                "title": s["name"],
                "author": s["username"],
                "license": "CC0 1.0 Universal (public domain dedication)",
                "source": s.get("url", f"https://freesound.org/s/{s['id']}/"),
                "query": query,
            })
            seen.add(s["id"])
            kept += 1
            print(f"  kept {name}.wav  ({s['duration']:.2f}s, by {s['username']})")
    json.dump(record, open(PROVENANCE, "w"), indent=2)
    return kept


if __name__ == "__main__":
    if "--list" in sys.argv:
        if os.path.isfile(PROVENANCE):
            for r in json.load(open(PROVENANCE)):
                print(f"{r['file']:34s} #{r['freesound_id']:<9} {r['author']:<18} {r['title'][:40]}")
        sys.exit(0)
    k = api_key()
    if "--ids" in sys.argv:
        i = sys.argv.index("--ids")
        slot_name = sys.argv[1]
        ids = [int(x) for x in sys.argv[i + 1:]]
        print(f"fetching {len(ids)} sound(s) by id for {slot_name!r}...")
        print(f"{fetch_ids(slot_name, ids, k)} written; provenance in {PROVENANCE}")
        sys.exit(0)
    slot = sys.argv[1] if len(sys.argv) > 1 else "harvest"
    queries = sys.argv[2:] or SEARCHES.get(slot, [slot])
    print(f"searching CC0 for {slot!r}...")
    n = fetch(slot, queries, k)
    print(f"{n} candidate(s) written; provenance in {PROVENANCE}")
