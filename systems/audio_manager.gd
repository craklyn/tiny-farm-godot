extends Node

var bgm_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var num_sfx_players = 8

var sfx_streams = {
    "click": preload("res://assets/audio/sfx/ui_click.wav"),
    "till": preload("res://assets/audio/sfx/till.wav"),
    "water": preload("res://assets/audio/sfx/water.wav"),
    "harvest": preload("res://assets/audio/sfx/harvest.wav"),
    "squawk": preload("res://assets/audio/sfx/squawk.wav"),
    "cluck": preload("res://assets/audio/sfx/cluck.wav"),
    "jingle": preload("res://assets/audio/sfx/jingle.wav")
}

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
    if not sfx_streams.has(sound_name):
        return
        
    for p in sfx_players:
        if not p.playing:
            p.stream = sfx_streams[sound_name]
            p.play()
            return
    
    # If all busy, override the oldest one (first in array that we cycle, or just the first)
    var p = sfx_players[0]
    p.stream = sfx_streams[sound_name]
    p.play()
