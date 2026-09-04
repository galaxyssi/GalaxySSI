package com.galaxyssi.chat.voice.asr.local

import android.content.res.AssetManager
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Locale

internal data class QnnContextWrapperAsset(
    val assetPath: String,
    val installedName: String,
    val sizeBytes: Long,
    val sha256: String
) {
    init {
        require(assetPath.isNotBlank() && !assetPath.startsWith('/') && !assetPath.contains(".."))
        require(installedName.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")))
        require(sizeBytes > 0L)
        require(sha256.matches(Regex("[a-f0-9]{64}")))
    }
}

internal fun interface QnnContextAssetSource {
    fun open(path: String): InputStream
}

internal class AndroidQnnContextAssetSource(private val assets: AssetManager) : QnnContextAssetSource {
    override fun open(path: String): InputStream = assets.open(path, AssetManager.ACCESS_STREAMING)
}

internal class WhisperQnnContextAssetInstaller(
    private val source: QnnContextAssetSource,
    private val assets: List<QnnContextWrapperAsset> = WhisperQnnContextAssets.all
) {
    fun ensureInstalled(modelDirectory: File): Map<String, File> {
        val canonicalDirectory = modelDirectory.canonicalFile
        require(canonicalDirectory.isDirectory && canonicalDirectory.canRead() && canonicalDirectory.canWrite()) {
            "QNN ASR model directory is not writable"
        }
        require(assets.isNotEmpty() && assets.map(QnnContextWrapperAsset::installedName).distinct().size == assets.size)
        return assets.associate { asset ->
            asset.installedName to ensureAsset(canonicalDirectory, asset)
        }
    }

    private fun ensureAsset(directory: File, asset: QnnContextWrapperAsset): File {
        val destination = secureChild(directory, asset.installedName)
        if (isValid(destination, asset)) return destination

        val temporary = secureChild(directory, "tmp-${asset.installedName}-${System.nanoTime()}.part")
        try {
            source.open(asset.assetPath).buffered(BUFFER_BYTES).use { input ->
                FileOutputStream(temporary).use { output ->
                    input.copyTo(output, BUFFER_BYTES)
                    output.fd.sync()
                }
            }
            require(isValid(temporary, asset)) { "Packaged QNN context wrapper verification failed" }
            atomicMove(temporary, destination)
            require(isValid(destination, asset)) { "Installed QNN context wrapper verification failed" }
            return destination
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    private fun isValid(file: File, asset: QnnContextWrapperAsset): Boolean =
        file.isFile && file.length() == asset.sizeBytes && sha256(file) == asset.sha256

    private fun secureChild(parent: File, name: String): File {
        require(name.matches(SAFE_NAME))
        val child = File(parent, name).canonicalFile
        require(child.parentFile == parent.canonicalFile) { "QNN wrapper path escaped the model directory" }
        return child
    }

    private fun atomicMove(source: File, target: File) {
        try {
            Files.move(source.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered(BUFFER_BYTES).use { input ->
            val buffer = ByteArray(BUFFER_BYTES)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                if (read > 0) digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(Locale.ROOT, byte) }
    }

    private companion object {
        const val BUFFER_BYTES = 64 * 1024
        val SAFE_NAME = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
    }
}

internal object WhisperQnnContextAssets {
    private const val ROOT = "voice/qnn/whisper-large-v3-turbo-s26u"

    val encoder = QnnContextWrapperAsset(
        assetPath = "$ROOT/encoder_context.onnx",
        installedName = WhisperLargeTurboQnnContract.encoder.wrapperModelName,
        sizeBytes = 866L,
        sha256 = "77ca1586db42df9cbd116cfd9002bda12627f0804c81d8c92eddeb5027a3bf42"
    )

    val decoder = QnnContextWrapperAsset(
        assetPath = "$ROOT/decoder_context.onnx",
        installedName = WhisperLargeTurboQnnContract.decoder.wrapperModelName,
        sizeBytes = 2_051L,
        sha256 = "0b9992323e509572783a4f014d88ac0d19629dde724c3b4c894591d44c167445"
    )

    val all = listOf(encoder, decoder)
}
