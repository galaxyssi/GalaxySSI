package com.galaxyssi.chat.voice.asr.local

import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.ZipFile

enum class QnnContextModelState {
    NOT_INSTALLED,
    INSTALLED,
    INVALID
}

data class QnnContextInstalledFile(
    val name: String,
    val sizeBytes: Long,
    val sha256: String
)

data class QnnContextModelInstallRecord(
    val modelId: String,
    val releaseVersion: String,
    val qairtVersion: String,
    val targetChipset: String,
    val htpVersion: Int,
    val archiveSha256: String,
    val installedAtMillis: Long,
    val files: List<QnnContextInstalledFile>
) {
    fun toJson(): String = JSONObject()
        .put("schema_version", SCHEMA_VERSION)
        .put("model_id", modelId)
        .put("release_version", releaseVersion)
        .put("qairt_version", qairtVersion)
        .put("target_chipset", targetChipset)
        .put("htp_version", htpVersion)
        .put("archive_sha256", archiveSha256)
        .put("installed_at_millis", installedAtMillis)
        .put("files", JSONArray().apply {
            files.sortedBy(QnnContextInstalledFile::name).forEach { file ->
                put(JSONObject()
                    .put("name", file.name)
                    .put("size_bytes", file.sizeBytes)
                    .put("sha256", file.sha256))
            }
        })
        .toString()

    companion object {
        const val SCHEMA_VERSION = 1

        fun fromJson(json: String): QnnContextModelInstallRecord {
            val root = JSONObject(json)
            require(root.getInt("schema_version") == SCHEMA_VERSION)
            val values = root.getJSONArray("files")
            val files = buildList {
                repeat(values.length()) { index ->
                    val value = values.getJSONObject(index)
                    add(QnnContextInstalledFile(
                        name = value.getString("name"),
                        sizeBytes = value.getLong("size_bytes"),
                        sha256 = value.getString("sha256").lowercase(Locale.ROOT)
                    ))
                }
            }
            return QnnContextModelInstallRecord(
                modelId = root.getString("model_id"),
                releaseVersion = root.getString("release_version"),
                qairtVersion = root.getString("qairt_version"),
                targetChipset = root.getString("target_chipset"),
                htpVersion = root.getInt("htp_version"),
                archiveSha256 = root.getString("archive_sha256").lowercase(Locale.ROOT),
                installedAtMillis = root.getLong("installed_at_millis"),
                files = files
            )
        }
    }
}

data class QnnContextModelSnapshot(
    val state: QnnContextModelState,
    val directory: File? = null,
    val record: QnnContextModelInstallRecord? = null,
    val detail: String = ""
)

data class QnnContextModelInstallResult(
    val directory: File,
    val record: QnnContextModelInstallRecord,
    val replacedDirectory: File?
)

data class QnnContextModelRecoveryResult(
    val active: QnnContextModelSnapshot,
    val quarantinedDirectory: File?,
    val rolledBack: Boolean,
    val reasonCode: String
)

class QnnContextModelInstallException(message: String, cause: Throwable? = null) : IOException(message, cause)

