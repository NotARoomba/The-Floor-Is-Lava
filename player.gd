extends CharacterBody2D

@onready var _animated_sprite = $AnimatedSprite2D


const SPEED = 400.0
const JUMP_VELOCITY = -800.0


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_animated_sprite.play("jump")

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("left", "right")
	if direction:
		_animated_sprite.play("run", 3.0)
		velocity.x = direction * SPEED
		_animated_sprite.flip_h = direction < 0
	else:
		_animated_sprite.play("default")
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

func play_death_animation():
	_animated_sprite.play("death")
