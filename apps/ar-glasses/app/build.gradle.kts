import java.net.URI
import java.security.MessageDigest

plugins {
    id("com.android.application")
    kotlin("android")
}

// The device has no public RecognitionService. Bundle a checksum-pinned offline
// Mandarin model so microphone input still works without a cloud ASR account.
val modelHash = "3af8b0e7e0f835ae9d414ce5df580237a3cfb08d586c9fbbb0f7ff29ad5b14ba"
val englishModelHash = "30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498"
val modelAssets = layout.buildDirectory.dir("generated/modelAssets")
val prepareSpeechModel by tasks.registering {
    inputs.property("modelHash", modelHash)
    inputs.property("englishModelHash", englishModelHash)
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
        prepare("vosk-model-small-cn-0.22", modelHash)
        prepare("vosk-model-small-en-us-0.15", englishModelHash)
    }
}

android {
    namespace = "com.galaxyssi.glasses"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.galaxyssi.glasses"
        minSdk = 30
        targetSdk = 35
        versionCode = 4
        versionName = "0.2.1"
    }
    sourceSets["main"].assets.srcDir(modelAssets)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    packaging { jniLibs.useLegacyPackaging = true }
}
tasks.named("preBuild").configure { dependsOn(prepareSpeechModel) }

dependencies {
    implementation("com.alphacephei:vosk-android:0.3.75@aar")
    implementation("net.java.dev.jna:jna:5.18.1@aar")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
