# Runs the benchmark's eight-busy-machine scaling workload on desktop or Android.
# Use the same scene/build on both devices; each sample starts from a fresh seed.
extends Node

const BENCHMARK = preload("res://tools/benchmark_sim.gd")
const SAMPLES := 7

func _ready() -> void:
	for i in SAMPLES:
		var result: Dictionary = BENCHMARK._fleet_run(
			BENCHMARK.SCALE_FLEET, BotBrain.CONFIG_CIRCLE)
		print("SIM_PROFILE sample=%d ticks=%d seconds=%.6f actions=%d moved=%d" % [
			i + 1, BENCHMARK.SCALE_TICKS, result["elapsed"],
			result["actions"], result["moved"]])
	print("SIM_PROFILE done")
	get_tree().quit()
