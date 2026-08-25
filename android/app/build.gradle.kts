plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val androidKeystorePath =
    providers.environmentVariable("ANDROID_KEYSTORE_PATH").getOrNull()
val androidKeyAlias =
    providers.environmentVariable("ANDROID_KEY_ALIAS").getOrNull()
val androidKeystorePassword =
    providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").getOrNull()
val androidKeyPassword =
    providers.environmentVariable("ANDROID_KEY_PASSWORD").getOrNull()
val releaseKeystoreFile = androidKeystorePath
    ?.takeUnless { it.isBlank() }
    ?.let { project.file(it) }
val missingReleaseSigningEnv = listOfNotNull(
    "ANDROID_KEYSTORE_PATH".takeIf { androidKeystorePath.isNullOrBlank() },
    "ANDROID_KEY_ALIAS".takeIf { androidKeyAlias.isNullOrBlank() },
    "ANDROID_KEYSTORE_PASSWORD".takeIf {
        androidKeystorePassword.isNullOrBlank()
    },
    "ANDROID_KEY_PASSWORD".takeIf { androidKeyPassword.isNullOrBlank() },
)
val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    doLast {
        if (missingReleaseSigningEnv.isNotEmpty()) {
            throw GradleException(
                "Android release signing credentials are required; missing " +
                    "environment variables: " +
                    missingReleaseSigningEnv.joinToString(", ") + ".",
            )
        }
        if (releaseKeystoreFile?.isFile != true) {
            throw GradleException(
                "Android release signing keystore is missing or is not a " +
                    "regular file.",
            )
        }
    }
}
tasks.configureEach {
    val isReleasePackagingTask =
        name.contains("Release") &&
            (
                name.startsWith("assemble") ||
                    name.startsWith("bundle") ||
                    name.startsWith("package") ||
                    name.startsWith("sign")
            )
    if (isReleasePackagingTask || name == "validateSigningRelease") {
        dependsOn(validateReleaseSigning)
    }
}

android {
    namespace = "com.ccreativeod1l.project_sw"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ccreativeod1l.project_sw"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = androidKeyAlias
            keyPassword = androidKeyPassword
            storeFile = releaseKeystoreFile
            storePassword = androidKeystorePassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
