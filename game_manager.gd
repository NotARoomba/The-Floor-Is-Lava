extends Node2D

# === Inspector Vars ===
@export var tile_layer: TileMapLayer
@export var player: Node2D

# Floor Settings
@export var floor_source_id: int = 0
@export var floor_height: int = 0
@export var floor_depth: int = 3
@export var chunk_size: int = 16
@export var view_distance: int = 3

# Platform Settings
@export var platform_source_id: int = 0
@export var platform_width_range: Vector2i = Vector2i(3, 8)
@export var platform_spacing_vertical: Vector2i = Vector2i(3, 5) # min/max spacing up
@export var platform_spacing_horizontal_max: int = 6

@export var lava_speed: float = 1.0
@export var lava_thickness: int = 8 # How many tile layers thick the lava should be
# Atlas Coords
@export var floor_tiles: Array[Vector2i] = [
	Vector2i(7, 0),
	Vector2i(7, 1),
	Vector2i(7, 2)
]
@export var platform_tiles: Array[Vector2i] = [
	Vector2i(12, 4),
	Vector2i(13, 4),
	Vector2i(14, 4)
]

# === Internal Vars ===
var loaded_chunks := {}
var rng = RandomNumberGenerator.new()
var highest_platform_y := {} # Dictionary per chunk_x

# Lava system
var lava_y: float = 0.0 # Current lava height in tile coordinates
var lava_world_y: float = 0.0 # Current lava height in world coordinates
var lava_chunks := {} # Track lava tiles per chunk

# Game over system
var is_game_over := false
var death_animation_played := false
var fade_overlay: ColorRect
var fade_tween: Tween

# Countdown vars
var start_countdown_time := 3.0
var game_started := false
var countdown_label: Label

func _ready():
	rng.randomize()
	_setup_countdown_ui()
	_generate_initial_chunks()
	_generate_lava()

func _process(delta):
	if not game_started:
		start_countdown_time -= delta
		if start_countdown_time > 0:
			if countdown_label and is_instance_valid(countdown_label):
				countdown_label.text = str(int(ceil(start_countdown_time)))
		else:
			if countdown_label and is_instance_valid(countdown_label):
				countdown_label.text = "GO!"
				if start_countdown_time <= -1.0: # 1 sec after GO
					countdown_label.queue_free()
					countdown_label = null
					game_started = true
		return
	
	var player_chunk_x = _world_to_chunk_x(player.global_position.x)
	_generate_chunks_around(player_chunk_x)
	_cleanup_chunks(player_chunk_x)
	

	# Check for game over (player touching lava)
	if game_started and not is_game_over:
		_check_lava_collision()
	
	if is_game_over:
		_handle_game_over(delta)
		return

	# Continuously add platforms above player if needed
	_extend_platforms_above_player(player_chunk_x)

	_move_lava(delta)

# === Helpers ===
func _generate_lava():
	# Generate initial lava layer below the player
	lava_y = 7 # Start at tile Y = 7
	lava_world_y = lava_y * 32.0 # Convert to world coordinates
	_generate_lava_layer()
	

func _move_lava(delta: float):
	# Move lava up continuously
	lava_y -= lava_speed * delta
	lava_world_y = lava_y * 32.0 # Update world coordinates
	
	# Generate new lava layer at current height
	_generate_lava_layer()
	
	# Clean up old lava tiles that are too far below
	_cleanup_old_lava()

func _generate_lava_layer():
	# Get player chunk position to center lava generation
	var player_chunk_x = _world_to_chunk_x(player.global_position.x)
	
	# Generate lava across the entire screen width around the player
	for chunk_x in range(player_chunk_x - view_distance - 1, player_chunk_x + view_distance + 2):
		var chunk_key = str(chunk_x)
		if not lava_chunks.has(chunk_key):
			lava_chunks[chunk_key] = []
		
		# Clear old lava tiles for this chunk
		for old_tile in lava_chunks[chunk_key]:
			tile_layer.set_cell(old_tile, -1) # Remove old tile
		lava_chunks[chunk_key].clear()
		
		# Generate new lava tiles for this chunk
		var start_cell_x = chunk_x * chunk_size
		for local_x in range(chunk_size):
			var cell_x = start_cell_x + local_x
			
			# Generate multiple layers of lava for thickness
			for layer in range(lava_thickness):
				var cell_y = int(lava_y) + layer
				
				# Place lava tile
				var lava_tile = Vector2i(rng.randi() % 20, rng.randi() % 10)
				tile_layer.set_cell(Vector2i(cell_x, cell_y), platform_source_id, lava_tile)
				
				# Track this tile for cleanup
				lava_chunks[chunk_key].append(Vector2i(cell_x, cell_y))

