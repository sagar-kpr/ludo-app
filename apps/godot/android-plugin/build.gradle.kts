plugins {
    id("com.android.library") version "8.6.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.20" apply false
}

tasks.register<Copy>("packageGodotAddon") {
    dependsOn(":rally-media:assembleDebug", ":rally-media:assembleRelease")
    into(layout.buildDirectory.dir("godot-addon/addons/rally_media"))
    from("godot-addon/addons/rally_media")
    from("rally-media/build/outputs/aar/rally-media-debug.aar") {
        into("bin")
    }
    from("rally-media/build/outputs/aar/rally-media-release.aar") {
        into("bin")
    }
}

