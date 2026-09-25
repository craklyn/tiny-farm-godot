Engineering benchmark · Tiny Farm
# Independent tablet sim timing on 2026-09-24

| Date | Status | Last updated | Repo/location |
| --- | --- | --- | --- |
| 2026-09-24 | FINAL | 2026-09-24 | `docs/benchmarks/tablet-sim-independent-2026-09-24.md` |

## Background and question

This is an independent repeat of the eight-busy-machine tablet/desktop comparison that landed as commit `93bf394` and set `DEVICE_FACTOR=2.36` in `tools/benchmark_sim.gd`. The question is whether a separate session supports a materially different device slowdown. The primary measurement used 14 samples per device and is recorded on HQ work card `wfd1627b62ab2` and in `docs/DECISION_LOG.md`.

## Hardware and build

| Side | Conditions |
| --- | --- |
| Desktop | AMD Ryzen 7 PRO 6850H with Radeon Graphics; Linux; Godot 4.7.2.stable.official.ed1daf0bf; headless scene run |
| Tablet | Lenovo TB336FU; Android 16; Godot 4.7.2 debug APK launched as `com.daniel.tinyfarm.profile.sim` |
| Code | Base commit `306e4cba8a203ade91cdbd16ee59f92b2fd7eb47` plus a temporary shared `benchmark_fleet.gd` function copied without workload changes from `benchmark_sim.gd`; the same function ran on both devices |
| APK | SHA-256 `09b2b1cdfbed81f68780c17f076c3a5f384c4205a28d7831e9847d497af9340a`; `aapt dump badging` verified the separate package before install |

The real `com.daniel.tinyfarm` package remained installed. The temporary profile package was uninstalled after measurement. This run did not read or write the real game's saves.

## Method

Each sample reseeded to 1234, cleared the same meadow orbit, deployed eight circle bots, and timed only `world.advance_ticks(10000, gs)`. One warm-up was discarded. Five consecutive samples were taken on each device; the sample median is the comparison statistic. World generation and initialization were outside the timed interval. The Android profile used an isolated `/tmp` snapshot and its own debug APK; the desktop ran the same profile scene headlessly. The run's temporary harness was superseded by the profile scene in commit `93bf394` and is not needed to reproduce the primary result.

## Results — complete

| Timed sample | Desktop µs/tick | Tablet µs/tick |
| ---: | ---: | ---: |
| 1 | 118.379 | 267.690 |
| 2 | 118.058 | 264.910 |
| 3 | 123.879 | 262.342 |
| 4 | 123.894 | 262.737 |
| 5 | 120.544 | 262.373 |
| **Median** | **120.544** | **262.737** |

All samples reported eight machines moving. The desktop range was 5.836 µs/tick and the tablet range was 5.348 µs/tick. These are within-session spreads, not day-to-day uncertainty estimates. The raw output is preserved below.[^raw]

**Verdict:** This session's median ratio was 262.737 / 120.544 = **2.18×**. The primary 14-sample measurement was **2.36×**. Tablet medians differ by about 1%; desktop medians differ by about 9%. Thus the ratio difference comes mainly from desktop timing in these two sessions. This repeat does not establish that the tablet itself became faster, nor does it justify replacing the primary factor. The existing 2.36 remains the more conservative target.

## Conclusion and next step

Keep `DEVICE_FACTOR=2.36` from the primary measurement. If a tighter calibration matters, run paired desktop and tablet samples under controlled desktop load and repeat across days. The current factor already gives the benchmark a measured tablet basis; this additional run shows that desktop load can move the ratio.

## Raw profile output

```text
Desktop: PROFILE_SIM run=1 ticks=10000 busy=8 usec_per_tick=118.379
Desktop: PROFILE_SIM run=2 ticks=10000 busy=8 usec_per_tick=118.058
Desktop: PROFILE_SIM run=3 ticks=10000 busy=8 usec_per_tick=123.879
Desktop: PROFILE_SIM run=4 ticks=10000 busy=8 usec_per_tick=123.894
Desktop: PROFILE_SIM run=5 ticks=10000 busy=8 usec_per_tick=120.544
Desktop: PROFILE_SIM median_usec_per_tick=120.544 runs=5 os=Linux processor=AMD Ryzen 7 PRO 6850H with Radeon Graphics
Tablet: PROFILE_SIM run=1 ticks=10000 busy=8 usec_per_tick=267.690
Tablet: PROFILE_SIM run=2 ticks=10000 busy=8 usec_per_tick=264.910
Tablet: PROFILE_SIM run=3 ticks=10000 busy=8 usec_per_tick=262.342
Tablet: PROFILE_SIM run=4 ticks=10000 busy=8 usec_per_tick=262.737
Tablet: PROFILE_SIM run=5 ticks=10000 busy=8 usec_per_tick=262.373
Tablet: PROFILE_SIM median_usec_per_tick=262.737 runs=5 os=Android processor=
```

[^raw]: Timing source: `PROFILE_SIM` stdout on desktop and `godot` logcat from the tablet profile APK, reproduced above. The APK hash and command conditions identify the Android artifact.