func _cleanup_old_lava():
	# Remove lava tiles that are too far below the current lava level
	# Account for lava thickness in cleanup threshold
	var cleanup_threshold = lava_y + lava_thickness + 50 # Remove tiles 50 units below current lava
	
	for chunk_key in lava_chunks.keys():
		var tiles_to_remove = []
		for tile_pos in lava_chunks[chunk_key]:
			if tile_pos.y > cleanup_threshold:
				tile_layer.set_cell(tile_pos, -1)
				tiles_to_remove.append(tile_pos)
		
		# Remove cleaned tiles from tracking
		for tile_pos in tiles_to_remove:
			lava_chunks[chunk_key].erase(tile_pos)

func _setup_countdown_ui():
	countdown_label = Label.new()
	countdown_label.add_theme_font_size_override("font_size", 96)
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.anchor_left = 0.5
	countdown_label.anchor_right = 0.5
	countdown_label.anchor_top = 0.5
	countdown_label.anchor_bottom = 0.5
	countdown_label.position = Vector2(576, 324)
	add_child(countdown_label)
	
	# Create fade overlay for game over
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color.BLACK
	fade_overlay.modulate.a = 0.0
	fade_overlay.anchor_left = 0.0
	fade_overlay.anchor_right = 1.0
	fade_overlay.anchor_top = 0.0
	fade_overlay.anchor_bottom = 1.0
	fade_overlay.z_index = 1000 # Ensure it's on top
	fade_overlay.visible = false # Start hidden
	add_child(fade_overlay)

func _world_to_chunk_x(world_x: float) -> int:
	var cell_x = tile_layer.local_to_map(Vector2(world_x, 0)).x
	return int(floor(cell_x / chunk_size))

func _chunk_key(chunk_x: int) -> String:
	return str(chunk_x)

# === Generation ===
func _generate_initial_chunks():
	var start_chunk = _world_to_chunk_x(player.global_position.x)
	_generate_chunks_around(start_chunk)

func _generate_chunks_around(center_chunk_x: int):
	for x in range(center_chunk_x - view_distance, center_chunk_x + view_distance + 1):
		var key = _chunk_key(x)
		if not loaded_chunks.has(key):
			_generate_chunk(x)

func _generate_chunk(chunk_x: int):
	var key = _chunk_key(chunk_x)
	loaded_chunks[key] = true
	var start_cell_x = chunk_x * chunk_size

	# Floor
	for local_x in range(chunk_size):
		var cell_x = start_cell_x + local_x
		for y in range(floor_depth):
			var cell_y = floor_height + y
			var atlas_coords = floor_tiles[0] if y == 0 else floor_tiles[1]
			tile_layer.set_cell(Vector2i(cell_x, cell_y), floor_source_id, atlas_coords)
	
	# Platforms
	var highest_y = _generate_platforms_in_chunk(chunk_x, floor_height - rng.randi_range(2, 4))
	highest_platform_y[chunk_x] = highest_y

func _cleanup_chunks(center_chunk_x: int):
	var to_remove = []
	for key in loaded_chunks.keys():
		var chunk_x = int(key)
		if abs(chunk_x - center_chunk_x) > view_distance:
			to_remove.append(key)
	for key in to_remove:
		_remove_chunk(int(key))

func _remove_chunk(chunk_x: int):
	var start_cell_x = chunk_x * chunk_size
	for local_x in range(chunk_size):
		var cell_x = start_cell_x + local_x
		for y in range(floor_depth + 300):
			tile_layer.set_cell(Vector2i(cell_x, floor_height - y), -1)
	loaded_chunks.erase(_chunk_key(chunk_x))
	highest_platform_y.erase(chunk_x)
	
	# Also clean up lava tiles for this chunk
	var chunk_key = str(chunk_x)
	if lava_chunks.has(chunk_key):
		for tile_pos in lava_chunks[chunk_key]:
			tile_layer.set_cell(tile_pos, -1)
		lava_chunks.erase(chunk_key)

