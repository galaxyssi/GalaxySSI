plugins {
    id("com.android.application")
    kotlin("android")
}
android {
    namespace = "com.galaxyssi.watch"
    compileSdk = 35
    ndkVersion = "29.0.13113456"
    defaultConfig {
        applicationId = "com.galaxyssi.watch"
        minSdk = 33
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    testOptions { unitTests.isIncludeAndroidResources = true }
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }
    packaging {
        jniLibs.excludes += "**/libsignal_jni_testing.so"
        jniLibs.useLegacyPackaging = true
        resources.excludes += listOf("**/*.dll", "**/*.dylib", "**/*.so")
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation(project(":shared-link"))
    implementation("org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.wear:wear:1.3.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("com.squareup.okhttp3:okhttp-tls:4.12.0")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

// Generate the lightweight catalog from the phone's authoritative presets.
val phonePresets = file("../../android/app/src/main/java/com/galaxyssi/chat/MainActivityConstants.kt")
val catalogOutput = layout.buildDirectory.dir("generated/watchCatalog")
val generateWatchCatalog by tasks.registering {
    inputs.file(phonePresets)
    outputs.dir(catalogOutput)
    doLast {
        val entries = Regex("CloudModelPreset\\(\"[^\"]*\", \"[^\"]*\", \"[^\"]*\", \"[^\"]*\", \"[^\"]*\"\\)")
            .findAll(phonePresets.readText().substringAfter("val CLOUD_MODEL_PRESETS = listOf(")).map { it.value }.toList()
        check(entries.isNotEmpty()) { "Android cloud catalog is missing" }
        val target = catalogOutput.get().file("com/galaxyssi/watch/WatchCatalog.kt").asFile
        target.parentFile.mkdirs()
        target.writeText("package com.galaxyssi.watch\n" +
            "data class CloudModelPreset(val provider: String, val name: String, val model: String, val endpoint: String, val style: String)\n" +
            "val WATCH_MODEL_PRESETS = listOf(\n" + entries.joinToString(",\n") + "\n)\n")
    }
}
android.sourceSets.getByName("main").java.srcDir(catalogOutput)
tasks.named("preBuild").configure { dependsOn(generateWatchCatalog) }

val phoneBrandOutput = layout.buildDirectory.dir("generated/phoneBrand")
val syncPhoneBrand by tasks.registering(Sync::class) {
    from("../../android/app/src/main/res") {
        include("drawable/galaxyssi_mark_large.png", "drawable/ic_galaxyssi_logo.xml",
            "mipmap-anydpi-v26/ic_launcher.xml", "mipmap-anydpi-v26/ic_launcher_round.xml")
    }
    into(phoneBrandOutput)
}
android.sourceSets.getByName("main").res.srcDir(phoneBrandOutput)
tasks.named("preBuild").configure { dependsOn(syncPhoneBrand) }
