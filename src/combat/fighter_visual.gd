class_name FighterVisual
extends Node3D
## Displays a fighter's state. Reads Fighter.state every frame and never
## writes to it. (Placeholder capsule until the character model lands.)

var fighter: Fighter


func _ready() -> void:
	fighter = get_parent() as Fighter
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	body.mesh = capsule
	body.position = Vector3(0, 0.9, 0)
	body.material_override = ToonMaterials.make(Color(0.2, 0.7, 0.7) if fighter.team == 0 else Color(1.0, 0.45, 0.2))
	add_child(body)
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.2, 0.5)
	nose.mesh = box
	nose.position = Vector3(0, 1.4, -0.45)
	nose.material_override = ToonMaterials.make(Color(0.9, 0.9, 0.85))
	add_child(nose)
