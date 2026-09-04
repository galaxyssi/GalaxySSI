package com.galaxyssi.chat.voice.asr.local

import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.URI
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max

enum class QnnModelDownloadNetworkPolicy {
    WIFI_ONLY,
    ANY_VALIDATED_NETWORK
}

fun interface QnnModelDownloadNetworkGate {
    fun isAllowed(policy: QnnModelDownloadNetworkPolicy): Boolean
}

fun interface QnnModelDownloadCancellation {
    fun isCancellationRequested(): Boolean

    companion object {
        val NONE = QnnModelDownloadCancellation { false }
    }
}

enum class QnnModelDownloadPhase {
    ARCHIVE,
    SUPPORT_ASSET,
    VERIFYING
}

data class QnnModelDownloadProgress(
    val phase: QnnModelDownloadPhase,
    val assetName: String,
    val downloadedBytes: Long,
    val totalBytes: Long,
    val aggregateDownloadedBytes: Long,
    val aggregateTotalBytes: Long,
    val resumed: Boolean
) {
    val percent: Int
        get() = if (aggregateTotalBytes <= 0L) 0 else
            ((aggregateDownloadedBytes * 100L) / aggregateTotalBytes).toInt().coerceIn(0, 100)
}

data class QnnContextModelDownloadResult(
    val archive: File,
    val archiveSha256: String,
    val supportAssets: Map<String, File>,
    val resumed: Boolean
)

class QnnModelDownloadException(message: String, cause: Throwable? = null) : Exception(message, cause)
class QnnModelDownloadCancelledException : Exception("QNN ASR model download was cancelled")

