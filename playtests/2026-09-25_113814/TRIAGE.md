# Manual triage, 2026-09-25 — replay MISMATCH, installed over deliberately

Checked under its exact recording build (a04429a, clean) with
`tools/verify_replay.gd`:

    MISMATCH: recomputation diverged from the recording.
    entry 653: recorded @58205 {actor=bot_mk3,seed_type=tomato,target=12,8,verb=plant},
               recomputed @58175 {actor=bot_mk3,target=10,9,verb=till}

The Mark III's recomputed brain chose differently from the live one — a
determinism break in the sim, not damage to the farm. The autosave on the
tablet is untouched by an install, and all three files are kept here.

`verification.sha256` beside this note is therefore a triage receipt, not a
passed verification: it lets the deploy install today's build (Daniel was
blocked on the Spiral Tower having no way in) without re-litigating this
session. The divergence is filed as its own follow-up.