class LargeTurboQnnModelStore(
    filesDirectory: File,
    modelRootName: String = LargeTurboQnnModelCatalog.MODEL_ROOT_NAME,
    deviceRootName: String = LargeTurboQnnModelCatalog.DEVICE_ROOT_NAME,
    private val clock: () -> Long = System::currentTimeMillis,
    private val usableSpace: (File) -> Long = File::getUsableSpace
) {
    private val root = secureChild(
        secureChild(
            secureChild(
                secureChild(filesDirectory.canonicalFile, "models"),
                "asr"
            ),
            modelRootName
        ),
        deviceRootName
    )
    private val releases = secureChild(root, "releases")
    private val staging = secureChild(root, ".staging")
    private val activePointer = secureChild(root, "active.json")

    init {
        check(releases.mkdirs() || releases.isDirectory) { "QNN ASR release storage is unavailable" }
        check(staging.mkdirs() || staging.isDirectory) { "QNN ASR staging storage is unavailable" }
    }

    fun downloadDirectory(): File = secureChild(root, ".downloads").also {
        check(it.mkdirs() || it.isDirectory) { "QNN ASR download storage is unavailable" }
    }

    fun requiredFreeBytes(manifest: LargeTurboQnnModelManifest): Long {
        val currentBytes = activeDirectory()?.walkTopDown()?.filter(File::isFile)?.sumOf(File::length) ?: 0L
        return safeAdd(
            safeAdd(manifest.archive.sizeBytes, manifest.totalInstalledSizeBytes),
            safeAdd(currentBytes, MIN_FREE_AFTER_INSTALL_BYTES)
        )
    }

    fun requiredInstallFreeBytes(manifest: LargeTurboQnnModelManifest): Long {
        val currentBytes = activeDirectory()?.walkTopDown()?.filter(File::isFile)?.sumOf(File::length) ?: 0L
        return safeAdd(
            manifest.totalInstalledSizeBytes,
            safeAdd(currentBytes, MIN_FREE_AFTER_INSTALL_BYTES)
        )
    }

    fun hasEnoughSpace(manifest: LargeTurboQnnModelManifest): Boolean =
        usableSpace(root) >= requiredFreeBytes(manifest)

    fun hasEnoughInstallSpace(manifest: LargeTurboQnnModelManifest): Boolean =
        usableSpace(root) >= requiredInstallFreeBytes(manifest)

    @Synchronized
    fun inspectActive(manifest: LargeTurboQnnModelManifest): QnnContextModelSnapshot {
        val directory = activeDirectory() ?: return QnnContextModelSnapshot(QnnContextModelState.NOT_INSTALLED)
        return inspectDirectory(directory, manifest)
    }

    @Synchronized
    fun install(
        manifest: LargeTurboQnnModelManifest,
        archive: File,
        archiveSha256: String,
        supportAssets: Map<String, File>
    ): QnnContextModelInstallResult {
        require(archiveSha256.matches(SHA256_PATTERN)) { "Archive SHA-256 is invalid" }
        if (!archive.isFile || archive.length() != manifest.archive.sizeBytes) {
            throw QnnContextModelInstallException("QNN model archive size does not match its manifest")
        }
        manifest.archive.sha256?.let { expected ->
            if (!archiveSha256.equals(expected, ignoreCase = true)) {
                throw QnnContextModelInstallException("QNN model archive SHA-256 does not match its manifest")
            }
        }
        if (!hasEnoughInstallSpace(manifest)) {
            throw QnnContextModelInstallException("Not enough storage to install the QNN ASR model")
        }

        val releaseKey = "${manifest.installDirectoryName}-${archiveSha256.take(12)}"
        val destination = secureChild(releases, releaseKey)
        inspectDirectory(destination, manifest).takeIf { it.state == QnnContextModelState.INSTALLED }?.let { ready ->
            val previous = activeDirectory()?.takeUnless { it.canonicalFile == destination.canonicalFile }
            writeActivePointer(destination, previous)
            return QnnContextModelInstallResult(destination, requireNotNull(ready.record), previous)
        }

        val work = secureChild(staging, "$releaseKey-${clock()}")
        work.deleteRecursively()
        check(work.mkdirs()) { "Could not create QNN ASR staging directory" }
        try {
            val installedFiles = extractArchive(manifest, archive, work).toMutableList()
            manifest.supportAssets.forEach { asset ->
                val source = supportAssets[asset.installedName]
                    ?: throw QnnContextModelInstallException("Missing support asset ${asset.installedName}")
                installedFiles += installSupportAsset(asset, source, work)
            }
            validateWhisperMetadata(File(work, "whisper_metadata.json"), manifest)
            val record = QnnContextModelInstallRecord(
                modelId = manifest.modelId,
                releaseVersion = manifest.releaseVersion,
                qairtVersion = manifest.qairtVersion,
                targetChipset = manifest.targetChipset,
                htpVersion = manifest.htpVersion,
                archiveSha256 = archiveSha256.lowercase(Locale.ROOT),
                installedAtMillis = clock(),
                files = installedFiles
            )
            writeAndSync(File(work, INSTALL_RECORD_FILE), record.toJson().toByteArray(Charsets.UTF_8))
            writeAndSync(File(work, ARCHIVE_DIGEST_FILE), "$archiveSha256\n".toByteArray(Charsets.US_ASCII))

            val previous = activeDirectory()?.takeUnless { it.canonicalFile == destination.canonicalFile }
            if (destination.exists()) destination.deleteRecursively()
            atomicMove(work, destination)
            writeActivePointer(destination, previous)
            return QnnContextModelInstallResult(destination, record, previous)
        } catch (error: Throwable) {
            work.deleteRecursively()
            if (error is QnnContextModelInstallException) throw error
            throw QnnContextModelInstallException("Could not install the QNN ASR model", error)
        }
    }

    @Synchronized
    fun rollback(manifest: LargeTurboQnnModelManifest): QnnContextModelSnapshot {
        val pointer = readActivePointer() ?: return QnnContextModelSnapshot(
            QnnContextModelState.NOT_INSTALLED,
            detail = "No active QNN ASR release exists"
        )
        val previousName = pointer.optString("previous")
        if (previousName.isBlank()) {
            return QnnContextModelSnapshot(QnnContextModelState.NOT_INSTALLED, detail = "No rollback release exists")
        }
        val previous = secureChild(releases, previousName)
        val snapshot = inspectDirectory(previous, manifest)
        if (snapshot.state != QnnContextModelState.INSTALLED) return snapshot
        val active = pointer.optString("active").takeIf(String::isNotBlank)?.let { secureChild(releases, it) }
        writeActivePointer(previous, active)
        return snapshot
    }

    @Synchronized
    fun quarantineActiveAndRollback(
        manifest: LargeTurboQnnModelManifest,
        reasonCode: String,
        detail: String
    ): QnnContextModelRecoveryResult {
        require(reasonCode.matches(REASON_CODE_PATTERN)) { "QNN ASR quarantine reason is invalid" }
        val pointer = readActivePointer() ?: return QnnContextModelRecoveryResult(
            active = QnnContextModelSnapshot(
                QnnContextModelState.NOT_INSTALLED,
                detail = "No active QNN ASR release exists"
            ),
            quarantinedDirectory = null,
            rolledBack = false,
            reasonCode = reasonCode
        )
        val activeName = pointer.optString("active")
        if (activeName.isBlank()) return QnnContextModelRecoveryResult(
            active = QnnContextModelSnapshot(
                QnnContextModelState.NOT_INSTALLED,
                detail = "No active QNN ASR release exists"
            ),
            quarantinedDirectory = null,
            rolledBack = false,
            reasonCode = reasonCode
        )
        val active = secureChild(releases, activeName)
        writeQuarantineRecord(active, reasonCode, detail)

        val previousName = pointer.optString("previous")
        if (previousName.isBlank()) return QnnContextModelRecoveryResult(
            active = inspectDirectory(active, manifest),
            quarantinedDirectory = active,
            rolledBack = false,
            reasonCode = reasonCode
        )
        val previous = secureChild(releases, previousName)
        val previousSnapshot = inspectCompatibleRelease(previous, manifest)
        if (previousSnapshot.state != QnnContextModelState.INSTALLED) {
            return QnnContextModelRecoveryResult(
                active = inspectDirectory(active, manifest),
                quarantinedDirectory = active,
                rolledBack = false,
                reasonCode = reasonCode
            )
        }
        writeActivePointer(previous, active)
        return QnnContextModelRecoveryResult(
            active = previousSnapshot,
            quarantinedDirectory = active,
            rolledBack = true,
            reasonCode = reasonCode
        )
    }

    @Synchronized
    fun deleteAll() {
        root.deleteRecursively()
        check(releases.mkdirs() || releases.isDirectory) { "QNN ASR release storage is unavailable" }
        check(staging.mkdirs() || staging.isDirectory) { "QNN ASR staging storage is unavailable" }
    }

    private fun extractArchive(
        manifest: LargeTurboQnnModelManifest,
        archive: File,
        target: File
    ): List<QnnContextInstalledFile> = ZipFile(archive).use { zip ->
        val expected = manifest.archive.entries.associateBy(QnnContextArchiveEntry::archivePath)
        val actualFiles = zip.entries().asSequence().filterNot { it.isDirectory }.toList()
        val unexpected = actualFiles.map { it.name }.filterNot(expected::containsKey)
        if (unexpected.isNotEmpty() || actualFiles.size != expected.size) {
            throw QnnContextModelInstallException("QNN model archive contains an unexpected file layout")
        }
        manifest.archive.entries.map { entry ->
            val source = zip.getEntry(entry.archivePath)
                ?: throw QnnContextModelInstallException("QNN model archive is missing ${entry.archivePath}")
            if (source.size != entry.uncompressedSizeBytes || source.compressedSize != entry.compressedSizeBytes ||
                source.crc != entry.crc32
            ) {
                throw QnnContextModelInstallException("QNN model archive metadata is invalid for ${entry.installedName}")
            }
            val output = secureChild(target, entry.installedName)
            val digest = MessageDigest.getInstance("SHA-256")
            var copied = 0L
            zip.getInputStream(source).buffered(BUFFER_BYTES).use { input ->
                FileOutputStream(output).buffered(BUFFER_BYTES).use { outputStream ->
                    val buffer = ByteArray(BUFFER_BYTES)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        copied += read
                        if (copied > entry.uncompressedSizeBytes) {
                            throw QnnContextModelInstallException("QNN model entry exceeds its signed size")
                        }
                        digest.update(buffer, 0, read)
                        outputStream.write(buffer, 0, read)
                    }
                }
            }
            if (copied != entry.uncompressedSizeBytes) {
                throw QnnContextModelInstallException("QNN model entry was truncated during extraction")
            }
            QnnContextInstalledFile(entry.installedName, copied, digest.hex())
        }
    }

    private fun installSupportAsset(
        asset: QnnContextSupportAsset,
        source: File,
        target: File
    ): QnnContextInstalledFile {
        if (!source.isFile || source.length() != asset.downloadSizeBytes ||
            !sha256(source).equals(asset.sha256, ignoreCase = true)
        ) {
            throw QnnContextModelInstallException("Support asset verification failed for ${asset.installedName}")
        }
        val destination = secureChild(target, asset.installedName)
        when (asset.transform) {
            QnnContextSupportTransform.NONE -> copyAndSync(source, destination)
            QnnContextSupportTransform.MEL_80_NPY_TO_FLOAT32 -> extractMel(source, destination, 80)
            QnnContextSupportTransform.MEL_128_NPY_TO_FLOAT32 -> extractMel(source, destination, 128)
        }
        if (destination.length() != asset.installedSizeBytes) {
            throw QnnContextModelInstallException("Support asset output is invalid for ${asset.installedName}")
        }
        return QnnContextInstalledFile(asset.installedName, destination.length(), sha256(destination))
    }

    private fun extractMel(source: File, destination: File, melBins: Int) = ZipFile(source).use { zip ->
        require(melBins in setOf(80, 128))
        val entry = zip.getEntry("mel_${melBins}.npy")
            ?: throw QnnContextModelInstallException("OpenAI mel filter archive is missing mel_${melBins}.npy")
        zip.getInputStream(entry).buffered().use { input ->
            val magic = ByteArray(6).also { input.readFully(it) }
            if (!magic.contentEquals(byteArrayOf(0x93.toByte(), 0x4e, 0x55, 0x4d, 0x50, 0x59))) {
                throw QnnContextModelInstallException("OpenAI mel filter has an invalid NPY header")
            }
            val major = input.read()
            input.read()
            val headerSize = when (major) {
                1 -> ByteBuffer.wrap(ByteArray(2).also { input.readFully(it) }).order(ByteOrder.LITTLE_ENDIAN)
                    .short.toInt() and 0xffff
                2, 3 -> ByteBuffer.wrap(ByteArray(4).also { input.readFully(it) }).order(ByteOrder.LITTLE_ENDIAN).int
                else -> throw QnnContextModelInstallException("Unsupported NPY version for mel filters")
            }
            val header = ByteArray(headerSize).also { input.readFully(it) }.toString(Charsets.US_ASCII)
            if (!("'<f4'" in header || "\"<f4\"" in header) || "True" in header ||
                !Regex("\\(\\s*$melBins\\s*,\\s*201\\s*[,]?\\s*\\)").containsMatchIn(header)
            ) {
                throw QnnContextModelInstallException("OpenAI mel filter tensor layout is unsupported")
            }
            FileOutputStream(destination).use { output ->
                val buffer = ByteArray(BUFFER_BYTES)
                var copied = 0L
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    copied += read
                    val expectedBytes = melBins.toLong() * MEL_FFT_BINS * Float.SIZE_BYTES
                    if (copied > expectedBytes) {
                        throw QnnContextModelInstallException("OpenAI mel filter tensor is oversized")
                    }
                    output.write(buffer, 0, read)
                }
                output.fd.sync()
                val expectedBytes = melBins.toLong() * MEL_FFT_BINS * Float.SIZE_BYTES
                if (copied != expectedBytes) {
                    throw QnnContextModelInstallException("OpenAI mel filter tensor is truncated")
                }
            }
        }
    }

    private fun validateWhisperMetadata(file: File, manifest: LargeTurboQnnModelManifest) {
        val root = runCatching { JSONObject(file.readText(Charsets.UTF_8)) }
            .getOrElse { throw QnnContextModelInstallException("QNN Whisper metadata is invalid", it) }
        val chipset = root.getJSONObject("chipset_attributes")
        val aliases = chipset.getJSONArray("aliases").let { values ->
            buildSet { repeat(values.length()) { add(values.getString(it).lowercase(Locale.ROOT)) } }
        }
        val modelFiles = root.getJSONObject("model_files")
        val encoderInput = modelFiles.getJSONObject("encoder.bin")
            .getJSONObject("inputs").getJSONObject("input_features")
        val logits = modelFiles.getJSONObject("decoder.bin")
            .getJSONObject("outputs").getJSONObject("logits")
        requireMetadata(root.getString("model_id") == manifest.metadataModelId, "model id")
        requireMetadata(root.getString("runtime") == "qnn_context_binary", "runtime")
        requireMetadata(root.getString("precision") == manifest.precision, "precision")
        requireMetadata(root.getJSONObject("tool_versions").getString("qairt") == manifest.qairtVersion, "QAIRT version")
        requireMetadata(chipset.getInt("htp_version") == manifest.htpVersion, "HTP version")
        requireMetadata(chipset.getInt("soc_model") == manifest.socModel, "SoC model")
        requireMetadata(aliases.any { it in manifest.targetAliases }, "chipset alias")
        requireMetadata(
            encoderInput.getJSONArray("shape").toIntList() == listOf(1, manifest.melBins, manifest.melFrames),
            "encoder input"
        )
        requireMetadata(logits.getJSONArray("shape").toIntList() == listOf(1, manifest.vocabularySize, 1, 1), "decoder output")
    }

    private fun inspectDirectory(
        directory: File,
        manifest: LargeTurboQnnModelManifest
    ): QnnContextModelSnapshot {
        if (!directory.isDirectory) return QnnContextModelSnapshot(QnnContextModelState.NOT_INSTALLED)
        quarantineDetail(directory)?.let { detail ->
            return QnnContextModelSnapshot(QnnContextModelState.INVALID, directory, detail = detail)
        }
        val record = runCatching {
            QnnContextModelInstallRecord.fromJson(File(directory, INSTALL_RECORD_FILE).readText(Charsets.UTF_8))
        }.getOrElse {
            return QnnContextModelSnapshot(QnnContextModelState.INVALID, directory, detail = "Install record is missing")
        }
        if (record.modelId != manifest.modelId || record.releaseVersion != manifest.releaseVersion ||
            record.qairtVersion != manifest.qairtVersion || record.targetChipset != manifest.targetChipset ||
            record.htpVersion != manifest.htpVersion || !record.archiveSha256.matches(SHA256_PATTERN)
        ) {
            return QnnContextModelSnapshot(QnnContextModelState.INVALID, directory, record, "Install record is incompatible")
        }
        if (!archiveDigestReceiptMatches(directory, record)) {
            return QnnContextModelSnapshot(
                QnnContextModelState.INVALID,
                directory,
                record,
                "Archive digest receipt is invalid"
            )
        }
        val expectedNames = manifest.archive.entries.map(QnnContextArchiveEntry::installedName) +
            manifest.supportAssets.map(QnnContextSupportAsset::installedName)
        if (record.files.map(QnnContextInstalledFile::name).toSet() != expectedNames.toSet()) {
            return QnnContextModelSnapshot(QnnContextModelState.INVALID, directory, record, "Installed file set is incomplete")
        }
        record.files.forEach { installed ->
            val file = runCatching { secureChild(directory, installed.name) }.getOrNull()
            if (file == null || !file.isFile || file.length() != installed.sizeBytes ||
                !sha256(file).equals(installed.sha256, ignoreCase = true)
            ) {
                return QnnContextModelSnapshot(
                    QnnContextModelState.INVALID,
                    directory,
                    record,
                    "Installed file verification failed for ${installed.name}"
                )
            }
        }
        return QnnContextModelSnapshot(QnnContextModelState.INSTALLED, directory, record)
    }

    private fun inspectCompatibleRelease(
        directory: File,
        manifest: LargeTurboQnnModelManifest
    ): QnnContextModelSnapshot {
        if (!directory.isDirectory) return QnnContextModelSnapshot(QnnContextModelState.NOT_INSTALLED)
        quarantineDetail(directory)?.let { detail ->
            return QnnContextModelSnapshot(QnnContextModelState.INVALID, directory, detail = detail)
        }
        val record = runCatching {
            QnnContextModelInstallRecord.fromJson(File(directory, INSTALL_RECORD_FILE).readText(Charsets.UTF_8))
        }.getOrElse {
            return QnnContextModelSnapshot(QnnContextModelState.INVALID, directory, detail = "Install record is missing")
        }
        if (record.modelId != manifest.modelId || record.qairtVersion != manifest.qairtVersion ||
            record.targetChipset != manifest.targetChipset || record.htpVersion != manifest.htpVersion ||
            !record.archiveSha256.matches(SHA256_PATTERN)
        ) {
            return QnnContextModelSnapshot(
                QnnContextModelState.INVALID,
                directory,
                record,
                "Rollback release is incompatible"
            )
        }
        if (!archiveDigestReceiptMatches(directory, record)) {
            return QnnContextModelSnapshot(
                QnnContextModelState.INVALID,
                directory,
                record,
                "Rollback archive digest receipt is invalid"
            )
        }
        val requiredNames = manifest.archive.entries.map(QnnContextArchiveEntry::installedName).toSet() +
            manifest.supportAssets.map(QnnContextSupportAsset::installedName).toSet()
        if (!record.files.map(QnnContextInstalledFile::name).toSet().containsAll(requiredNames)) {
            return QnnContextModelSnapshot(
                QnnContextModelState.INVALID,
                directory,
                record,
                "Rollback release file set is incomplete"
            )
        }
        record.files.forEach { installed ->
            val file = runCatching { secureChild(directory, installed.name) }.getOrNull()
            if (file == null || !file.isFile || file.length() != installed.sizeBytes ||
                !sha256(file).equals(installed.sha256, ignoreCase = true)
            ) {
                return QnnContextModelSnapshot(
                    QnnContextModelState.INVALID,
                    directory,
                    record,
                    "Rollback release verification failed for ${installed.name}"
                )
            }
        }
        return QnnContextModelSnapshot(QnnContextModelState.INSTALLED, directory, record)
    }

    private fun archiveDigestReceiptMatches(
        directory: File,
        record: QnnContextModelInstallRecord
    ): Boolean {
        val receipt = runCatching { secureChild(directory, ARCHIVE_DIGEST_FILE) }.getOrNull()
            ?: return false
        if (!receipt.isFile || receipt.length() !in 64L..66L) return false
        val digest = runCatching { receipt.readText(Charsets.US_ASCII).trim() }.getOrNull()
            ?: return false
        return digest.matches(SHA256_PATTERN) && digest.equals(record.archiveSha256, ignoreCase = true)
    }

    private fun writeQuarantineRecord(directory: File, reasonCode: String, detail: String) {
        require(directory.parentFile?.canonicalFile == releases.canonicalFile)
        val value = JSONObject()
            .put("schema_version", 1)
            .put("reason_code", reasonCode)
            .put("detail", detail.take(MAX_QUARANTINE_DETAIL_CHARS))
            .put("quarantined_at_millis", clock())
        val target = secureChild(directory, QUARANTINE_RECORD_FILE)
        val temporary = secureChild(directory, ".quarantine-${clock()}.json")
        writeAndSync(temporary, value.toString().toByteArray(Charsets.UTF_8))
        atomicMove(temporary, target)
    }

    private fun quarantineDetail(directory: File): String? {
        val file = secureChild(directory, QUARANTINE_RECORD_FILE)
        if (!file.isFile) return null
        return runCatching {
            val value = JSONObject(file.readText(Charsets.UTF_8))
            "Quarantined QNN ASR release: ${value.optString("reason_code", "unknown")}" +
                value.optString("detail").takeIf(String::isNotBlank)?.let { ": $it" }.orEmpty()
        }.getOrDefault("Quarantined QNN ASR release")
    }

    private fun activeDirectory(): File? {
        val active = readActivePointer()?.optString("active").orEmpty()
        return active.takeIf(String::isNotBlank)?.let { secureChild(releases, it) }
    }

    private fun readActivePointer(): JSONObject? = runCatching {
        if (!activePointer.isFile) null else JSONObject(activePointer.readText(Charsets.UTF_8))
    }.getOrNull()

    private fun writeActivePointer(active: File, previous: File?) {
        require(active.parentFile?.canonicalFile == releases.canonicalFile)
        previous?.let { require(it.parentFile?.canonicalFile == releases.canonicalFile) }
        val value = JSONObject()
            .put("schema_version", 1)
            .put("active", active.name)
            .put("previous", previous?.name.orEmpty())
            .put("updated_at_millis", clock())
        val temporary = secureChild(root, ".active-${clock()}.json")
        writeAndSync(temporary, value.toString().toByteArray(Charsets.UTF_8))
        atomicMove(temporary, activePointer)
    }

    private fun copyAndSync(source: File, destination: File) {
        source.inputStream().buffered(BUFFER_BYTES).use { input ->
            FileOutputStream(destination).use { output ->
                input.copyTo(output, BUFFER_BYTES)
                output.fd.sync()
            }
        }
    }

    private fun writeAndSync(file: File, bytes: ByteArray) {
        file.parentFile?.mkdirs()
        FileOutputStream(file).use { output ->
            output.write(bytes)
            output.fd.sync()
        }
    }

    private fun atomicMove(source: File, target: File) {
        target.parentFile?.mkdirs()
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
                digest.update(buffer, 0, read)
            }
        }
        return digest.hex()
    }

    private fun secureChild(parent: File, name: String): File {
        require(name.isNotBlank() && '/' !in name && '\\' !in name && name !in setOf(".", ".."))
        val canonicalParent = parent.canonicalFile
        val candidate = File(canonicalParent, name).canonicalFile
        require(candidate.path.startsWith(canonicalParent.path + File.separator)) { "Path escapes QNN ASR storage" }
        return candidate
    }

    private fun requireMetadata(condition: Boolean, field: String) {
        if (!condition) throw QnnContextModelInstallException("QNN Whisper metadata has an incompatible $field")
    }

    private fun JSONArray.toIntList(): List<Int> = buildList {
        repeat(length()) { add(getInt(it)) }
    }

    private fun BufferedInputStream.readFully(target: ByteArray) {
        var offset = 0
        while (offset < target.size) {
            val read = read(target, offset, target.size - offset)
            if (read < 0) throw QnnContextModelInstallException("Unexpected end of model support asset")
            offset += read
        }
    }

    private fun MessageDigest.hex(): String = digest().joinToString("") { "%02x".format(it) }

    private fun safeAdd(left: Long, right: Long): Long = runCatching { Math.addExact(left, right) }
        .getOrDefault(Long.MAX_VALUE)

    private companion object {
        const val INSTALL_RECORD_FILE = "manifest.json"
        const val ARCHIVE_DIGEST_FILE = "model.sha256"
        const val BUFFER_BYTES = 256 * 1024
        const val MEL_FFT_BINS = 201L
        const val MIN_FREE_AFTER_INSTALL_BYTES = 512L * 1024L * 1024L
        const val QUARANTINE_RECORD_FILE = ".quarantined.json"
        const val MAX_QUARANTINE_DETAIL_CHARS = 512
        val SHA256_PATTERN = Regex("[a-fA-F0-9]{64}")
        val REASON_CODE_PATTERN = Regex("[a-z0-9][a-z0-9_]{0,95}")
    }
}
