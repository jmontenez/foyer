plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "fr.foyer.foyer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "fr.foyer.foyer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (System.getenv("FOYER_KEYSTORE") != null) {
            create("personal") {
                storeFile = file(System.getenv("FOYER_KEYSTORE"))
                storePassword = System.getenv("FOYER_STORE_PASSWORD")
                keyAlias = System.getenv("FOYER_KEY_ALIAS")
                keyPassword = System.getenv("FOYER_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            // Never silently sign a production build with a public debug key.
            signingConfig = signingConfigs.findByName("personal")
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

dependencies {
    // FileProvider : transmet l’APK de mise à jour téléchargé à l’installateur Android.
    implementation("androidx.core:core:1.13.1")
}
