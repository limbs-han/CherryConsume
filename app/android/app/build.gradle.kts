import java.util.Properties

// 출시 서명 키. android/key.properties가 키 파일과 비밀번호를 가리킨다. 둘 다 저장소에 올리지 않는다. 작업 005 설계 5h
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val releaseBuild = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
// 디버그 키로 서명한 출시 빌드가 나오지 않게 멈춘다
if (releaseBuild && keyProperties.isEmpty) {
    throw GradleException("android/key.properties가 없다. docs/release-setup.md")
}
val missingKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword").filter {
    !keyProperties.isEmpty && keyProperties.getProperty(it).isNullOrBlank()
}
if (missingKeys.isNotEmpty()) {
    throw GradleException("android/key.properties에 ${missingKeys.joinToString()}가 없다. docs/release-setup.md")
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cherryconsume.cherry_consume"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cherryconsume.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (!keyProperties.isEmpty) {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
