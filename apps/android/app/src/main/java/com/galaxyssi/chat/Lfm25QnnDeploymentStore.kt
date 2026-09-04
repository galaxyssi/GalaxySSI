package com.galaxyssi.chat

import android.content.Context
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

internal fun interface Lfm25QnnDeploymentSignatureVerifier {
    fun verify(manifest: Lfm25QnnDeploymentManifest): Boolean
}

internal data class Lfm25QnnRuntimeArtifact(
    val modelPath: String,
    val tokenizerPath: String,
    val runtimeId: String,
    val manifest: Lfm25QnnDeploymentManifest
)

internal class AndroidLfm25QnnDeploymentSignatureVerifier(context: Context) :
    Lfm25QnnDeploymentSignatureVerifier {
    private val verifier = AndroidRuntimePayloadVerifier(context)

    override fun verify(manifest: Lfm25QnnDeploymentManifest): Boolean = verifier.verify(
        manifest.signatureKeyId,
        manifest.signature,
        manifest.signingPayload()
    )
}

internal class Lfm25QnnDeploymentStore private constructor(
    private val root: File,
    private val signatureVerifier: Lfm25QnnDeploymentSignatureVerifier
) {
    constructor(context: Context) : this(
        File(context.applicationContext.noBackupFilesDir, ROOT_DIRECTORY),
        AndroidLfm25QnnDeploymentSignatureVerifier(context.applicationContext)
    )

    fun install(packageInput: InputStream, onBytesCopied: (Long) -> Unit = {}): LocalModelRuntimeProfile {
        root.mkdirs()
        require(root.isDirectory)
        val staging = File(root, ".staging-${UUID.randomUUID()}")
        require(staging.mkdirs()) { "Unable to create QNN deployment staging directory" }
        try {
            val extracted = extract(packageInput, staging, onBytesCopied)
            val manifestFile = File(staging, Lfm25QnnDeploymentManifest.MANIFEST_FILE_NAME)
            require(manifestFile.isFile) { "The QNN package has no deployment manifest" }
            val manifest = Lfm25QnnDeploymentManifest.parse(manifestFile.readText(Charsets.UTF_8))
            require(signatureVerifier.verify(manifest)) { "The QNN deployment signature is not trusted" }
            verifyExtractedArtifacts(staging, manifest, extracted)
            commitStaging(staging)
            return manifest.toRuntimeProfile()
        } catch (error: Throwable) {
            safeDelete(staging)
            throw error
        }
    }

    fun installedManifest(): Lfm25QnnDeploymentManifest? = runCatching {
        val directory = installationDirectory()
        val manifestFile = File(directory, Lfm25QnnDeploymentManifest.MANIFEST_FILE_NAME)
        if (!manifestFile.isFile) return@runCatching null
        val manifest = Lfm25QnnDeploymentManifest.parse(manifestFile.readText(Charsets.UTF_8))
        require(signatureVerifier.verify(manifest))
        manifest.files.forEach { declared ->
            val file = resolveInside(directory, declared.path)
            require(file.isFile && file.length() == declared.sizeBytes)
        }
        manifest
    }.getOrNull()

    fun isInstalled(profile: LocalModelRuntimeProfile): Boolean =
        LocalModelQnnMemoryPolicy.appliesTo(profile) && installedManifest()?.modelId == profile.id

    fun partialDownloadFile(): File {
        root.mkdirs()
        require(root.isDirectory)
        return File(root, PARTIAL_DOWNLOAD_FILE_NAME)
    }

    fun partialDownloadBytes(): Long = partialDownloadFile().length().coerceAtLeast(0L)

    fun availableBytes(): Long {
        root.mkdirs()
        return root.usableSpace
    }

    fun requiredDownloadBytes(estimatedArchiveBytes: Long): Long {
        val remainingArchive = (estimatedArchiveBytes - partialDownloadBytes()).coerceAtLeast(0L)
        val extractionBytes = estimatedArchiveBytes.coerceAtMost(Lfm25QnnDeploymentManifest.MAX_INSTALLED_BYTES)
        return safeAdd(safeAdd(remainingArchive, extractionBytes), MINIMUM_FREE_SPACE_BYTES)
    }

    fun deletePartialDownload() {
        safeDelete(partialDownloadFile())
    }

    fun runtimeArtifact(profile: LocalModelRuntimeProfile): Lfm25QnnRuntimeArtifact {
        require(LocalModelQnnMemoryPolicy.appliesTo(profile))
        val manifest = requireNotNull(installedManifest()) {
            "The signed LFM2.5 QNN deployment is not installed"
        }
        val directory = installationDirectory()
        val model = manifest.resolveModelPath(directory)
        val tokenizer = manifest.resolveTokenizerPath(directory)
        require(model.exists()) { "The LFM2.5 QNN model path is missing" }
        require(tokenizer.isFile) { "The LFM2.5 tokenizer is missing" }
        return Lfm25QnnRuntimeArtifact(
            modelPath = model.absolutePath,
            tokenizerPath = tokenizer.absolutePath,
            runtimeId = manifest.runtimeId,
            manifest = manifest
        )
    }

    fun delete() {
        safeDelete(installationDirectory())
        safeDelete(partialDownloadFile())
    }

    private fun extract(
        input: InputStream,
        staging: File,
        onBytesCopied: (Long) -> Unit
    ): Map<String, ExtractedArtifact> {
        val extracted = linkedMapOf<String, ExtractedArtifact>()
        var totalBytes = 0L
        ZipInputStream(BufferedInputStream(input, COPY_BUFFER_BYTES)).use { zip ->
            var entry: ZipEntry? = zip.nextEntry
            while (entry != null) {
                val path = normalizedPath(entry.name)
                if (path.isNotBlank() && !entry.isDirectory) {
                    require(path !in extracted) { "Duplicate QNN deployment file: $path" }
                    require(extracted.size < MAX_PACKAGE_ENTRIES) { "The QNN package contains too many files" }
                    val output = resolveInside(staging, path)
                    output.parentFile?.mkdirs()
                    val digest = MessageDigest.getInstance("SHA-256")
                    var fileBytes = 0L
                    FileOutputStream(output).buffered(COPY_BUFFER_BYTES).use { destination ->
                        val buffer = ByteArray(COPY_BUFFER_BYTES)
                        while (true) {
                            val count = zip.read(buffer)
                            if (count < 0) break
                            fileBytes += count
                            totalBytes += count
                            require(fileBytes <= MAX_SINGLE_FILE_BYTES &&
                                totalBytes <= Lfm25QnnDeploymentManifest.MAX_INSTALLED_BYTES + MAX_MANIFEST_BYTES
                            ) { "The QNN deployment package exceeds its size limit" }
                            digest.update(buffer, 0, count)
                            destination.write(buffer, 0, count)
                            onBytesCopied(totalBytes)
                        }
                    }
                    extracted[path] = ExtractedArtifact(
                        sizeBytes = fileBytes,
                        sha256 = digest.digest().toHex()
                    )
                }
                zip.closeEntry()
                entry = zip.nextEntry
            }
        }
        return extracted
    }

    private fun verifyExtractedArtifacts(
        staging: File,
        manifest: Lfm25QnnDeploymentManifest,
        extracted: Map<String, ExtractedArtifact>
    ) {
        val expectedPaths = manifest.files.mapTo(linkedSetOf(), Lfm25QnnDeploymentFile::path)
        val actualPaths = extracted.keys - Lfm25QnnDeploymentManifest.MANIFEST_FILE_NAME
        require(actualPaths == expectedPaths) { "The QNN package file list does not match its signed manifest" }
        manifest.files.forEach { declared ->
            val actual = requireNotNull(extracted[declared.path])
            require(actual.sizeBytes == declared.sizeBytes) { "Wrong size for ${declared.path}" }
            require(actual.sha256 == declared.sha256) { "SHA-256 mismatch for ${declared.path}" }
            require(resolveInside(staging, declared.path).isFile)
        }
    }

    private fun installationDirectory(): File = File(root, Lfm25QnnDeploymentManifest.MODEL_ID)

    private fun commitStaging(staging: File) {
        val destination = installationDirectory()
        val previous = File(root, ".previous-${Lfm25QnnDeploymentManifest.MODEL_ID}")
        safeDelete(previous)
        if (destination.exists()) {
            require(destination.renameTo(previous)) { "Unable to preserve the installed QNN deployment" }
        }
        if (!staging.renameTo(destination)) {
            if (previous.exists()) previous.renameTo(destination)
            error("Unable to commit the QNN deployment package")
        }
        safeDelete(previous)
    }

    private fun safeDelete(target: File) {
        val canonicalRoot = root.canonicalFile
        val canonicalTarget = target.canonicalFile
        require(canonicalTarget.parentFile == canonicalRoot) { "Refusing to delete outside the QNN model store" }
        if (canonicalTarget.exists()) require(canonicalTarget.deleteRecursively())
    }

    private data class ExtractedArtifact(val sizeBytes: Long, val sha256: String)

    companion object {
        internal fun forTesting(
            root: File,
            signatureVerifier: Lfm25QnnDeploymentSignatureVerifier
        ): Lfm25QnnDeploymentStore = Lfm25QnnDeploymentStore(root, signatureVerifier)

        private const val ROOT_DIRECTORY = "local-model-qnn"
        private const val PARTIAL_DOWNLOAD_FILE_NAME = "lfm2.5-2.6b-qnn-w4a8-sm8850.zip.part"
        private const val COPY_BUFFER_BYTES = 1024 * 1024
        private const val MAX_PACKAGE_ENTRIES = 96
        private const val MAX_SINGLE_FILE_BYTES = 3L * 1024L * 1024L * 1024L
        private const val MAX_MANIFEST_BYTES = 256L * 1024L
        private const val MINIMUM_FREE_SPACE_BYTES = 512L * 1024L * 1024L

        private fun safeAdd(left: Long, right: Long): Long =
            if (Long.MAX_VALUE - left < right) Long.MAX_VALUE else left + right
    }
}

private fun normalizedPath(value: String): String = value.replace('\\', '/').trim('/')

private fun resolveInside(root: File, relativePath: String): File {
    val canonicalRoot = root.canonicalFile
    val candidate = File(canonicalRoot, relativePath).canonicalFile
    require(candidate.path.startsWith(canonicalRoot.path + File.separator)) {
        "QNN deployment path escapes its staging directory"
    }
    return candidate
}

private fun ByteArray.toHex(): String = joinToString("") { byte ->
    String.format(Locale.ROOT, "%02x", byte.toInt() and 0xff)
}