class LargeTurboQnnModelDownloader(
    private val root: File,
    private val networkGate: QnnModelDownloadNetworkGate = QnnModelDownloadNetworkGate { true },
    private val client: OkHttpClient = OkHttpClient.Builder()
        .followRedirects(false)
        .followSslRedirects(false)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS)
        .callTimeout(90, TimeUnit.MINUTES)
        .build(),
    private val sourceUrlResolver: (String) -> String = { it },
    private val allowInsecureLoopbackForTests: Boolean = false
) {
    private val activeCall = AtomicReference<Call?>(null)

    init {
        check(root.mkdirs() || root.isDirectory) { "QNN ASR download storage is unavailable" }
    }

    fun download(
        manifest: LargeTurboQnnModelManifest,
        networkPolicy: QnnModelDownloadNetworkPolicy,
        cancellation: QnnModelDownloadCancellation = QnnModelDownloadCancellation.NONE,
        onProgress: (QnnModelDownloadProgress) -> Unit = {}
    ): QnnContextModelDownloadResult {
        requireNetwork(networkPolicy)
        val totalBytes = manifest.archive.sizeBytes + manifest.supportAssets.sumOf(QnnContextSupportAsset::downloadSizeBytes)
        var aggregateBase = 0L
        val archive = downloadOne(
            key = "${manifest.modelId}-${manifest.releaseVersion}-archive",
            displayName = "model.zip",
            sourceUrl = manifest.archive.sourceUrl,
            expectedSize = manifest.archive.sizeBytes,
            expectedSha256 = manifest.archive.sha256,
            expectedEtag = manifest.archive.etag,
            expectedCrc64Nvme = manifest.archive.crc64NvmeBase64,
            phase = QnnModelDownloadPhase.ARCHIVE,
            aggregateBase = aggregateBase,
            aggregateTotal = totalBytes,
            networkPolicy = networkPolicy,
            cancellation = cancellation,
            onProgress = onProgress
        )
        aggregateBase += manifest.archive.sizeBytes
        val support = linkedMapOf<String, File>()
        var resumed = archive.resumed
        manifest.supportAssets.forEach { asset ->
            val result = downloadOne(
                key = "${manifest.modelId}-${manifest.releaseVersion}-${asset.installedName}",
                displayName = asset.installedName,
                sourceUrl = asset.sourceUrl,
                expectedSize = asset.downloadSizeBytes,
                expectedSha256 = asset.sha256,
                expectedEtag = "",
                expectedCrc64Nvme = "",
                phase = QnnModelDownloadPhase.SUPPORT_ASSET,
                aggregateBase = aggregateBase,
                aggregateTotal = totalBytes,
                networkPolicy = networkPolicy,
                cancellation = cancellation,
                onProgress = onProgress
            )
            support[asset.installedName] = result.file
            aggregateBase += asset.downloadSizeBytes
            resumed = resumed || result.resumed
        }
        onProgress(QnnModelDownloadProgress(
            phase = QnnModelDownloadPhase.VERIFYING,
            assetName = manifest.displayName,
            downloadedBytes = totalBytes,
            totalBytes = totalBytes,
            aggregateDownloadedBytes = totalBytes,
            aggregateTotalBytes = totalBytes,
            resumed = resumed
        ))
        return QnnContextModelDownloadResult(archive.file, archive.sha256, support, resumed)
    }

    fun cancelActiveDownload() {
        activeCall.getAndSet(null)?.cancel()
    }

    private fun downloadOne(
        key: String,
        displayName: String,
        sourceUrl: String,
        expectedSize: Long,
        expectedSha256: String?,
        expectedEtag: String,
        expectedCrc64Nvme: String,
        phase: QnnModelDownloadPhase,
        aggregateBase: Long,
        aggregateTotal: Long,
        networkPolicy: QnnModelDownloadNetworkPolicy,
        cancellation: QnnModelDownloadCancellation,
        onProgress: (QnnModelDownloadProgress) -> Unit
    ): DownloadedFile {
        require(expectedSize > 0L)
        require(expectedSha256 == null || expectedSha256.matches(SHA256_PATTERN))
        val safeKey = key.replace(Regex("[^A-Za-z0-9._-]"), "_").take(160)
        val completed = File(root, "$safeKey.complete")
        val receipt = File(root, "$safeKey.complete.json")
        val partial = File(root, "$safeKey.partial")
        val resumeFile = File(root, "$safeKey.partial.json")

        readCompletedReceipt(receipt)?.takeIf { saved ->
            completed.isFile && completed.length() == expectedSize && saved.sourceUrl == sourceUrl &&
                saved.sizeBytes == expectedSize &&
                (expectedSha256 == null || saved.sha256.equals(expectedSha256, ignoreCase = true)) &&
                sha256(completed).equals(saved.sha256, ignoreCase = true)
        }?.let { saved -> return DownloadedFile(completed, saved.sha256, resumed = false) }
        completed.delete()
        receipt.delete()

        val saved = readResume(resumeFile)
        if (saved == null || saved.sourceUrl != sourceUrl || saved.sizeBytes != expectedSize ||
            (expectedSha256 != null && !saved.expectedSha256.equals(expectedSha256, ignoreCase = true))
        ) {
            partial.delete()
            resumeFile.delete()
        }
        var offset = partial.length()
        if (offset !in 0..expectedSize) {
            partial.delete()
            offset = 0L
        }
        ensureSpace(expectedSize - offset)
        var resumeEtag = readResume(resumeFile)?.etag.orEmpty()
        var resumed = offset > 0L
        var attempts = 0
        while (offset < expectedSize) {
            checkpoint(cancellation)
            requireNetwork(networkPolicy)
            val response = openResponse(sourceUrl, offset, resumeEtag, cancellation)
            try {
                response.use { active ->
                    if (active.code == 416 && offset == expectedSize) return@use
                    if (active.code !in setOf(200, 206)) {
                        throw QnnModelDownloadException("Model download returned HTTP ${active.code}")
                    }
                    val append = if (active.code == 206) {
                        val range = parseContentRange(active.header("Content-Range"))
                            ?: throw QnnModelDownloadException("Model source returned an invalid Content-Range")
                        if (range.first != offset || range.total != expectedSize) {
                            throw QnnModelDownloadException("Model source returned a mismatched resume range")
                        }
                        offset > 0L
                    } else {
                        if (offset > 0L) {
                            partial.delete()
                            offset = 0L
                            resumed = false
                        }
                        false
                    }
                    val etag = active.header("ETag").orEmpty().take(MAX_HEADER_CHARS)
                    if (expectedEtag.isNotBlank() && etag.isNotBlank() && etag != expectedEtag) {
                        throw QnnModelDownloadException("Official model archive changed without a manifest update")
                    }
                    if (append && resumeEtag.isNotBlank() && etag.isNotBlank() && etag != resumeEtag) {
                        throw QnnModelDownloadException("Model archive changed while resuming")
                    }
                    active.header("x-amz-checksum-crc64nvme")?.takeIf(String::isNotBlank)?.let { checksum ->
                        if (expectedCrc64Nvme.isNotBlank() && checksum != expectedCrc64Nvme) {
                            throw QnnModelDownloadException("Official model archive checksum metadata changed")
                        }
                    }
                    resumeEtag = etag
                    writeResume(resumeFile, ResumeRecord(sourceUrl, expectedSize, expectedSha256.orEmpty(), etag))
                    val body = active.body ?: throw QnnModelDownloadException("Model download body is empty")
                    FileOutputStream(partial, append).buffered(BUFFER_BYTES).use { output ->
                        body.byteStream().buffered(BUFFER_BYTES).use { input ->
                            val buffer = ByteArray(BUFFER_BYTES)
                            var downloaded = if (append) offset else 0L
                            var sinceNetworkCheck = 0L
                            while (true) {
                                checkpoint(cancellation)
                                val read = input.read(buffer)
                                if (read < 0) break
                                downloaded += read
                                sinceNetworkCheck += read
                                if (downloaded > expectedSize) {
                                    throw QnnModelDownloadException("Model source exceeded its manifest size")
                                }
                                output.write(buffer, 0, read)
                                if (sinceNetworkCheck >= NETWORK_RECHECK_BYTES) {
                                    requireNetwork(networkPolicy)
                                    sinceNetworkCheck = 0L
                                }
                                onProgress(QnnModelDownloadProgress(
                                    phase = phase,
                                    assetName = displayName,
                                    downloadedBytes = downloaded,
                                    totalBytes = expectedSize,
                                    aggregateDownloadedBytes = aggregateBase + downloaded,
                                    aggregateTotalBytes = aggregateTotal,
                                    resumed = resumed
                                ))
                            }
                        }
                    }
                }
            } finally {
                activeCall.getAndSet(null)
            }
            offset = partial.length()
            if (offset == expectedSize) break
            if (offset <= 0L || ++attempts >= MAX_RESUME_ATTEMPTS) {
                throw QnnModelDownloadException("Model download ended before the expected size")
            }
            resumed = true
        }
        checkpoint(cancellation)
        if (partial.length() != expectedSize) throw QnnModelDownloadException("Downloaded model size is invalid")
        val digest = sha256(partial)
        if (expectedSha256 != null && !digest.equals(expectedSha256, ignoreCase = true)) {
            partial.delete()
            resumeFile.delete()
            throw QnnModelDownloadException("Downloaded model SHA-256 verification failed")
        }
        atomicMove(partial, completed)
        resumeFile.delete()
        writeCompletedReceipt(receipt, CompletedReceipt(sourceUrl, expectedSize, digest))
        return DownloadedFile(completed, digest, resumed)
    }

    private fun openResponse(
        initialUrl: String,
        offset: Long,
        etag: String,
        cancellation: QnnModelDownloadCancellation
    ): Response {
        var current = sourceUrlResolver(initialUrl)
        repeat(MAX_REDIRECTS + 1) { redirectCount ->
            validateUrl(current)
            val request = Request.Builder()
                .url(current)
                .header("User-Agent", "GalaxySSI-Android/QNN-Large-Turbo")
                .header("Accept-Encoding", "identity")
                .header("x-amz-checksum-mode", "ENABLED")
                .apply {
                    if (offset > 0L) {
                        header("Range", "bytes=$offset-")
                        if (etag.isNotBlank()) header("If-Range", etag)
                    }
                }
                .build()
            checkpoint(cancellation)
            val call = client.newCall(request)
            activeCall.set(call)
            val response = try {
                call.execute()
            } catch (error: Throwable) {
                activeCall.compareAndSet(call, null)
                throw error
            }
            if (response.code in REDIRECT_CODES) {
                if (redirectCount >= MAX_REDIRECTS) {
                    response.close()
                    activeCall.compareAndSet(call, null)
                    throw QnnModelDownloadException("Model download has too many redirects")
                }
                val location = response.header("Location")
                response.close()
                activeCall.compareAndSet(call, null)
                if (location.isNullOrBlank()) throw QnnModelDownloadException("Model redirect is missing a location")
                current = URI(current).resolve(location).toString()
                return@repeat
            }
            return response
        }
        throw QnnModelDownloadException("Model download redirect failed")
    }

    private fun validateUrl(value: String) {
        val uri = runCatching { URI(value) }.getOrElse { throw QnnModelDownloadException("Model URL is invalid", it) }
        if (allowInsecureLoopbackForTests && uri.scheme == "http" && uri.host in setOf("127.0.0.1", "localhost")) return
        if (!uri.scheme.equals("https", ignoreCase = true) || uri.host.isNullOrBlank() || uri.userInfo != null) {
            throw QnnModelDownloadException("Model URL must use HTTPS")
        }
        val host = uri.host.lowercase(Locale.ROOT)
        if (host !in TRUSTED_HOSTS && TRUSTED_HOST_SUFFIXES.none(host::endsWith)) {
            throw QnnModelDownloadException("Model URL host is not trusted")
        }
    }

    private fun requireNetwork(policy: QnnModelDownloadNetworkPolicy) {
        if (!networkGate.isAllowed(policy)) {
            val detail = if (policy == QnnModelDownloadNetworkPolicy.WIFI_ONLY) {
                "Connect to Wi-Fi to download the local ASR model"
            } else {
                "A validated network is required to download the local ASR model"
            }
            throw QnnModelDownloadException(detail)
        }
    }

    private fun checkpoint(cancellation: QnnModelDownloadCancellation) {
        if (cancellation.isCancellationRequested()) throw QnnModelDownloadCancelledException()
    }

    private fun ensureSpace(remainingBytes: Long) {
        val required = max(0L, remainingBytes) + MIN_FREE_DOWNLOAD_BYTES
        if (root.usableSpace in 0 until required) {
            throw QnnModelDownloadException("Not enough storage to download the local ASR model")
        }
    }

    private fun parseContentRange(value: String?): ContentRange? {
        val match = CONTENT_RANGE_PATTERN.matchEntire(value.orEmpty()) ?: return null
        val first = match.groupValues[1].toLongOrNull() ?: return null
        val last = match.groupValues[2].toLongOrNull() ?: return null
        val total = match.groupValues[3].toLongOrNull() ?: return null
        if (first < 0L || last < first || total <= last) return null
        return ContentRange(first, last, total)
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered(BUFFER_BYTES).use { input ->
            val buffer = ByteArray(BUFFER_BYTES)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun readResume(file: File): ResumeRecord? = runCatching {
        val value = JSONObject(file.readText(Charsets.UTF_8))
        ResumeRecord(
            sourceUrl = value.getString("source_url"),
            sizeBytes = value.getLong("size_bytes"),
            expectedSha256 = value.optString("expected_sha256"),
            etag = value.optString("etag")
        )
    }.getOrNull()

    private fun writeResume(file: File, value: ResumeRecord) = writeJsonAtomically(file, JSONObject()
        .put("source_url", value.sourceUrl)
        .put("size_bytes", value.sizeBytes)
        .put("expected_sha256", value.expectedSha256)
        .put("etag", value.etag))

    private fun readCompletedReceipt(file: File): CompletedReceipt? = runCatching {
        val value = JSONObject(file.readText(Charsets.UTF_8))
        CompletedReceipt(
            sourceUrl = value.getString("source_url"),
            sizeBytes = value.getLong("size_bytes"),
            sha256 = value.getString("sha256")
        )
    }.getOrNull()

    private fun writeCompletedReceipt(file: File, value: CompletedReceipt) = writeJsonAtomically(file, JSONObject()
        .put("source_url", value.sourceUrl)
        .put("size_bytes", value.sizeBytes)
        .put("sha256", value.sha256))

    private fun writeJsonAtomically(file: File, value: JSONObject) {
        val temporary = File(file.parentFile, ".${file.name}.tmp")
        temporary.writeText(value.toString(), Charsets.UTF_8)
        atomicMove(temporary, file)
    }

    private fun atomicMove(source: File, target: File) {
        try {
            Files.move(source.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private data class DownloadedFile(val file: File, val sha256: String, val resumed: Boolean)
    private data class ResumeRecord(
        val sourceUrl: String,
        val sizeBytes: Long,
        val expectedSha256: String,
        val etag: String
    )
    private data class CompletedReceipt(val sourceUrl: String, val sizeBytes: Long, val sha256: String)
    private data class ContentRange(val first: Long, val last: Long, val total: Long)

    private companion object {
        const val BUFFER_BYTES = 256 * 1024
        const val NETWORK_RECHECK_BYTES = 8L * 1024L * 1024L
        const val MIN_FREE_DOWNLOAD_BYTES = 512L * 1024L * 1024L
        const val MAX_RESUME_ATTEMPTS = 8
        const val MAX_REDIRECTS = 5
        const val MAX_HEADER_CHARS = 512
        val SHA256_PATTERN = Regex("[a-fA-F0-9]{64}")
        val CONTENT_RANGE_PATTERN = Regex("bytes ([0-9]+)-([0-9]+)/([0-9]+)")
        val REDIRECT_CODES = setOf(301, 302, 303, 307, 308)
        val TRUSTED_HOSTS = setOf(
            "qaihub-public-assets.s3.us-west-2.amazonaws.com",
            "raw.githubusercontent.com",
            "huggingface.co",
            "cdn-lfs.huggingface.co"
        )
        val TRUSTED_HOST_SUFFIXES = setOf(".huggingface.co", ".hf.co")
    }
}