func _generate_platforms_in_chunk(chunk_x: int, start_y: int) -> int:
	var y_pos = start_y
	var ground_y = floor_height
	var player_tile_y = tile_layer.local_to_map(player.global_position).y
	var max_platform_y = min(player_tile_y - 10, ground_y - 200) # allow more height

	while y_pos >= max_platform_y:
		var platform_x = chunk_x * chunk_size + rng.randi_range(0, platform_spacing_horizontal_max)
		var platform_width = rng.randi_range(platform_width_range.x, platform_width_range.y)
		for x in range(platform_width):
			var cell_x = platform_x + x
			var atlas_coords: Vector2i
			if x == 0:
				atlas_coords = platform_tiles[0]
			elif x == platform_width - 1:
				atlas_coords = platform_tiles[2]
			else:
				atlas_coords = platform_tiles[1]
			tile_layer.set_cell(Vector2i(cell_x, y_pos), platform_source_id, atlas_coords)

		y_pos -= rng.randi_range(platform_spacing_vertical.x, platform_spacing_vertical.y)

	return y_pos

func _extend_platforms_above_player(center_chunk_x: int):
	var player_tile_y = tile_layer.local_to_map(player.global_position).y
	for chunk_x in range(center_chunk_x - view_distance, center_chunk_x + view_distance + 1):
		if highest_platform_y.has(chunk_x):
			# If player is within 10 tiles of highest platform in chunk, add more above it
			if player_tile_y - highest_platform_y[chunk_x] < 12:
				var new_highest = _generate_platforms_in_chunk(chunk_x, highest_platform_y[chunk_x] - rng.randi_range(3, 5))
				highest_platform_y[chunk_x] = new_highest


# === Game Over System ===
func _check_lava_collision():
	if not game_started:
		return

	# Get adjusted player position (offset by 534 for proper collision detection)
	var player_y = player.global_position.y - 534
	var lava_top_y = lava_world_y

	# Check if player is touching lava
	if player_y >= lava_top_y:
		_trigger_game_over()

func _trigger_game_over():
	if not is_game_over:
		is_game_over = true
		
		# Play death animation if player has one
		if player.has_method("play_death_animation"):
			player.play_death_animation()
		else:
			# Fallback: just hide the player
			player.visible = false
		
		# Start fade to black
		_start_fade_to_black()

func _handle_game_over(delta):
	# Handle game over state
	# This function runs every frame when game is over
	pass

func _start_fade_to_black():
	# Make overlay visible and fade to black
	fade_overlay.visible = true
	fade_overlay.modulate.a = 0.0
	
	# Create tween for smooth fade to black
	fade_tween = create_tween()
	fade_tween.tween_property(fade_overlay, "modulate:a", 1.0, 1.5) # 1.5 second fade
	fade_tween.tween_callback(_on_fade_complete)

func _on_fade_complete():
	# Wait a moment on black screen, then restart
	await get_tree().create_timer(1.0).timeout
	_restart_game()

func _restart_game():
	# Reset game state
	is_game_over = false
	death_animation_played = false
	game_started = false
	start_countdown_time = 3.0
	
	# Reset player
	if player:
		player.visible = true
		player.global_position.y = -32 # Reset to starting position
	
	# Reset lava
	_generate_lava()
	
	# Reset chunks
	loaded_chunks.clear()
	highest_platform_y.clear()
	lava_chunks.clear()
	_generate_initial_chunks()
	
	# Reset countdown UI
	_reset_countdown_ui()
	
	# Fade back in
	_fade_back_in()

func _fade_back_in():
	# Fade from black back to transparent
	fade_tween = create_tween()
	fade_tween.tween_property(fade_overlay, "modulate:a", 0.0, 1.0) # 1 second fade
	fade_tween.tween_callback(_on_fade_back_in_complete)

func _on_fade_back_in_complete():
	# Hide overlay and start countdown
	fade_overlay.visible = false
	_start_countdown()

func _start_countdown():
	# Start the countdown timer
	start_countdown_time = 3.0
	game_started = false
	
	# Ensure countdown label is visible and set to "3"
	if countdown_label and is_instance_valid(countdown_label):
		countdown_label.text = "3"
		countdown_label.visible = true

func _reset_countdown_ui():
	# Recreate countdown label if it doesn't exist or is invalid
	if not countdown_label or not is_instance_valid(countdown_label):
		countdown_label = Label.new()
		countdown_label.add_theme_font_size_override("font_size", 96)
		countdown_label.add_theme_color_override("font_color", Color.WHITE)
		countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		countdown_label.anchor_left = 0.5
		countdown_label.anchor_right = 0.5
		countdown_label.anchor_top = 0.5
		countdown_label.anchor_bottom = 0.5
		countdown_label.position = Vector2(576, 324)
		add_child(countdown_label)
	
	# Reset the label
	countdown_label.text = "3"
	countdown_label.visible = true
