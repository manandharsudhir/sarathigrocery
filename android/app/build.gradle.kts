plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.manandharsudhir.sarathigrocery"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.manandharsudhir.sarathigrocery"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Brands built from this codebase. Build/run with --flavor <name>.
    // Each brand's launcher label comes from its appName placeholder; its Dart-side name
    // from kAppName (lib/app/app.dart), which reads appFlavor.
    flavorDimensions += "brand"
    productFlavors {
        create("sarathi") {
            dimension = "brand"
            isDefault = true
            manifestPlaceholders["appName"] = "sarathigrocery"
        }
        create("uniquebakery") {
            dimension = "brand"
            applicationId = "com.manandharsudhir.uniquebakery"
            manifestPlaceholders["appName"] = "Unique Bakery and Cookies"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
