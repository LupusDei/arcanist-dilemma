class_name UiScale
extends RefCounted
## Keeps the UI the same size relative to the window. Every screen is laid out
## for a 1600x900 view. Without a stretch mode Godot draws it at that pixel
## size on any window, so on a large or Retina screen it shrinks into a small
## strip with unreadable text.
##
## The proper fix is in project.godot, which scales all 2D at once:
##   [display]
##   window/stretch/mode="canvas_items"
##   window/stretch/aspect="expand"
## Until that is set, fit() scales our own layers to the window. As soon as a
## stretch mode is set it does nothing, so the two never stack.

const BASE_SIZE := Vector2(1600, 900)


## The factor that maps the 1600x900 layout onto the current window.
static func factor(viewport: Viewport) -> float:
	if viewport == null or _stretch_on(viewport):
		return 1.0
	var size := viewport.get_visible_rect().size
	return maxf(minf(size.x / BASE_SIZE.x, size.y / BASE_SIZE.y), 0.5)


static func _stretch_on(viewport: Viewport) -> bool:
	var win := viewport as Window
	if win == null:
		win = viewport.get_window()
	return win != null and win.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED


## Scales a CanvasLayer (and sizes its top-level controls to match) or a root
## Control, now and whenever the window changes size.
static func fit(node: Node) -> void:
	var viewport := node.get_viewport()
	if viewport == null:
		return
	_refit(node)
	var callable := _refit.bind(node)
	if not viewport.size_changed.is_connected(callable):
		viewport.size_changed.connect(callable)


static func _refit(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var viewport := node.get_viewport()
	var s := factor(viewport)
	var logical := viewport.get_visible_rect().size / s
	if node is CanvasLayer:
		(node as CanvasLayer).transform = Transform2D.IDENTITY.scaled(Vector2(s, s))
		for child in node.get_children():
			if not child is Control:
				continue
			var c := child as Control
			if c.has_meta(&"ui_fit") or (c.anchor_right == 1.0 and c.anchor_bottom == 1.0):
				c.set_meta(&"ui_fit", true)
				_size_control(c, logical, 1.0)
	elif node is Control:
		_size_control(node, logical, s)


static func _size_control(c: Control, logical: Vector2, s: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2.ZERO
	c.scale = Vector2(s, s)
	c.size = logical
