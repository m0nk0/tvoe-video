plugins {
    id("com.android.application")
    // ✅ УДАЛЕНО: id("kotlin-android") — Flutter теперь использует Built-in Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tvoymagazine.tvoe_video"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tvoymagazine.tvoe_video"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// ✅ Оставлено: настройка JVM target для Kotlin (работает с Built-in Kotlin)
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}