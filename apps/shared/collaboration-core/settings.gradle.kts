pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("org.jetbrains.kotlin.jvm") version "2.0.21"
    }
}
dependencyResolutionManagement {
    repositories { mavenCentral() }
}
rootProject.name = "collaboration-core"
