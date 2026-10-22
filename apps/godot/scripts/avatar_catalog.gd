extends RefCounted

const DIRECTORY := "res://assets/avatars/"
static var cached_names: PackedStringArray
static var scanned := false
static var textures: Dictionary = {}
static var portrait_material: ShaderMaterial

static func rounded_material() -> ShaderMaterial:
	if portrait_material == null:
		portrait_material = ShaderMaterial.new()
		portrait_material.shader = preload("res://resources/avatar_mask.gdshader")
	return portrait_material

static func names() -> PackedStringArray:
	if not scanned:
		scanned = true
		for entry in DirAccess.get_files_at(DIRECTORY):
			# Imported resources can be listed by their sidecars in an export.
			var filename := entry.trim_suffix(".remap").trim_suffix(".import")
			if filename.get_extension().to_lower() in ["png","jpg","jpeg","webp"] and not cached_names.has(filename) and ResourceLoader.exists(DIRECTORY+filename):
				cached_names.append(filename)
		cached_names.sort()
	return cached_names

static func resolve_id(value: String) -> String:
	var available := names()
	if available.has(value):
		return value
	if available.has("default.png"):
		return "default.png"
	return available[0] if not available.is_empty() else ""

static func texture_for(value: String) -> Texture2D:
	var id := resolve_id(value)
	if id.is_empty():
		return null
	if not textures.has(id):
		textures[id] = load(DIRECTORY+id) as Texture2D
	return textures[id]
