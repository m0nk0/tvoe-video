plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tvoymagazine.tvoe_video"
    
    // ✅ ФИКС 1: Поднимаем до 36 (требование file_picker 10.3.3 и lifecycle)
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
        
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a"))
        }
    }

    // ✅ ФИКС 2: Современный синтаксис packaging (вместо устаревшего packagingOptions)
    // Решает конфликт нативных библиотек FFmpeg и Flutter
    packaging {
        jniLibs {
            useLegacyPackaging = true
            pickFirsts += listOf(
                "lib/armeabi-v7a/libc++_shared.so",
                "lib/arm64-v8a/libc++_shared.so",
                "lib/x86/libc++_shared.so",
                "lib/x86_64/libc++_shared.so"
            )
        }
    }

    buildTypes {
        release {
            // ✅ ФИКС 3: Отключаем R8, чтобы он не вырезал нативные классы FFmpeg и VideoEncoder
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

// ✅ ФИКС 4: Отключаем превращение предупреждений Java в ошибки (лечит just_audio)
tasks.withType<JavaCompile> {
    options.compilerArgs.add("-Xlint:-options")
}