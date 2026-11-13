allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // ✅ Отключаем превращение предупреждений Java в ошибки для ВСЕХ модулей
    tasks.withType<JavaCompile> {
        options.compilerArgs.add("-Xlint:-options")
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

// ==========================================
// ✅ ЗОЛОТОЙ ХАК: Принудительно поднимаем compileSdk до 36 для ВСЕХ плагинов
// (Лечит share_plus, file_picker, flutter_quick_video_encoder и др.)
// ВАЖНО: Этот блок должен идти ДО project.evaluationDependsOn(":app")
// ==========================================
subprojects {
    if (state.executed) {
        applyCompileSdk36(this)
    } else {
        afterEvaluate {
            applyCompileSdk36(this)
        }
    }
}

fun applyCompileSdk36(project: Project) {
    val androidExt = project.extensions.findByName("android") ?: return
    try {
        val setCompileSdk = androidExt.javaClass.methods.firstOrNull {
            it.name == "setCompileSdk" && it.parameterTypes.size == 1 &&
            it.parameterTypes[0] == Int::class.javaPrimitiveType
        }
        if (setCompileSdk != null) {
            val current = try {
                androidExt.javaClass.getMethod("getCompileSdk").invoke(androidExt) as? Int ?: 0
            } catch (_: Exception) { 0 }
            if (current < 36) {
                setCompileSdk.invoke(androidExt, 36)
                project.logger.lifecycle("🔧 ${project.name}: compileSdk → 36")
            }
        }
    } catch (e: Exception) {
        project.logger.warn("⚠️ ${project.name}: не удалось поднять compileSdk — ${e.message}")
    }
}
// ==========================================

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}