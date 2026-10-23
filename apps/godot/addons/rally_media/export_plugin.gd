@tool
extends EditorPlugin

var _export_plugin: RallyMediaExportPlugin

func _enter_tree() -> void:
	_export_plugin = RallyMediaExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class RallyMediaExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "RallyMedia"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var variant := "debug" if debug else "release"
		return PackedStringArray(["res://addons/rally_media/bin/rally-media-%s.aar" % variant])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		# A local AAR does not bundle Maven dependencies. Keep these pins in sync
		# with rally-media/build.gradle.kts.
		return PackedStringArray([
			"io.livekit:livekit-android:2.23.5",
			"org.jetbrains.kotlinx:kotlinx-coroutines-android:1.6.0",
		])

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["https://jitpack.io"])
