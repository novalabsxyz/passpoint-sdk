// Consumes the SDK exactly as a partner app would. Because it depends on
// :passpoint-core as a separate module, it only compiles if the SDK's *public*
// surface is complete — which is why CI assembles it:
//
//   ./gradlew :example-android:assembleDebug
//
// A real app would replace the project dependency with the published artifact:
//   implementation("com.helium.passpoint:passpoint-sdk:0.1.1")

plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.android")
}

android {
  namespace = "com.helium.passpoint.example"
  compileSdk = 36

  defaultConfig {
    applicationId = "com.helium.passpoint.example"
    minSdk = 26
    targetSdk = 36
    versionCode = 1
    versionName = "1.0"
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  kotlinOptions { jvmTarget = "17" }

  buildTypes {
    getByName("release") {
      isMinifyEnabled = true
      proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
    }
  }

  // BouncyCastle ships duplicate OSGi metadata across bcprov and bcpkix, which
  // the resource merger refuses to pick a winner for. Every app that pulls in
  // the SDK needs this block — see the Android section of the SDK README.
  packaging {
    resources {
      excludes += setOf(
        "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
        "META-INF/DEPENDENCIES",
      )
    }
  }
}

dependencies {
  implementation(project(":passpoint-core"))
  implementation("androidx.appcompat:appcompat:1.7.0")
  implementation("androidx.core:core-ktx:1.13.1")
}
