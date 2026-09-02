extends Node

var bgm_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var num_sfx_players = 8

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
    "jingle": [preload("res://assets/audio/sfx/jingle.wav")],
    "nope": [preload("res://assets/audio/sfx/nope.wav")],
    # T-13: the offscreen moving truck. Two parps and an engine pulling away —
    # the callback that ends the cold open, in place of a truck sprite.
    "honk": [preload("res://assets/audio/sfx/honk.wav")]
}

# Presentation-only randomness, deliberately NOT SimRng: drawing from the seeded
# sim RNG here would consume it out of band and desync replays (S-5).
var _variant_rng := RandomNumberGenerator.new()
var _last_variant: Dictionary = {}

# Per-sound pitch jitter (±fraction): a few percent multiplies three takes into
# a dozen perceived pours. Only the heavy-repetition foley pool opts in.
var sfx_jitter = {"water": 0.04}

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS

    # Setup BGM player
    bgm_player = AudioStreamPlayer.new()
    bgm_player.stream = preload("res://assets/audio/music/bgm_wholesome.ogg")
    bgm_player.volume_db = -10.0
    bgm_player.bus = "Master"
    add_child(bgm_player)
    bgm_player.play()
    
    # Setup SFX players
    for i in range(num_sfx_players):
        var p = AudioStreamPlayer.new()
        p.bus = "Master"
        add_child(p)
        sfx_players.append(p)

func play_sfx(sound_name: String):
    var variants = sfx_streams.get(sound_name)
    if variants == null or variants.is_empty():
        return

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
