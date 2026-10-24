extends SceneTree
## Tiles screenshots into one contact sheet, so a run's frames can be judged
## side by side (an agent reads the one PNG instead of a dozen).
##
##   godot_console --headless --path . -s tools/screens/contact_sheet.gd -- \
##       <out.png> <columns> <scale> <full | x,y,w,h> <in1.png> [in2.png ...]
##
## `scale` shrinks each cell (0.4 fits 4 columns of 1600x900 shots on one
## screen); the crop zooms every frame on the same region. Paths are OS paths.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("usage: <out.png> <columns> <scale> <full | x,y,w,h> <in.png>...")
		quit(1)
		return
	var out: String = args[0]
	var columns := int(args[1])
	var scale := float(args[2])
	var files := args.slice(4)
	for file in files:
		if not FileAccess.file_exists(file):
			push_error("no such screenshot: %s" % file)
			quit(1)
			return
	var first := Image.load_from_file(files[0])
	var rect := Rect2i(Vector2i.ZERO, first.get_size())
	if args[3] != "full":
		var crop := args[3].split(",")
		rect = Rect2i(int(crop[0]), int(crop[1]), int(crop[2]), int(crop[3]))
	var cell := Vector2i(roundi(rect.size.x * scale), roundi(rect.size.y * scale))
	var rows := ceili(files.size() / float(columns))
	var sheet := Image.create(cell.x * columns + (columns - 1) * 4, cell.y * rows + (rows - 1) * 4, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	for i in files.size():
		var image := Image.load_from_file(files[i])
		image.convert(Image.FORMAT_RGB8)
		var part := image.get_region(rect)
		part.resize(cell.x, cell.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(part, Rect2i(Vector2i.ZERO, cell), Vector2i((i % columns) * (cell.x + 4), (i / columns) * (cell.y + 4)))
	var error := sheet.save_png(out)
	if error != OK:
		push_error("couldn't save %s (does its folder exist?): %s" % [out, error_string(error)])
		quit(1)
		return
	print("sheet ", out, " ", sheet.get_size())
	quit()
