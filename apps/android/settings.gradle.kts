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

rootProject.name = "GalaxySSI"
include(":app")
include(":llama-runtime")
include(":collaboration-core")
project(":collaboration-core").projectDir = file("../shared/collaboration-core")
