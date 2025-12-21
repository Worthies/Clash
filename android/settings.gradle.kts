// Read local.properties early and apply any proxy settings there as JVM system properties so
// Gradle tooling (pluginManagement, dependency resolution) can use the configured proxy.
run {
    val local = java.util.Properties()
    val lp = file("local.properties")
    if (lp.exists()) {
        lp.inputStream().use { local.load(it) }
        listOf("http", "https").forEach { proto ->
            val hostKey = "systemProp.$proto.proxyHost"
            val portKey = "systemProp.$proto.proxyPort"
            val host = local.getProperty(hostKey)
            val port = local.getProperty(portKey)
            if (!host.isNullOrBlank()) {
                System.setProperty("$proto.proxyHost", host)
                println("settings.gradle.kts: applied $proto.proxyHost=$host from local.properties")
            }
            if (!port.isNullOrBlank()) {
                System.setProperty("$proto.proxyPort", port)
                println("settings.gradle.kts: applied $proto.proxyPort=$port from local.properties")
            }
        }
    }
}

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")

// Include vpn4j as a composite build (platform-independent module)
// includeBuild("../vpn4j")
