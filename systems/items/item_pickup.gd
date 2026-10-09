class_name ItemPickup
extends Area3D
## An item lying on the ground: a small colored placeholder with its name
## floating above in the rarity color, and a light beam for rares and uniques.
## Walking over it puts it in the bag (gold always; other items when they fit).
##
## Create with ItemPickup.spawn(item, parent, position).

signal picked_up(item: ItemInstance, by: Node)

@export var item: ItemInstance
@export var collector_group := &"player"
## Lets the item pop out before it can be taken.
@export var pickup_delay := 0.5

var _age := 0.0
var _taken := false
var _model: Node3D
var _label: Label3D
var _full_warned := false


static func spawn(p_item: ItemInstance, parent: Node, at: Vector3) -> ItemPickup:
	var pickup := ItemPickup.new()
	pickup.item = p_item
	parent.add_child(pickup)
	pickup.global_position = at
	return pickup


func _ready() -> void:
	add_to_group(&"item_pickups")
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	shape.position.y = 0.5
	add_child(shape)
	_build_visual()
	body_entered.connect(_try_collect)


func _physics_process(delta: float) -> void:
	_age += delta
	if _model:
		_model.rotation.y += delta * 1.2
		_model.position.y = 0.3 + sin(_age * 2.5) * 0.06
	if _age >= pickup_delay and not _taken:
		for body in get_overlapping_bodies():
			_try_collect(body)


func _try_collect(body: Node) -> void:
	if _taken or _age < pickup_delay or item == null or not body.is_in_group(collector_group):
		return
	var items := _items_service()
	var taken := false
	if items:
		if item.get_kind() == ItemDefs.Kind.GOLD or items.inventory.can_fit(item):
			taken = items.pick_up(item)
		elif not _full_warned:
			_full_warned = true
			items.message.emit("Your bag is full")
	elif body.has_method("pick_up_item"):
		taken = body.pick_up_item(item)
	if taken:
		_taken = true
		picked_up.emit(item, body)
		queue_free()


func _build_visual() -> void:
	if item == null:
		return
	var base := item.get_base()
	var color := base.color if base else Color.WHITE
	_model = Node3D.new()
	add_child(_model)
	var mesh := MeshInstance3D.new()
	var size := item.get_size()
	match item.get_kind():
		ItemDefs.Kind.GOLD:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.18
			cyl.bottom_radius = 0.18
			cyl.height = 0.08
			mesh.mesh = cyl
		ItemDefs.Kind.POTION:
			var sph := SphereMesh.new()
			sph.radius = 0.14
			sph.height = 0.3
			mesh.mesh = sph
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.18 * size.x, 0.18 * size.y, 0.12)
			mesh.mesh = box
			mesh.position.y = 0.09 * size.y
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = item.get_color() if item.rarity != ItemDefs.Rarity.COMMON else color
	mat.emission_energy_multiplier = 0.6
	mat.metallic = 0.3 if item.get_kind() == ItemDefs.Kind.GOLD else 0.0
	mesh.material_override = mat
	_model.add_child(mesh)

	if item.rarity >= ItemDefs.Rarity.RARE:
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.12
		cyl.height = 3.0
		beam.mesh = cyl
		beam.position.y = 1.5
		var beam_mat := StandardMaterial3D.new()
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := item.get_color()
		beam_mat.albedo_color = Color(c.r, c.g, c.b, 0.35)
		beam.material_override = beam_mat
		add_child(beam)

	_label = Label3D.new()
	if item.get_kind() == ItemDefs.Kind.GOLD:
		_label.text = "%d Gold" % item.quantity
	elif item.quantity > 1:
		_label.text = "%s x%d" % [item.get_display_name(), item.quantity]
	else:
		_label.text = item.get_display_name()
	_label.modulate = item.get_color()
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.outline_size = 8
	# Same size on screen at any distance, like Diablo's item names.
	_label.fixed_size = true
	_label.font_size = 32
	_label.pixel_size = 0.0006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position.y = 0.9
	add_child(_label)


func _items_service() -> Node:
	return get_node_or_null(^"/root/Items")
