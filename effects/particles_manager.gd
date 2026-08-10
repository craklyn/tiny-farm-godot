# particles_manager.gd — Manages particle effects
# Mirrors the Love2D particles.lua using Godot's GPUParticles2D
extends Node2D

var particle_texture: Texture2D


func _ready() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	particle_texture = ImageTexture.create_from_image(img)
func emit(effect_type: String, world_pos: Vector2) -> void:
	var particles := GPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.position = world_pos
	particles.texture = particle_texture

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 2.0

	match effect_type:
		"dirt":
			particles.amount = 12
			particles.lifetime = 0.5
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 180.0
			mat.initial_velocity_min = 20.0
			mat.initial_velocity_max = 50.0
			mat.gravity = Vector3(0, 60.0, 0)
			mat.scale_min = 1.0
			mat.scale_max = 1.5
			mat.color = Color(0.7, 0.5, 0.3)
		"water":
			particles.amount = 10
			particles.lifetime = 0.4
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 60.0
			mat.initial_velocity_min = 15.0
			mat.initial_velocity_max = 35.0
			mat.gravity = Vector3(0, 50.0, 0)
			mat.scale_min = 0.8
			mat.scale_max = 1.2
			mat.color = Color(0.4, 0.7, 0.9)
		"harvest":
			particles.amount = 15
			particles.lifetime = 0.6
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 180.0
			mat.initial_velocity_min = 10.0
			mat.initial_velocity_max = 30.0
			mat.gravity = Vector3(0, -15.0, 0)
			mat.scale_min = 1.0
			mat.scale_max = 2.0
			mat.color = Color(1, 0.9, 0.3)
		"chop":
			particles.amount = 10
			particles.lifetime = 0.4
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 120.0
			mat.initial_velocity_min = 25.0
			mat.initial_velocity_max = 60.0
			mat.gravity = Vector3(0, 70.0, 0)
			mat.scale_min = 1.0
			mat.scale_max = 1.5
			mat.color = Color(0.6, 0.45, 0.25)

	particles.process_material = mat
	add_child(particles)
	particles.emitting = true

	# Auto-cleanup after particles finish
	var cleanup_timer := Timer.new()
	cleanup_timer.wait_time = particles.lifetime + 0.5
	cleanup_timer.one_shot = true
	cleanup_timer.timeout.connect(func(): particles.queue_free(); cleanup_timer.queue_free())
	add_child(cleanup_timer)
	cleanup_timer.start()
