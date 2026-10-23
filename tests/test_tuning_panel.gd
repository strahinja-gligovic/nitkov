extends GutTest
## The tuning panel exposes every numeric knob and edits the resource live.


func test_panel_exposes_every_tuning_number() -> void:
	var tuning := CombatTuning.new()
	var panel := TuningPanel.new()
	add_child_autofree(panel)
	panel.setup([["Combat", tuning]])
	var numeric := 0
	for prop: Dictionary in tuning.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and prop["type"] in [TYPE_FLOAT, TYPE_INT]:
			numeric += 1
	assert_gt(numeric, 40)
	assert_eq(panel.find_children("*", "SpinBox", true, false).size(), numeric)


func test_editing_a_value_changes_the_resource() -> void:
	var tuning := CombatTuning.new()
	var panel := TuningPanel.new()
	add_child_autofree(panel)
	panel.setup([["Combat", tuning]])
	(panel.editor_for(tuning, "parry_window") as SpinBox).value = 0.2
	assert_almost_eq(tuning.parry_window, 0.2, 0.0001)
	(panel.editor_for(tuning, "chill_max_stacks") as SpinBox).value = 5
	assert_eq(tuning.chill_max_stacks, 5)


func test_nested_attacks_get_editors_too() -> void:
	var weapon: WeaponData = load("res://data/weapons/longsword.tres").duplicate(true)
	var panel := TuningPanel.new()
	add_child_autofree(panel)
	panel.setup([["Longsword", weapon]])
	assert_not_null(panel.editor_for(weapon.heavy, "windup"))
	assert_not_null(panel.editor_for(weapon.light_chain[2], "damage"))
	assert_not_null(panel.editor_for(weapon.heavy, "hyperarmor"), "bools get checkboxes")
