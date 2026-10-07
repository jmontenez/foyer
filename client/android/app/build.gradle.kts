plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Canal de distribution : « beta » produit une app installable à côté de l'app principale
// (applicationId suffixé, libellés distincts), signée avec la même clé. Voir docs/beta.md.
val foyerBeta = System.getenv("FOYER_CHANNEL") == "beta"

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
        // Libellés dépendants du canal : nom d'app (manifeste) et titres des widgets
        // (resValue plutôt que res/values pour rester pilotés par FOYER_CHANNEL).
        manifestPlaceholders["appLabel"] = if (foyerBeta) "Foyer β" else "Foyer"
        resValue("string", "widget_today_label", if (foyerBeta) "Foyer β · Aujourd’hui" else "Foyer · Aujourd’hui")
        resValue("string", "widget_shopping_label", if (foyerBeta) "Foyer β · Courses" else "Foyer · Courses")
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
            if (foyerBeta) {
                // Package distinct pour installer la beta à côté de l'app principale.
                // Les classes restent dans le namespace fr.foyer.foyer : les receivers
                // relatifs du manifeste et les qualifiedAndroidName Dart restent valides.
                applicationIdSuffix = ".beta"
                versionNameSuffix = "-beta"
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

dependencies {
    // Liste défilante du widget Courses (RemoteViewsCompat.setRemoteAdapter, sans service à écrire).
    implementation("androidx.core:core-remoteviews:1.1.0")
    // Actions des widgets : notre propre file (voir WidgetActions.kt), même version que home_widget.
    implementation("androidx.work:work-runtime-ktx:2.11.2")
}
