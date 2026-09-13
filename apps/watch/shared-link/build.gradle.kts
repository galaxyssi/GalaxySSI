plugins {
    id("com.android.library")
    kotlin("android")
}

// Compile the phone's actual sources, with an explicit allowlist. No phone runtime
// project, assets, native models, or application manifest enters the watch build.
val syncPhoneSources by tasks.registering(Sync::class) {
    from("../../android/app/src/main/java") {
        include(
            "com/galaxyssi/chat/AgentEncryptedStorage.kt",
            "com/galaxyssi/chat/AndroidPersistentSignalStore.kt",
            "com/galaxyssi/chat/GalaxySSICrypto.kt",
            "com/galaxyssi/chat/PhoneRelationshipIdentityBinding.kt",
            "com/galaxyssi/chat/GalaxySSILinkProtocol.kt",
            "com/galaxyssi/chat/GalaxySSIMqttWireChunking.kt",
            "com/galaxyssi/chat/MqttChunkManifest.kt"
        )
    }
    into(layout.buildDirectory.dir("generated/phone-sources"))
}
android {
    namespace = "com.galaxyssi.watch.link"
    compileSdk = 35
    defaultConfig { minSdk = 33 }
    sourceSets.getByName("main").java.srcDir(syncPhoneSources.map { it.destinationDir })
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
tasks.named("preBuild").configure { dependsOn(syncPhoneSources) }
dependencies { api("org.signal:libsignal-android:0.86.5") }
