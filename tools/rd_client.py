#!/usr/bin/env python3
# Vendored from the retro-diffusion-pixel-art skill
# (~/.claude/skills/retro-diffusion-pixel-art/scripts/rd_client.py, 2026-09-29) so the
# work queue's drain (hq/art_requests.py) can import it. Local change: find_key(), which
# returns None instead of exiting when no key is found. Keep the two copies in step.
"""Retro Diffusion API client: credits, free cost checks, generation with retry.

The API key is read from a project-local .env (never printed, never sent anywhere
but api.retrodiffusion.ai).

    python3 rd_client.py credits
    python3 rd_client.py cost params.json
    python3 rd_client.py generate NAME params.json [--out DIR]
    python3 rd_client.py batch batch.json [--out DIR]

params.json is the request body, with one convenience: "palette_hex": ["#rrggbb", ...]
is converted to the base64 "input_palette" the API expects.
batch.json is a list of [name, params] pairs.
"""
import argparse
import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.retrodiffusion.ai/v1"
ENV_VAR = "RETRODIFFUSION_API_KEY"


def find_key(*paths):
    """The key from the environment or the first of these .env files that has it, or None."""
    if os.environ.get(ENV_VAR):
        return os.environ[ENV_VAR]
    for path in paths:
        if path and os.path.isfile(path):
            with open(path) as fh:
                for line in fh:
                    if line.startswith(ENV_VAR + "="):
                        return line.split("=", 1)[1].strip() or None
    return None


def load_key(explicit_path=None):
    """Find the key in the environment or a project .env. Never returns it to stdout."""
    key = find_key(explicit_path, ".env", os.path.join(os.getcwd(), ".env"))
    if key:
        return key
    sys.exit(
        f"{ENV_VAR} not found. Put it in the project's .env (gitignored first) "
        f"or export it in the environment."
    )


def palette_b64(hex_colors):
    """Build the 1xN PNG the API takes as input_palette."""
    from PIL import Image

    im = Image.new("RGB", (len(hex_colors), 1))
    for i, h in enumerate(hex_colors):
        h = h.lstrip("#")
        im.putpixel((i, 0), tuple(int(h[j:j + 2], 16) for j in (0, 2, 4)))
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode()


def _prepare(params):
    params = dict(params)
    if "palette_hex" in params:
        params["input_palette"] = palette_b64(params.pop("palette_hex"))
    return params


def _request(method, path, key, body=None, timeout=900):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"X-RD-Token": key, "Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def credits(key):
    return _request("GET", "/inferences/credits", key, timeout=30)


def cost(key, params):
    body = dict(_prepare(params))
    body["check_cost"] = True
    res = _request("POST", "/inferences", key, body, timeout=60)
    res.pop("output_images", None)
    res.pop("base64_images", None)
    return res


def generate(key, name, params, out_dir, tries=4, timeout=900):
    """Generate and save. Returns the response metadata, or None if it never succeeded.
    `timeout` bounds each request; `tries` is how many requests an HTTP error may use."""
    body = _prepare(params)
    res = None
    for attempt in range(1, tries + 1):
        try:
            res = _request("POST", "/inferences", key, body, timeout=timeout)
            break
        except urllib.error.HTTPError as err:
            detail = err.read().decode()[:200]
            print(f"  {name}: HTTP {err.code} attempt {attempt}/{tries} {detail}", flush=True)
            if attempt == tries:
                return None
            time.sleep(8 * attempt)  # transient inference_failed clears on retry
    os.makedirs(out_dir, exist_ok=True)
    images = res.get("output_images") or res.get("base64_images") or []
    meta = {k: v for k, v in res.items() if k not in ("output_images", "base64_images")}
    with open(os.path.join(out_dir, f"{name}_meta.json"), "w") as fh:
        json.dump(meta, fh, indent=2)
    if not images:
        # Charged but nothing saved - always surface this loudly.
        print(f"  {name}: WARNING charged but no image payload; keys={list(res)}", flush=True)
    for i, b64 in enumerate(images):
        path = os.path.join(out_dir, f"{name}_{i}.png")
        with open(path, "wb") as fh:
            fh.write(base64.b64decode(b64))
        print(f"  {name}: saved {path}", flush=True)
    print(
        f"  {name}: cost={meta.get('balance_cost')} remaining={meta.get('remaining_balance')}",
        flush=True,
    )
    return meta


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["credits", "cost", "generate", "batch"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--out", default="./raw", help="directory for generated PNGs")
    ap.add_argument("--env", help="path to the .env holding the key")
    opts = ap.parse_args()
    key = load_key(opts.env)

    if opts.command == "credits":
        print(json.dumps(credits(key)))
    elif opts.command == "cost":
        print(json.dumps(cost(key, json.load(open(opts.args[0]))), indent=2))
    elif opts.command == "generate":
        name, params_file = opts.args[0], opts.args[1]
        generate(key, name, json.load(open(params_file)), opts.out)
    elif opts.command == "batch":
        jobs = json.load(open(opts.args[0]))
        total = 0.0
        for name, params in jobs:
            meta = generate(key, name, params, opts.out)
            if meta:
                total += meta.get("balance_cost", 0) or 0
            time.sleep(1)
        print(f"batch done, spent ${total:.3f}")


if __name__ == "__main__":
    main()
