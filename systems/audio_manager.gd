extends Node

var bgm_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var num_sfx_players = 8

const BGM_BASE_DB := -10.0
# P-15 p1 ("Duck the music... by about 6 dB for the length of a story night"):
# the amount `set_bgm_duck` pulls the music down by at full duck. The music
# has never been ducked anywhere before this — a plain night leaves it alone.
const BGM_DUCK_DB := 6.0

# A continuous bed — a sound that keeps looping rather than firing once — for
# a machine that acts the whole length of a story-night loop rather than on
# one frame of it: the seeder robot's treads while it drives. A dedicated
# player rather than one of `sfx_players`, so a one-shot triggered mid-drive
# (the servo, the scatter) never steals the bed's slot or cuts it off.
var bed_player: AudioStreamPlayer
var _bed_active: String = ""

# name -> variants. Multiple entries are cycled at play time so a verb repeated
# fifteen times in a row (tilling a row, harvesting a plot) does not replay one
# byte-identical buffer. Harvest ships three CC0 recordings; see CREDITS.md for
# each file's Freesound ID, author and licence.
var sfx_streams = {
    "click": [preload("res://assets/audio/sfx/ui_click.wav")],
    "till": [preload("res://assets/audio/sfx/till.wav")],
    # Q-31 foley: three real can-on-soil pours recorded by the designer
    # (2026-09-02), replacing the synthesized water.wav — the one verb
    # synthesis reliably failed at and CC0 had nothing for.
    "water": [
        preload("res://assets/audio/sfx/water_pour_01.wav"),
        preload("res://assets/audio/sfx/water_pour_02.wav"),
        preload("res://assets/audio/sfx/water_pour_03.wav"),
    ],
    "harvest": [
        preload("res://assets/audio/sfx/harvest_cc0_699491.wav"),
        preload("res://assets/audio/sfx/harvest_cc0_699492.wav"),
        preload("res://assets/audio/sfx/harvest_cc0_699493.wav"),
    ],
    "squawk": [preload("res://assets/audio/sfx/squawk.wav")],
    "cluck": [preload("res://assets/audio/sfx/cluck.wav")],
    # A dial turn on the training workbench (Q-102): CC0 recording, see CREDITS.md.
    "dial": [preload("res://assets/audio/sfx/dial_cc0_120844.wav")],
    "jingle": [preload("res://assets/audio/sfx/jingle.wav")],
    "nope": [preload("res://assets/audio/sfx/nope.wav")],
    # T-13: the offscreen moving truck. Two parps and an engine pulling away —
    # the callback that ends the cold open, in place of a truck sprite.
    "honk": [preload("res://assets/audio/sfx/honk.wav")],
    # P-15 p1 ("a sound bed under each story night"): the crow gorge's own two
    # strikes, one per side of the loop. CC0 recording; see CREDITS.md.
    "peck": [preload("res://assets/audio/sfx/peck_cc0_248254.wav")],
    # The seeder robot's three beats — a continuous bed (treads, played through
    # `play_bed`, not `play_sfx`) and two one-shots on the arm's own swing.
    # All three CC0; see CREDITS.md.
    "seeder_tread": [preload("res://assets/audio/sfx/seeder_tread_cc0_425271.wav")],
    "seeder_servo": [preload("res://assets/audio/sfx/seeder_servo_cc0_740244.wav")],
    "seeder_scatter": [preload("res://assets/audio/sfx/seeder_scatter_cc0_348953.wav")],
    # The boot bloom's rising chime (Q-103), synthesized (tools/gen_sfx.py) —
    # see CREDITS.md.
    "bloom_chime": [preload("res://assets/audio/sfx/bloom_chime.wav")],
}

# Presentation-only randomness, deliberately NOT SimRng: drawing from the seeded
# sim RNG here would consume it out of band and desync replays (S-5).
var _variant_rng := RandomNumberGenerator.new()
var _last_variant: Dictionary = {}

# Per-sound pitch jitter (±fraction): a few percent multiplies three takes into
# a dozen perceived pours. Only the heavy-repetition foley pool opts in.
var sfx_jitter = {"water": 0.04}

# The name of the last sound actually dispatched, and how many have been. A
# headless run has no audio device, so this is the only way a test can assert
# that a verb was *heard* — which is what the NPC watering cue needed
# (`world/farm.gd:_voice_actor_verb`). Written here and read nowhere in the game.
var last_sfx: String = ""
var sfx_count: int = 0

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS

    # Setup BGM player
    bgm_player = AudioStreamPlayer.new()
    bgm_player.stream = preload("res://assets/audio/music/bgm_wholesome.ogg")
    bgm_player.volume_db = BGM_BASE_DB
    bgm_player.bus = "Master"
    add_child(bgm_player)
    bgm_player.play()

    # Setup SFX players
    for i in range(num_sfx_players):
        var p = AudioStreamPlayer.new()
        p.bus = "Master"
        add_child(p)
        sfx_players.append(p)

    bed_player = AudioStreamPlayer.new()
    bed_player.bus = "Master"
    add_child(bed_player)
    bed_player.finished.connect(_on_bed_finished)


func play_sfx(sound_name: String):
    var variants = sfx_streams.get(sound_name)
    if variants == null or variants.is_empty():
        return
    last_sfx = sound_name
    sfx_count += 1

    var idx := 0
    if variants.size() > 1:
        idx = _variant_rng.randi_range(0, variants.size() - 1)
        # Never play the same variant twice running; that is the repetition the
        # cycling exists to avoid.
        if idx == int(_last_variant.get(sound_name, -1)):
            idx = (idx + 1) % variants.size()
        _last_variant[sound_name] = idx

    var jitter := float(sfx_jitter.get(sound_name, 0.0))
    var pitch := 1.0 + _variant_rng.randf_range(-jitter, jitter) if jitter > 0.0 else 1.0

    for p in sfx_players:
        if not p.playing:
            p.stream = variants[idx]
            p.pitch_scale = pitch
            p.play()
            return

    # All busy: reuse the first player rather than dropping the sound.
    if not sfx_players.is_empty():
        sfx_players[0].stream = variants[idx]
        sfx_players[0].pitch_scale = pitch
        sfx_players[0].play()


func _on_bed_finished() -> void:
    # A bed keeps going for as long as it is wanted, not for one play-through —
    # this is what makes a short recording (`seeder_tread` is 1.5s) cover a
    # loop that plays several seconds longer.
    if _bed_active != "" and bed_player.stream != null:
        bed_player.play()


## Starts a continuous background sound (see `_bed_active` above). A repeat
## call for the sound already playing is a no-op, so a caller can call this
## every frame without restarting the loop each time.
func play_bed(sound_name: String) -> void:
    var variants = sfx_streams.get(sound_name)
    if variants == null or variants.is_empty():
        return
    if _bed_active == sound_name and bed_player.playing:
        return
    _bed_active = sound_name
    bed_player.stream = variants[0]
    bed_player.play()


func stop_bed() -> void:
    _bed_active = ""
    bed_player.stop()


## Ducks `bgm_player` toward `BGM_DUCK_DB` below its base volume, `amount`
## ranging 0 (full volume) .. 1 (fully ducked). Presentation-only, driven by
## whatever currently wants the music quiet (today: the overnight's
## story-night loop, `systems/day_cycle.gd`) — nothing here remembers who
## asked, so the last call simply wins, same as any other volume knob.
func set_bgm_duck(amount: float) -> void:
    if bgm_player == null:
        return
    bgm_player.volume_db = BGM_BASE_DB - BGM_DUCK_DB * clampf(amount, 0.0, 1.0)
