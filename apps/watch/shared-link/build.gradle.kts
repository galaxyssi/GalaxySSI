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
            "com/galaxyssi/chat/Mqtt*.kt",
            "com/galaxyssi/chat/AndroidMqttChunks.kt",
            "com/galaxyssi/chat/GalaxySSILinkInbox.kt",
            "com/galaxyssi/chat/GalaxySSILinkTransportDiagnostics.kt"
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
// Run the phone's transport contract tests against the sources shipped on Wear OS.
val syncPhoneTransportTests by tasks.registering(Sync::class) {
    from("../../android/app/src/test/java") {
        listOf("MqttPoolTestRig", "MqttBrokerPoolTest", "MqttPoolTransportTest", "MqttPeerRoutesTest",
            "MqttMultipathPolicyTest", "MqttDeliveryDispatchTest", "MqttRouteAdvertisementTest",
            "MqttChunkReceiptsTest", "MqttChunkFlowTest", "MqttReceiptRetryTest", "MqttTrafficPolicyTest",
            "MqttOutboxRetryWindowTest", "MqttInboxDispatchGateTest", "MqttInboundRoutePoolTest",
            "MqttInboundBindingsTest", "GalaxySSIMqttWireChunkingTest").forEach { include("com/galaxyssi/chat/$it.kt") }
    }
    into(layout.buildDirectory.dir("generated/phone-tests"))
}
android.sourceSets.getByName("test").java.srcDir(syncPhoneTransportTests.map { it.destinationDir })
tasks.named("preBuild").configure { dependsOn(syncPhoneTransportTests) }
dependencies {
    api("org.signal:libsignal-android:0.86.5")
    implementation("org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
