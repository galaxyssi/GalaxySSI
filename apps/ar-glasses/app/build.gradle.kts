import java.net.URI
import java.security.MessageDigest

plugins {
    id("com.android.application")
    kotlin("android")
}

// Keep English Vosk for continuous wake detection; multilingual Whisper Tiny decodes utterances.
val englishModelHash = "30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498"
val tinyModelHash = "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7"
val tinyModelName = "ggml-tiny-q5_1.bin"
val modelAssets = layout.buildDirectory.dir("generated/modelAssets")
val prepareSpeechModel by tasks.registering {
    inputs.property("englishModelHash", englishModelHash)
    inputs.property("tinyModelHash", tinyModelHash)
    outputs.dir(modelAssets)
    doLast {
        fun sha256(file: File) = MessageDigest.getInstance("SHA-256")
            .digest(file.readBytes()).joinToString("") { "%02x".format(it) }
        fun prepare(name: String, hash: String) {
            val cached = File(gradle.gradleUserHomeDir, "caches/galaxyssi-models/$hash.zip")
            if (!cached.isFile || sha256(cached) != hash) {
                cached.parentFile.mkdirs()
                val part = File(cached.parentFile, "$hash.partial")
                val source = URI("https://alphacephei.com/vosk/models/$name.zip").toURL().openConnection()
                source.connectTimeout = 30000
                source.readTimeout = 120000
                source.getInputStream().use { input -> part.outputStream().use { input.copyTo(it) } }
                check(sha256(part) == hash) { "$name checksum mismatch" }
                check(part.renameTo(cached)) { "Cannot cache $name" }
            }
            val target = modelAssets.get().file("$name.zip").asFile
            target.parentFile.mkdirs()
            cached.copyTo(target, overwrite = true)
        }
        prepare("vosk-model-small-en-us-0.15", englishModelHash)
        val cachedTiny = File(gradle.gradleUserHomeDir, "caches/galaxyssi-models/$tinyModelHash.bin")
        if (!cachedTiny.isFile || sha256(cachedTiny) != tinyModelHash) {
            cachedTiny.parentFile.mkdirs()
            val part = File(cachedTiny.parentFile, "$tinyModelHash.partial")
            val modelPath = "ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/$tinyModelName"
            var downloadError: Exception? = null
            for (host in listOf("huggingface.co", "hf-mirror.com")) {
                try {
                    val source = URI("https://$host/$modelPath").toURL().openConnection()
                    source.connectTimeout = 10000
                    source.readTimeout = 120000
                    source.getInputStream().use { input -> part.outputStream().use { input.copyTo(it) } }
                    downloadError = null
                    break
                } catch (error: Exception) { downloadError = error }
            }
            if (downloadError != null) throw downloadError
            check(part.length() == 32152673L && sha256(part) == tinyModelHash) { "Whisper Tiny checksum mismatch" }
            check(part.renameTo(cachedTiny)) { "Cannot cache Whisper Tiny" }
        }
        cachedTiny.copyTo(modelAssets.get().file(tinyModelName).asFile, overwrite = true)
    }
}

android {
    namespace = "com.galaxyssi.glasses"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.galaxyssi.glasses"
        minSdk = 30
        targetSdk = 35
        versionCode = 15
        versionName = "0.3.10"
        ndk { abiFilters += "armeabi-v7a" }
        testInstrumentationRunner = "com.galaxyssi.glasses.WhisperSmokeInstrumentation"
    }
    sourceSets["main"].assets.srcDir(modelAssets)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    packaging { jniLibs.useLegacyPackaging = true }
    ndkVersion = "29.0.13113456"
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
}
tasks.named("preBuild").configure { dependsOn(prepareSpeechModel) }

dependencies {
    val cameraX = "1.5.3"
    implementation("androidx.activity:activity:1.12.3")
    implementation("androidx.camera:camera-core:$cameraX")
    implementation("androidx.camera:camera-camera2:$cameraX")
    implementation("androidx.camera:camera-lifecycle:$cameraX")
    implementation("androidx.camera:camera-view:$cameraX")
    implementation("androidx.camera:camera-video:$cameraX")
    implementation("com.google.zxing:core:3.5.3")
    implementation("com.alphacephei:vosk-android:0.3.75@aar")
    implementation("net.java.dev.jna:jna:5.18.1@aar")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
