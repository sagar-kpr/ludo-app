plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.rally.godot.media"
    compileSdk = 35
    buildToolsVersion = "35.0.1"

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }
    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Godot's export template supplies the engine; never bundle a second copy.
    compileOnly("org.godotengine:godot:4.6.1.stable")
    implementation("io.livekit:livekit-android:2.23.5")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.6.0")
}

