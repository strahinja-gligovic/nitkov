class_name SfxBank
extends RefCounted
## The sound files: assets/sfx/<name>.wav, or <name>_1.wav, _2, ... when a
## sound has variants (tools/sfx/build_sfx.py writes them all). Loaded on
## first use and cached; pick() returns a random variant, never the same one
## twice in a row.

const DIR := "res://assets/sfx/"
const MAX_VARIANTS := 6

static var _cache := {}
static var _last := {}


## Every variant of `name` (empty if there is no such sound).
static func streams(name: StringName) -> Array[AudioStream]:
	if _cache.has(name):
		return _cache[name]
	var found: Array[AudioStream] = []
	var single := DIR + String(name) + ".wav"
	if ResourceLoader.exists(single):
		found.append(load(single) as AudioStream)
	else:
		for i in range(1, MAX_VARIANTS + 1):
			var path := DIR + "%s_%d.wav" % [name, i]
			if not ResourceLoader.exists(path):
				break
			found.append(load(path) as AudioStream)
	if found.is_empty():
		push_warning("SfxBank: no sound named '%s'" % name)
	_cache[name] = found
	return found


## Drops every loaded stream (SfxPool calls this when it leaves the tree, so
## nothing outlives the scene at exit).
static func clear() -> void:
	_cache.clear()
	_last.clear()


static func pick(name: StringName) -> AudioStream:
	var all := streams(name)
	if all.is_empty():
		return null
	if all.size() == 1:
		return all[0]
	var index := randi() % all.size()
	if index == _last.get(name, -1):
		index = (index + 1 + randi() % (all.size() - 1)) % all.size()
	_last[name] = index
	return all[index]
