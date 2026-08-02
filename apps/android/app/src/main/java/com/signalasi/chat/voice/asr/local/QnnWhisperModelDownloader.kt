package com.signalasi.chat.voice.asr.local

import android.util.Log
import com.argmaxinc.whisperkit.huggingface.HuggingFaceApi
import com.argmaxinc.whisperkit.network.ArgmaxModel
import com.argmaxinc.whisperkit.network.ArgmaxModelDownloader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.TimeUnit

internal class QnnWhisperModelDownloader(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.MINUTES)
        .callTimeout(30, TimeUnit.MINUTES)
        .build(),
    private val preferChinaMirror: Boolean = Locale.getDefault().let {
        it.country.equals("CN", ignoreCase = true) || it.language.equals("zh", ignoreCase = true)
    }
) : ArgmaxModelDownloader {
    override fun download(
        model: ArgmaxModel,
        variant: String,
        root: File
    ): Flow<HuggingFaceApi.Progress> = flow {
        require(model == ArgmaxModel.WHISPER) { "Unsupported QNN model type: $model" }
        val assets = manifests[variant]
            ?: error("Unsupported QNN Whisper variant: $variant")
        root.mkdirs()
        assets.forEachIndexed { index, asset ->
            withContext(Dispatchers.IO) { ensureAsset(root, asset) }
            emit(HuggingFaceApi.Progress((index + 1f) / assets.size.toFloat()))
        }
    }

    private fun ensureAsset(root: File, asset: Asset) {
        val destination = File(root, asset.outputName)
        if (destination.matches(asset)) return
        val temporary = File(root, ".${asset.outputName}.part")
        temporary.delete()
        val sources = if (preferChinaMirror) {
            listOf(MIRROR_BASE, OFFICIAL_BASE)
        } else {
            listOf(OFFICIAL_BASE, MIRROR_BASE)
        }
        var lastError: Throwable? = null
        for (base in sources) {
            try {
                download("$base/${asset.repository}/resolve/${asset.revision}/${asset.remotePath}", temporary)
                check(temporary.matches(asset)) {
                    "Integrity verification failed for ${asset.outputName}"
                }
                Files.move(
                    temporary.toPath(),
                    destination.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                    StandardCopyOption.ATOMIC_MOVE
                )
                return
            } catch (error: Throwable) {
                lastError = error
                temporary.delete()
                Log.w(TAG, "QNN model source failed for ${asset.outputName}: $base", error)
            }
        }
        throw IllegalStateException("Unable to download ${asset.outputName}", lastError)
    }

    private fun download(url: String, destination: File) {
        destination.parentFile?.mkdirs()
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "SignalASI-Android/QNN-Whisper")
            .build()
        client.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "HTTP ${response.code} for $url" }
            val body = checkNotNull(response.body) { "Empty response for $url" }
            destination.outputStream().buffered().use { output ->
                body.byteStream().use { input -> input.copyTo(output, 1024 * 1024) }
            }
        }
    }

    private fun File.matches(asset: Asset): Boolean {
        if (!isFile || length() != asset.sizeBytes) return false
        val digest = MessageDigest.getInstance("SHA-256")
        inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                if (read > 0) digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) } == asset.sha256
    }

    private data class Asset(
        val outputName: String,
        val repository: String,
        val revision: String = "main",
        val remotePath: String = outputName,
        val sizeBytes: Long,
        val sha256: String
    )

    private companion object {
        const val TAG = "SignalASIQnnModels"
        const val OFFICIAL_BASE = "https://huggingface.co"
        const val MIRROR_BASE = "https://hf-mirror.com"

        val commonMel = Asset(
            outputName = "MelSpectrogram.tflite",
            repository = "argmaxinc/whisperkit-litert",
            remotePath = "openai_whisper-tiny/MelSpectrogram.tflite",
            sizeBytes = 714_324L,
            sha256 = "71c0c30975ce22c25e9ad17da917420506e99e101c78510acb213586936d26a1"
        )

        val manifests = mapOf(
            "whisperkit-litert/openai_whisper-tiny" to listOf(
                Asset(
                    "config.json",
                    "openai/whisper-tiny",
                    sizeBytes = 1_983L,
                    sha256 = "ffdccec4f3211f4c63310f2b7098f309fe70f3952cedc5e4d11e43f5b2379b98"
                ),
                Asset(
                    "tokenizer.json",
                    "openai/whisper-tiny",
                    sizeBytes = 2_480_466L,
                    sha256 = "27fc476bfe7f17299480be2273fc0608e4d5a99aba2ab5dec5374b4482d1a566"
                ),
                Asset(
                    "AudioEncoder.tflite",
                    "argmaxinc/whisperkit-litert",
                    remotePath = "openai_whisper-tiny/AudioEncoder.tflite",
                    sizeBytes = 37_601_120L,
                    sha256 = "e8b3333d3625da8935ed61d0475cf5e10a6d096008cec128f0262c751a03406a"
                ),
                Asset(
                    "TextDecoder.tflite",
                    "argmaxinc/whisperkit-litert",
                    remotePath = "openai_whisper-tiny/TextDecoder.tflite",
                    sizeBytes = 114_434_792L,
                    sha256 = "86846936c0224e7a567ca5df54edba83fda58ba6e177a35ec63b7838fa255cfb"
                ),
                commonMel
            ),
            "whisperkit-litert/openai_whisper-base" to listOf(
                Asset(
                    "config.json",
                    "openai/whisper-base",
                    sizeBytes = 1_983L,
                    sha256 = "a153c53883a6799b6f056b4a8d1a515c9926d03994682ba88a7616618d7da0c1"
                ),
                Asset(
                    "tokenizer.json",
                    "openai/whisper-base",
                    sizeBytes = 2_480_466L,
                    sha256 = "27fc476bfe7f17299480be2273fc0608e4d5a99aba2ab5dec5374b4482d1a566"
                ),
                Asset(
                    "AudioEncoder.tflite",
                    "argmaxinc/whisperkit-litert",
                    remotePath = "openai_whisper-base/AudioEncoder.tflite",
                    sizeBytes = 95_074_864L,
                    sha256 = "ca946ee8b2fba2ed65529f9e7150391b8b1c8913ccf6d4d20856668db3f1f619"
                ),
                Asset(
                    "TextDecoder.tflite",
                    "argmaxinc/whisperkit-litert",
                    remotePath = "openai_whisper-base/TextDecoder.tflite",
                    sizeBytes = 196_464_156L,
                    sha256 = "ef23a9ebfcd693fed0e9a0906377777e614590a94462c4f6677a03968e56e5a1"
                ),
                commonMel.copy(remotePath = "openai_whisper-base/MelSpectrogram.tflite")
            )
        )
    }
}
