// Gradle build for this repository only. React Native host apps never evaluate
// this file: autolinking injects android/ into the app's own build and picks up
// the shared Kotlin sources through `sourceSets` (see android/build.gradle).

pluginManagement {
  repositories {
    google()
    mavenCentral()
    gradlePluginPortal()
  }
}

dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    google()
    mavenCentral()
  }
}

rootProject.name = "helium-passpoint"

// The published Android SDK.
include(":passpoint-core")
project(":passpoint-core").projectDir = file("core/kotlin")

// Verification only: compiles the React Native bridge against a pinned
// react-android (see gradle.properties) so `./gradlew build` catches a bridge
// that no longer matches the core.
include(":passpoint-react-native")
project(":passpoint-react-native").projectDir = file("android")

// Native example app. Depends on :passpoint-core as a separate module, so
// building it proves the SDK's public API is usable from outside the library.
include(":example-android")
project(":example-android").projectDir = file("examples/android-kotlin")
