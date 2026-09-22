import java.security.MessageDigest
import java.net.URI
import java.nio.file.Files
import java.nio.file.StandardCopyOption

plugins {
    id("com.android.application")
    kotlin("android")
}

// Bundle a checksum-pinned offline model; no runtime model download or credentials are required.
val wakeModelSha256 = "30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498"
val wakeModelAssets = layout.buildDirectory.dir("generated/wakeAssets")
val prepareWakeModel by tasks.registering {
    inputs.property("modelSha256", wakeModelSha256)
    outputs.dir(wakeModelAssets)
    doLast {
        val archive = File(gradle.gradleUserHomeDir, "caches/galaxyssi-models/$wakeModelSha256.zip")
        fun digest(file: File): String {
            val hash = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { stream ->
                val buffer = ByteArray(65536)
                while (true) { val n = stream.read(buffer); if (n < 0) break; hash.update(buffer, 0, n) }
            }
            return hash.digest().joinToString("") { "%02x".format(it) }
        }
        if (!archive.isFile || digest(archive) != wakeModelSha256) {
            archive.parentFile.mkdirs()
            val partial = File(archive.parentFile, "$wakeModelSha256.partial")
            val connection = URI("https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip").toURL().openConnection()
            connection.connectTimeout = 30000
            connection.readTimeout = 120000
            connection.getInputStream().use { input -> partial.outputStream().use { input.copyTo(it) } }
            check(digest(partial) == wakeModelSha256) { "Offline wake model checksum mismatch" }
            Files.move(partial.toPath(), archive.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        val target = wakeModelAssets.get().dir("model-en-us").asFile
        copy {
            from(zipTree(archive))
            into(target)
            eachFile { path = path.substringAfter('/') }
            includeEmptyDirs = false
        }
        File(target, "uuid").writeText(wakeModelSha256 + "\n")
    }
}
android.sourceSets["main"].assets.srcDir(wakeModelAssets)
tasks.named("preBuild").configure { dependsOn(prepareWakeModel) }
android {
    namespace = "com.galaxyssi.watch"
    compileSdk = 35
    ndkVersion = "29.0.13113456"
    defaultConfig {
        applicationId = "com.galaxyssi.watch"
        minSdk = 33
        targetSdk = 35
        versionCode = 61
        versionName = "0.3.29"
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
    implementation("com.google.zxing:core:3.5.3")
    implementation("com.alphacephei:vosk-android:0.3.75@aar")
    implementation("net.java.dev.jna:jna:5.18.1@aar")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation(project(":shared-link"))
    implementation("org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.wear:wear:1.3.0")
    implementation("org.jsoup:jsoup:1.23.1")
    implementation("org.commonmark:commonmark:0.24.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
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
            "drawable/ic_input_menu_layers.xml", "drawable/ic_composer_send_plane.xml",
            "mipmap-anydpi-v26/ic_launcher.xml", "mipmap-anydpi-v26/ic_launcher_round.xml")
    }
    into(phoneBrandOutput)
}
android.sourceSets.getByName("main").res.srcDir(phoneBrandOutput)
tasks.named("preBuild").configure { dependsOn(syncPhoneBrand) }

val syncPhonePeerVoice by tasks.registering(Sync::class) {
    from("../../android/app/src/main/java") {
        include("com/galaxyssi/chat/voice/audio/PeerVoiceOpusRecorder.kt",
            "com/galaxyssi/chat/voice/audio/PeerVoiceMessageAudio.kt")
    }
    into(layout.buildDirectory.dir("generated/phonePeerVoice"))
}
android.sourceSets.getByName("main").java.srcDir(syncPhonePeerVoice.map { it.destinationDir })
tasks.named("preBuild").configure { dependsOn(syncPhonePeerVoice) }

// Compile Android's complete Web Intelligence engine from an explicit source allowlist.
val phoneWebRoot = file("../../android/app/src/main/java/com/galaxyssi/chat")
val webFiles = listOf(
    "RetiredAgentModelPolicy.kt",
    "GalaxySSIIdenticon.kt", "GalaxySSIIdenticonDrawable.kt",
    "AgentRemoteRecoveryClient.kt", "AgentResultRecoveryClient.kt", "AgentResultRecoveryPageCodec.kt",
    "AgentResultPageCheckpoint.kt", "AgentResultPageDatabase.kt", "GalaxySSITransportPrivacyPolicy.kt",
    "metrics/AgentRecoveryTiming.kt", "metrics/AgentLatencyTrace.kt",
    "metrics/AgentModelTiming.kt", "metrics/AgentPlanningTiming.kt", "metrics/AgentRuntimeTiming.kt",
    "metrics/AgentTimingJournal.kt",
    "AgentWebIntelligence.kt", "AgentWebIntelligenceService.kt", "AgentWebIntelligenceTransport.kt",
    "AgentWebEvidenceReader.kt", "AgentWebEvidencePack.kt", "AgentWebEvidenceVerification.kt",
    "AgentWebResearchPlan.kt", "AgentWebRendererHealth.kt", "AgentWebMaintenanceQueue.kt",
    "AgentWebLimits.kt", "AgentWebFetchSingleFlight.kt", "AgentWebExecutionBudget.kt",
    "AgentPublicWebSearchParser.kt", "AgentPublicImageSearchParser.kt", "AgentPublicArticleParser.kt",
    "AgentDynamicWebArticleFetcher.kt", "AgentIsolatedWebViewRenderer.kt", "AgentIsolatedWebRenderService.kt",
    "AgentInlineMarkdown.kt", "AgentRichInlineMarkdownRenderer.kt",
    "AgentRichContent.kt", "AgentRichFormatRegistry.kt", "AgentMarkdownImages.kt",
    "MicrosoftEdgeTts.kt", "MicrosoftEdgeTtsProtocol.kt", "MicrosoftTtsVoiceCatalog.kt",
    "voice/metrics/VoiceLatencyTracer.kt", "voice/audio/VoiceCommunicationAudioSession.kt",
    "voice/modelstream/SentenceCommitter.kt", "ui/AgentComposerUiPolicy.kt", "ui/ParagraphSelectingTextView.kt", "ui/ParagraphSelectingEditText.kt",
    "AgentWebReadingWindow.kt", "AgentResearchTrace.kt", "ResearchEvidenceAudit.kt",
    "CloudEvidenceCitations.kt", "ResearchQualityStandard.kt", "CloudWebToolLoopProgress.kt", "CloudWebGrounding.kt", "CloudWeatherLookup.kt", "CloudImageSearchEvidence.kt", "CloudImageAnnotationPlan.kt"
)
val webSlices = listOf("AgentModelSelectionSettings.kt", "MobileAgentConnectors.kt", "AgentWebMediaNativeTools.kt", "AgentNativeToolRegistry.kt",
    "AgentWebIntelligenceNativeTools.kt", "AgentUntrustedEvidenceBoundary.kt", "GalaxySSIApplication.kt", "AgentRemoteOutcomeCodec.kt", "AgentResultReceipt.kt")
val webParserOutput = layout.buildDirectory.dir("generated/phoneWebParser")
val syncPhoneWebParser by tasks.registering {
    inputs.files((webFiles + webSlices).map { phoneWebRoot.resolve(it) })
    outputs.dir(webParserOutput)
    doLast {
        val output = webParserOutput.get().dir("com/galaxyssi/chat").asFile
        output.mkdirs()
        fun write(name: String, text: String) { output.resolve(name).apply { parentFile.mkdirs(); writeText(text) } }
        fun slice(source: String, from: String, until: String): String {
            val start = source.indexOf(from)
            val end = source.indexOf(until, start + 1)
            check(start >= 0 && end > start) { "Android web source boundary changed: $from" }
            return source.substring(start, end)
        }
        // Compile the phone's desktop readiness rules verbatim, including its TTL and clock skew.
        // Keep capability normalization, retired-model filtering and wire fields identical to Android.
        write("AgentInvocationProfile.kt", phoneWebRoot.resolve("AgentModelSelectionSettings.kt").readText()
            .substringBefore("object AgentModelSelectionPolicy {"))
        write("AgentConnectorAvailability.kt", "package com.galaxyssi.chat\nimport org.json.JSONObject\nimport java.util.Locale\n" +
            slice(phoneWebRoot.resolve("MobileAgentConnectors.kt").readText(),
                "object AgentConnectorAvailability {", "    fun cloudModelReady(") + "}\n")
        webFiles.forEach { write(it, phoneWebRoot.resolve(it).readText().let { source ->
            if (it == "CloudWebGrounding.kt") source.replace("package com.galaxyssi.chat", "package com.galaxyssi.chat\nimport com.galaxyssi.watch.R") else source
        }) }
        write("GalaxySSIApplication.kt", phoneWebRoot.resolve("GalaxySSIApplication.kt").readText()
            .replace("class GalaxySSIApplication", "open class GalaxySSIApplication"))
        // The UI response bus below this boundary belongs to the phone; version fencing is shared.
        write("AgentRemoteOutcomeCodec.kt", phoneWebRoot.resolve("AgentRemoteOutcomeCodec.kt").readText()
            .substringBefore("    fun observation(") + "}\n")
        val resultReceipt = phoneWebRoot.resolve("AgentResultReceipt.kt").readText()
        write("AgentResultReceipt.kt", resultReceipt.substringBefore("    fun matches(") +
            "    companion object" + resultReceipt.substringAfter("    companion object"))
        val media = phoneWebRoot.resolve("AgentWebMediaNativeTools.kt").readText()
        val imports = media.lineSequence().filter { it.startsWith("import java.") ||
            it.startsWith("import okhttp3.") || it.startsWith("import org.json.") }.joinToString("\n")
        // The network transport is independent of the later OCR/media/transcoding tools.
        write("WatchSharedWebTransport.kt", "package com.galaxyssi.chat\n$imports\n" +
            slice(media, "enum class AgentWebMethod", "data class AgentContentWriteResult"))
        val registry = phoneWebRoot.resolve("AgentNativeToolRegistry.kt").readText()
        val registryImports = registry.lineSequence().filter { it.startsWith("import ") }.joinToString("\n")
        write("WatchSharedWebPrimitives.kt", "package com.galaxyssi.chat\n$registryImports\n" +
            "typealias AgentNativeJsonObject = Map<String, Any?>\n" +
            slice(registry, "enum class AgentNativeToolAvailabilityStatus", "data class AgentNativePermissionRequirement") +
            slice(registry, "fun interface AgentNativeClock", "class AgentNativeToolInvocation internal constructor") +
            "object AgentNativeJsonCodec" + registry.substringAfter("object AgentNativeJsonCodec"))
        val nativeTools = phoneWebRoot.resolve("AgentWebIntelligenceNativeTools.kt").readText()
        write("WatchSharedWebToolIds.kt", "package com.galaxyssi.chat\n" +
            slice(nativeTools, "object AgentWebIntelligenceNativeTools", "    private const val VERSION") + "}\n")
        val boundary = phoneWebRoot.resolve("AgentUntrustedEvidenceBoundary.kt").readText()
        // secureMessages only adapts the phone planner's message type; all evidence checks are shared.
        write("AgentUntrustedEvidenceBoundary.kt", boundary.substringBefore("    fun secureMessages") +
            "    fun metadata" + boundary.substringAfter("    fun metadata"))
    }
}
android.sourceSets.getByName("main").java.srcDir(webParserOutput)
tasks.named("preBuild").configure { dependsOn(syncPhoneWebParser) }
val syncPhoneRecoveryTests by tasks.registering(Sync::class) {
    from("../../android/app/src/test/java") {
        include("com/galaxyssi/chat/AgentRemoteRecoveryClientTest.kt", "com/galaxyssi/chat/AgentResultRecoveryClientTest.kt")
    }
    into(layout.buildDirectory.dir("generated/phoneRecoveryTests"))
}
android.sourceSets.getByName("test").java.srcDir(syncPhoneRecoveryTests.map { it.destinationDir })
tasks.named("preBuild").configure { dependsOn(syncPhoneRecoveryTests) }

val phoneWebAssets by tasks.registering(Sync::class) {
    from("../../android/app/src/main/assets") { include("web-intelligence/**") }
    into(layout.buildDirectory.dir("generated/phoneWebAssets"))
}
android.sourceSets.getByName("main").assets.srcDir(layout.buildDirectory.dir("generated/phoneWebAssets"))
tasks.named("preBuild").configure { dependsOn(phoneWebAssets) }

android.sourceSets.getByName("main").assets.srcDir(rootProject.file("../desktop/core/galaxyssi-link/backend/research_contract"))
