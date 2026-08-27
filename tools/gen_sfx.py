#!/usr/bin/env python3
"""Synthesise Tiny Farm's gameplay SFX from scratch.

Why: four shipped sounds (harvest, till, water, ui_click) had no recorded
provenance, which blocks the first public release (CREDITS.md). Generating them
here makes their origin unambiguous — this file is the source — and lets the mix
be re-tuned without hunting for sample packs.

Voicing follows docs/design/10 §"SFX: verb-driven foley": till = soft chunk,
water = sprinkle, harvest = pop + chime, UI = one soft tick. Kid constraints from
the same section: gentle attacks, no harsh stingers, comfortable at low volume.
Output matches the existing in-repo originals: 22050 Hz, mono, 16-bit.

    python3 tools/gen_sfx.py            # write assets/audio/sfx/*.wav
    python3 tools/gen_sfx.py --preview  # also render tools/sfx_preview.png
"""
import os
import struct
import sys
import wave

import numpy as np

SR = 22050
OUT_DIR = "assets/audio/sfx"
RNG = np.random.default_rng(20260827)  # fixed so regenerating is byte-stable


def env(n, attack, decay, curve=2.0):
    """Gentle attack / smooth decay envelope, both in samples."""
    a = np.linspace(0.0, 1.0, max(1, attack)) ** 0.6
    d = np.linspace(1.0, 0.0, max(1, n - len(a))) ** curve
    return np.concatenate([a, d])[:n]


def lowpass(x, cutoff):
    """One-pole lowpass; enough to take the edge off noise without a DSP dep."""
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    out = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        out[i] = acc
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def noise(n):
    return RNG.uniform(-1.0, 1.0, n)


def sine(freq, n, phase=0.0):
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * freq * t + phase)


def sweep(f0, f1, n):
    t = np.arange(n) / SR
    f = np.linspace(f0, f1, n)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def normalise(x, peak=0.72):
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * peak
    return x - np.mean(x)  # kill DC so quiet playback stays clean


def till():
    """Soft chunk: a hoe biting into earth — dull thump plus a scrape of grit."""
    n = int(0.20 * SR)
    thump = sine(96, n) * env(n, int(0.004 * SR), n, 3.2)
    body = lowpass(noise(n), 700) * env(n, int(0.003 * SR), n, 2.6)
    grit = highpass(lowpass(noise(n), 2400), 700) * env(n, int(0.002 * SR), n, 5.5) * 0.18
    return normalise(thump * 0.9 + body * 0.8 + grit, 0.66)


def water():
    """Sprinkle: a soft hiss with a handful of droplet ticks over the top."""
    n = int(0.34 * SR)
    hiss = highpass(lowpass(noise(n), 4200), 1100)
    shimmer = 0.6 + 0.4 * np.sin(2 * np.pi * 17 * np.arange(n) / SR)
    out = hiss * shimmer * env(n, int(0.02 * SR), n, 1.6) * 0.6
    for start, freq in ((0.03, 2100), (0.11, 2600), (0.19, 1900), (0.26, 2400)):
        s = int(start * SR)
        ln = int(0.035 * SR)
        drop = sine(freq, ln) * env(ln, int(0.001 * SR), ln, 6.0) * 0.28
        out[s:s + ln] += drop[:len(out) - s]
    return normalise(out, 0.6)


def harvest():
    """Pop plus a two-note chime — the phase-1 reward sound, so it may sparkle."""
    n = int(0.42 * SR)
    out = np.zeros(n)
    pn = int(0.06 * SR)
    out[:pn] += sweep(420, 900, pn) * env(pn, int(0.002 * SR), pn, 4.0) * 0.7
    for start, freq, amp in ((0.05, 880.0, 0.5), (0.13, 1318.5, 0.42)):
        s = int(start * SR)
        ln = n - s
        tone = sine(freq, ln) * 0.8 + sine(freq * 2, ln) * 0.2
        out[s:] += tone * env(ln, int(0.006 * SR), ln, 2.4) * amp
    return normalise(out, 0.68)


def ui_click():
    """One soft tick. Deliberately dull-edged: it fires on every single tap."""
    n = int(0.045 * SR)
    body = lowpass(noise(n), 2600) * env(n, int(0.002 * SR), n, 7.0)
    tone = sine(1250, n) * env(n, int(0.002 * SR), n, 8.0) * 0.5
    return normalise(body + tone, 0.42)


SOUNDS = {
    "till": till,
    "water": water,
    "harvest": harvest,
    "ui_click": ui_click,
}


def write_wav(path, samples):
    data = np.clip(samples, -1.0, 1.0)
    pcm = (data * 32767).astype(np.int16)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def preview(rendered, path="tools/sfx_preview.png"):
    """Waveform + spectral summary, so the sounds can be eyeballed as well as heard."""
    from PIL import Image, ImageDraw
    W, H = 720, 110
    sheet = Image.new("RGB", (W, H * len(rendered)), (28, 28, 36))
    d = ImageDraw.Draw(sheet)
    for i, (name, s) in enumerate(rendered.items()):
        y0 = i * H
        mid = y0 + H // 2
        d.line([(0, mid), (W, mid)], fill=(60, 60, 74))
        step = max(1, len(s) // W)
        for x in range(W):
            chunk = s[x * step:(x + 1) * step]
            if len(chunk) == 0:
                break
            hi = int(np.max(chunk) * (H // 2 - 12))
            lo = int(np.min(chunk) * (H // 2 - 12))
            d.line([(x, mid - hi), (x, mid - lo)], fill=(120, 200, 140))
        centroid = float(np.sum(np.abs(np.fft.rfft(s)) * np.fft.rfftfreq(len(s), 1 / SR))
                         / max(1e-9, np.sum(np.abs(np.fft.rfft(s)))))
        d.text((6, y0 + 6), f"{name}  {len(s)/SR:.2f}s  peak {np.max(np.abs(s)):.2f}"
                            f"  centroid {centroid:.0f}Hz", fill=(235, 235, 235))
    sheet.save(path)
    print("wrote", path)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    rendered = {}
    for name, fn in SOUNDS.items():
        s = fn()
        rendered[name] = s
        path = os.path.join(OUT_DIR, f"{name}.wav")
        write_wav(path, s)
        print(f"{name:10s} {len(s)/SR:.2f}s  peak {np.max(np.abs(s)):.2f}  -> {path}")
    if "--preview" in sys.argv:
        preview(rendered)
