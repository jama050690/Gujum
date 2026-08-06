import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

dependencies {
    implementation("com.google.android.play:core:1.10.3")
    // Telefon raqami "hint" tanlagichi (SIM dagi raqamlar ro'yxati) shu
    // kutubxonadagi Identity API orqali keladi. google_sign_in ham buni tortadi,
    // lekin versiyasi kafolatlanmagani uchun aniq e'lon qilamiz.
    implementation("com.google.android.gms:play-services-auth:21.2.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Release signing comes from android/key.properties (gitignored, and written by
// CI from secrets). Without it we fall back to the debug key so local builds
// still work — but that key is regenerated per machine, so its SHA-1 never
// matches the one Google Sign-In is registered against.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.example.bootchat_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.bootchat_flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "⚠️  key.properties yo'q — release APK debug kalit bilan " +
                        "imzolanadi. Google Sign-In bunday buildda ishlamaydi.",
                )
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/*.kotlin_module",
            )
        }
        jniLibs {
            // --target-platform android-arm64 only filters the Flutter engine
            // libs — confirmed: libflutter.so/libapp.so ship arm64 only. Native
            // libs bundled inside plugin AARs (above all flutter_webrtc's
            // libjingle_peerconnection_so.so) still carried every ABI: 22 MB of
            // a 57 MB APK, for architectures that cannot start the app at all
            // without an engine .so. ndk.abiFilters did NOT drop them; excluding
            // at packaging time does, because it filters the merged JNI folder
            // regardless of which dependency contributed the file.
            excludes += setOf(
                "**/x86/**",
                "**/x86_64/**",
                "**/armeabi-v7a/**",
            )
        }
    }
}

flutter {
    source = "../.."
}
