pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Required by LiveKit 2.23.5's pinned AudioSwitch dependency.
        maven("https://jitpack.io")
    }
}

rootProject.name = "rally-media-android"
include(":rally-media")

