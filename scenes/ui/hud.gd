extends CanvasLayer
## Debug HUD: controls reminder plus live movement state.

var _player: Player

@onready var _status_label: Label = %StatusLabel


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	var dodge_text := "ready"
	if _player.dodge_cooldown_remaining > 0.0:
		dodge_text = "%.1fs" % _player.dodge_cooldown_remaining
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var state := "Dodging" if _player.is_dodging else ("Grounded" if _player.is_on_floor() else "Airborne")
	_status_label.text = "Dodge: %s    Speed: %.1f m/s    %s" % [dodge_text, speed, state]
