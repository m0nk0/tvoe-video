allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // Применяем compileSdk 36 ко ВСЕМ Android-подпроектам (включая плагины)
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        try {
            // Для AGP 8.0+
            android.javaClass
                .getMethod("setCompileSdk", Int::class.java)
                .invoke(android, 36)
        } catch (e: NoSuchMethodException) {
            try {
                // Для старых версий AGP
                android.javaClass
                    .getMethod("setCompileSdkVersion", Int::class.java)
                    .invoke(android, 36)
            } catch (e2: NoSuchMethodException) {
                try {
                    android.javaClass
                        .getMethod("setCompileSdkVersion", String::class.java)
                        .invoke(android, "36")
                } catch (e3: Exception) {
                    logger.warn("Не удалось установить compileSdk для ${project.name}: ${e3.message}")
                }
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}