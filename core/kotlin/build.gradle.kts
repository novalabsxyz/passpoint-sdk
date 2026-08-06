import groovy.json.JsonSlurper

plugins {
  id("com.android.library")
  id("org.jetbrains.kotlin.android")
  id("maven-publish")
}

// One version number drives npm, SwiftPM (git tag) and Maven.
@Suppress("UNCHECKED_CAST")
val packageJson = JsonSlurper().parse(rootProject.file("package.json")) as Map<String, Any>
val sdkVersion = packageJson["version"] as String

android {
  namespace = "com.helium.passpoint"
  compileSdk = 36

  defaultConfig {
    minSdk = 26
    consumerProguardFiles("consumer-rules.pro")
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  kotlinOptions {
    jvmTarget = "17"
    // The same sources are compiled by React Native host apps, which may still
    // be on Kotlin 1.8. Fail here rather than in a partner's build.
    apiVersion = "1.8"
    languageVersion = "1.8"
  }

  testOptions {
    unitTests {
      isIncludeAndroidResources = true
      // Lets tests touch android.util.Log without Robolectric. Everything with
      // real logic under test lives in the Android-free classes.
      isReturnDefaultValues = true
    }
  }

  publishing {
    singleVariant("release") {
      withSourcesJar()
      withJavadocJar()
    }
  }
}

// Fixtures live in core/testdata/ and the contract in core/contract/, both
// shared with the Swift and TypeScript suites. Hand the tests an absolute path
// rather than relying on the working directory.
tasks.withType<Test>().configureEach {
  systemProperty("repoRoot", rootProject.projectDir.absolutePath)
  // Declared as inputs or Gradle serves this task FROM-CACHE when only the
  // contract or a fixture changed — silently skipping the conformance test
  // that exists precisely to catch that drift.
  inputs.dir(rootProject.file("core/contract")).withPathSensitivity(PathSensitivity.RELATIVE)
  inputs.dir(rootProject.file("core/testdata")).withPathSensitivity(PathSensitivity.RELATIVE)

  testLogging {
    events("failed")
    exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
  }

  // Gradle prints nothing when the task is UP-TO-DATE, so a green run is
  // ambiguous between "all passed" and "did not run". Say which.
  addTestListener(object : TestListener {
    override fun beforeSuite(suite: TestDescriptor) {}
    override fun beforeTest(testDescriptor: TestDescriptor) {}
    override fun afterTest(testDescriptor: TestDescriptor, result: TestResult) {}
    override fun afterSuite(suite: TestDescriptor, result: TestResult) {
      if (suite.parent != null) return
      println(
        "Tests: ${result.testCount} total, ${result.successfulTestCount} passed, " +
          "${result.failedTestCount} failed, ${result.skippedTestCount} skipped"
      )
    }
  })
}

dependencies {
  implementation("androidx.core:core-ktx:1.13.1")
  implementation("androidx.annotation:annotation:1.8.2")
  implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
  implementation("org.bouncycastle:bcpkix-jdk18on:1.78.1")

  // The real org.json, so the Android-free classes can be unit-tested without
  // Robolectric. android.jar's stubs throw "not mocked" on every call.
  testImplementation("org.json:json:20240303")
  testImplementation("org.jetbrains.kotlin:kotlin-test-junit")
  testImplementation("junit:junit:4.13.2")
}

publishing {
  repositories {
    // `./gradlew :passpoint-core:publish` with no repository declared is a
    // silent no-op — the task is SKIPPED and the build still reports success.
    maven {
      name = "sonatype"
      url = uri(
        providers.gradleProperty("heliumMavenUrl")
          .getOrElse("https://ossrh-staging-api.central.sonatype.com/service/local/staging/deploy/maven2/")
      )
      credentials {
        username = providers.gradleProperty("heliumMavenUser").orNull
          ?: System.getenv("MAVEN_USERNAME")
        password = providers.gradleProperty("heliumMavenPassword").orNull
          ?: System.getenv("MAVEN_PASSWORD")
      }
    }
  }

  publications {
    register<MavenPublication>("release") {
      groupId = "com.helium.passpoint"
      artifactId = "passpoint-sdk"
      version = sdkVersion

      afterEvaluate { from(components["release"]) }

      pom {
        name.set("Helium Passpoint SDK")
        description.set("Helium Passpoint (Hotspot 2.0) WiFi offload SDK for Android")
        url.set("https://github.com/helium/passpoint-sdk")
        licenses {
          license {
            name.set("MIT")
            url.set("https://opensource.org/licenses/MIT")
          }
        }
        developers {
          developer {
            name.set("Nova Labs")
            url.set("https://github.com/helium")
          }
        }
        scm {
          url.set("https://github.com/helium/passpoint-sdk")
          connection.set("scm:git:https://github.com/helium/passpoint-sdk.git")
        }
      }
    }
  }
}
