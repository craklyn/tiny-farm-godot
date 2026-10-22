# Sheep video v6 — later deliveries

Daniel asked for a new edit after the delivery audit showed that v5 used take 0045 throughout. His preference is to use the last delivery of a repeated line. He requested that the finished v6 be copied to his laptop.

The edit now uses take 0047 for the opening, the project description, wool growth, coats, doors, the sheep becoming unable to walk, grazing and the bird. The viewer's question and answer use the final repeat in 0046. Take 0045 supplies the unrepeated contentment and "things to do" lines and the concise final question.

Two deliberate exceptions within 0047: the doorway line uses the earlier correct description of the extra-full coat because the later repeat says "quarter full"; the coat list uses "coat" rather than the later expansion's "patch". The shearing aside and the bird restart are removed. The full source and output times are in delivery-selection-v6.json.

The voice gets a 70 Hz high-pass filter and is levelled before mixing. Music is reduced from v5's -24 dB to -30 dB and gameplay sound from -19 dB to -23 dB. These are modest changes to make speech clearer. They cannot establish that Daniel will prefer the recorded performance.

The picture keeps the gameplay-only layout, the wider sparkle orbit, the "Buddyo Vlogs" spelling, the stopped extreme sheep and the omission of the neck stretch. Captions and gameplay are retimed to the new words. Runtime: 35.702 seconds of narration plus the existing end card.

Reproduce with the PR 31 tools (c8fee07b):

    video/.venv/bin/python video/2026-10-14_tiktok_sheep/edit/render-v6.py --tools /path/to/PR31/video/tools

The timestamped caption file is local to this edit. It corrects automatic transcript timing errors without changing the original transcripts. The original takes and previous renders remain intact.

Verification: the finished 1080 × 1920, 29.97 fps file decodes all 1,136 frames without errors or detected black flashes. A contact sheet sampled once per second was visually checked. Caption bounds and ordering pass. A fresh local medium.en transcription of the assembled voice preserves the intended narration and has no repeated bird restart. The finished mix measures -14.4 LUFS integrated with a -1.4 dBFS true peak. Delivery quality still awaits Daniel's review.

Delivered October 22, 2026 through Tailscale file transfer to Catherine's MacBook Pro (100.67.207.62), after verifying it was online. The transfer command acknowledged success. SSH on port 22 had refused the connection, so this uses the same route as the earlier v5 delivery. No posting or merge approval has been given.
