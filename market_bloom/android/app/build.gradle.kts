import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val requiredSigningKeys = listOf(
    "storePassword",
    "keyPassword",
    "keyAlias",
    "storeFile",
)
val invalidSigningKeys = requiredSigningKeys.filter { key ->
    val value = keystoreProperties.getProperty(key)?.trim().orEmpty()
    value.isEmpty() || value.startsWith("REPLACE_WITH_")
}
val configuredStoreFile = keystoreProperties.getProperty("storeFile")
    ?.trim()
    .orEmpty()
val productionAdMobAppId = providers
    .gradleProperty("POMARKET_ADMOB_APP_ID_ANDROID")
    .orElse(providers.environmentVariable("POMARKET_ADMOB_APP_ID_ANDROID"))
    .orNull
    ?.trim()
    .orEmpty()
val debugAdMobAppId = "ca-app-pub-3940256099942544~3347511713"

if (releaseRequested && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "Android release signing is not configured. Copy key.properties.example " +
            "to key.properties and provide the protected release keystore values.",
    )
}
if (releaseRequested && invalidSigningKeys.isNotEmpty()) {
    throw GradleException(
        "Android release signing has missing or placeholder values: " +
            invalidSigningKeys.joinToString(", "),
    )
}
if (releaseRequested &&
    configuredStoreFile.isNotEmpty() &&
    !rootProject.file(configuredStoreFile).isFile
) {
    throw GradleException(
        "Android release keystore was not found at the configured storeFile path.",
    )
}
if (releaseRequested && productionAdMobAppId.isEmpty()) {
    throw GradleException(
        "POMARKET_ADMOB_APP_ID_ANDROID is required for Android release builds.",
    )
}
if (releaseRequested &&
    (!productionAdMobAppId.startsWith("ca-app-pub-") ||
        !productionAdMobAppId.contains("~") ||
        productionAdMobAppId == debugAdMobAppId)
) {
    throw GradleException(
        "POMARKET_ADMOB_APP_ID_ANDROID must be a production AdMob app ID, not a test ID.",
    )
}

android {
    namespace = "com.sergiopodolyak.pomarket"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.sergiopodolyak.pomarket"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["ADMOB_APPLICATION_ID"] = debugAdMobAppId
    }

    signingConfigs {
        if (keystorePropertiesFile.exists() && invalidSigningKeys.isEmpty()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(configuredStoreFile)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            manifestPlaceholders["ADMOB_APPLICATION_ID"] = debugAdMobAppId
        }
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            manifestPlaceholders["ADMOB_APPLICATION_ID"] =
                productionAdMobAppId.ifEmpty { debugAdMobAppId }
            if (keystorePropertiesFile.exists() && invalidSigningKeys.isEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
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
