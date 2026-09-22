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
            "com/galaxyssi/chat/NearbyContactProtocol.kt",
            "com/galaxyssi/chat/AndroidPersistentSignalStore.kt",
            "com/galaxyssi/chat/GalaxySSICrypto.kt",
            "com/galaxyssi/chat/PhoneRelationshipIdentityBinding.kt",
            "com/galaxyssi/chat/GalaxySSIDeviceIdentity.kt",
            "com/galaxyssi/chat/GalaxySSILinkProtocol.kt",
            "com/galaxyssi/chat/GalaxySSIMqttWireChunking.kt",
            "com/galaxyssi/chat/Mqtt*.kt",
            "com/galaxyssi/chat/AndroidMqttChunks.kt",
            "com/galaxyssi/chat/GalaxySSILinkInbox.kt",
            "com/galaxyssi/chat/GalaxySSILinkTransportDiagnostics.kt"
        )
    }
    from("../../android/app/src/main/java") {
        include("com/galaxyssi/chat/PhoneContactCard.kt")
        // Only the profile storage adapter differs; signing, validation and rendezvous remain shared.
        filter { line: String -> line.replace("AppStore.profile(context)", "WatchContactProfile.current(context)") }
    }
    into(layout.buildDirectory.dir("generated/phone-sources"))
}
android {
    namespace = "com.galaxyssi.watch.link"
    compileSdk = 35
    defaultConfig {
        minSdk = 33
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    sourceSets.getByName("main").java.srcDir(syncPhoneSources.map { it.destinationDir })
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    packaging {
        jniLibs.useLegacyPackaging = true
        jniLibs.excludes += "**/libsignal_jni_testing.so"
        resources.excludes += listOf("**/*.dll", "**/*.dylib", "**/*.so")
    }
}
tasks.named("preBuild").configure { dependsOn(syncPhoneSources) }
// Run the phone's transport contract tests against the sources shipped on Wear OS.
val syncPhoneTransportTests by tasks.registering(Sync::class) {
    from("../../android/app/src/test/java") {
        listOf("MqttPoolTestRig", "MqttBrokerPoolTest", "MqttPoolTransportTest", "MqttPeerRoutesTest",
            "MqttMultipathPolicyTest", "MqttDeliveryDispatchTest", "MqttRouteAdvertisementTest",
            "MqttChunkReceiptsTest", "MqttChunkFlowTest", "MqttReceiptRetryTest", "MqttTrafficPolicyTest",
            "MqttOutboxRetryWindowTest", "MqttInboxDispatchGateTest", "MqttInboundRoutePoolTest",
            "MqttInboundBindingsTest", "GalaxySSIMqttWireChunkingTest", "PhoneContactCardTest",
            "PhoneRelationshipIdentityBindingTest").forEach { include("com/galaxyssi/chat/$it.kt") }
    }
    into(layout.buildDirectory.dir("generated/phone-tests"))
}
android.sourceSets.getByName("test").java.srcDir(syncPhoneTransportTests.map { it.destinationDir })
tasks.named("preBuild").configure { dependsOn(syncPhoneTransportTests) }
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    api("org.signal:libsignal-android:0.86.5")
    implementation("org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

val syncRouteDeviceTests by tasks.registering(Sync::class) {
    from("../../android/app/src/androidTest/java") {
        include("com/galaxyssi/chat/MqttRouteStateDeviceTest.kt")
    }
    into(layout.buildDirectory.dir("generated/route-device-tests"))
}
android.sourceSets.getByName("androidTest").java.srcDir(syncRouteDeviceTests.map { it.destinationDir })
tasks.named("preBuild").configure { dependsOn(syncRouteDeviceTests) }
