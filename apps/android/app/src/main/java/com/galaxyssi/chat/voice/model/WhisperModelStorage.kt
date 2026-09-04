package com.galaxyssi.chat.voice.model

import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

enum class WhisperModelStorageState {
    NOT_INSTALLED,
    CHECKING_SPACE,
    DOWNLOADING_PARTIAL,
    PAUSED,
    VERIFYING_SIZE,
    VERIFYING_SHA256,
    ATOMIC_INSTALLING,
    INSTALLED_UNCERTIFIED,
    BENCHMARKING,
    CERTIFIED,
    SECOND_PASS_ONLY,
    UNSUPPORTED,
    FAILED
}

enum class WhisperModelInstallFailure {
    INSUFFICIENT_SPACE,
    SOURCE_MISSING,
    SIZE_MISMATCH,
    SHA256_MISMATCH,
    COPY_FAILED,
    ATOMIC_INSTALL_FAILED,
    METADATA_INVALID,
    MODEL_IN_USE
}

class WhisperModelInstallException(
    val failure: WhisperModelInstallFailure,
    message: String,
    cause: Throwable? = null
) : IOException(message, cause)

data class WhisperModelInstallMetadata(
    val profileId: String,
    val fileName: String,
    val expectedSizeBytes: Long,
    val sha256: String,
    val catalogVersion: String,
    val installedAtMillis: Long,
    val source: String,
    val fileLastModifiedMillis: Long,
    val certification: WhisperCertificationLevel
) {
    fun toJson(): String = JSONObject()
        .put("profileId", profileId)
        .put("fileName", fileName)
        .put("expectedSizeBytes", expectedSizeBytes)
        .put("sha256", sha256)
        .put("catalogVersion", catalogVersion)
        .put("installedAtMillis", installedAtMillis)
        .put("source", source)
        .put("fileLastModifiedMillis", fileLastModifiedMillis)
        .put("certification", certification.name)
        .toString()

    companion object {
        fun fromJson(json: String): WhisperModelInstallMetadata {
            val value = JSONObject(json)
            return WhisperModelInstallMetadata(
                profileId = value.getString("profileId"),
                fileName = value.getString("fileName"),
                expectedSizeBytes = value.getLong("expectedSizeBytes"),
                sha256 = value.getString("sha256"),
                catalogVersion = value.getString("catalogVersion"),
                installedAtMillis = value.getLong("installedAtMillis"),
                source = value.getString("source"),
                fileLastModifiedMillis = value.getLong("fileLastModifiedMillis"),
                certification = enumValueOf(value.getString("certification"))
            )
        }
    }
}

data class WhisperModelStorageSnapshot(
    val state: WhisperModelStorageState,
    val file: File? = null,
    val metadata: WhisperModelInstallMetadata? = null,
    val failure: WhisperModelInstallFailure? = null,
    val detail: String = ""
) {
    val installed: Boolean
        get() = state in setOf(
            WhisperModelStorageState.INSTALLED_UNCERTIFIED,
            WhisperModelStorageState.CERTIFIED,
            WhisperModelStorageState.SECOND_PASS_ONLY,
            WhisperModelStorageState.UNSUPPORTED
        )
}

class WhisperModelStorage(
    rootDirectory: File,
    private val catalogVersion: String = WhisperModelCatalog.CATALOG_VERSION,
    private val clock: () -> Long = System::currentTimeMillis,
    private val capacityProvider: (File) -> Long = { it.usableSpace }
) {
    private val root = rootDirectory.canonicalFile
    private val modelsRoot = child(root, "models")
    private val stagingRoot = child(root, "staging")

    init {
        modelsRoot.mkdirs()
        stagingRoot.mkdirs()
    }

    fun finalFile(profile: WhisperModelProfile): File = child(modelDirectory(profile), profile.fileName)

    fun metadataFile(profile: WhisperModelProfile): File = child(modelDirectory(profile), "installation.json")

    fun stagingFile(profile: WhisperModelProfile): File = child(stagingRoot, "${profile.id}-${profile.fileName}.partial")

    fun requiredFreeBytes(profile: WhisperModelProfile): Long =
        safeAdd(safeMultiply(profile.expectedSizeBytes, 2L), profile.minFreeStorageBytes)

    fun inspect(profile: WhisperModelProfile): WhisperModelStorageSnapshot {
        val file = finalFile(profile)
        val metadata = readMetadata(profile) ?: return WhisperModelStorageSnapshot(WhisperModelStorageState.NOT_INSTALLED)
        if (!file.isFile || file.length() != profile.expectedSizeBytes) {
            return WhisperModelStorageSnapshot(
                state = WhisperModelStorageState.FAILED,
                file = file.takeIf(File::exists),
                metadata = metadata,
                failure = WhisperModelInstallFailure.SIZE_MISMATCH,
                detail = "Installed model size no longer matches its profile"
            )
        }
        if (!metadata.matches(profile, catalogVersion) || metadata.fileLastModifiedMillis != file.lastModified()) {
            return WhisperModelStorageSnapshot(
                state = WhisperModelStorageState.FAILED,
                file = file,
                metadata = metadata,
                failure = WhisperModelInstallFailure.METADATA_INVALID,
                detail = "Installed model metadata is stale or invalid"
            )
        }
        val state = when (metadata.certification) {
            WhisperCertificationLevel.UNTESTED -> WhisperModelStorageState.INSTALLED_UNCERTIFIED
            WhisperCertificationLevel.REALTIME, WhisperCertificationLevel.FINAL -> WhisperModelStorageState.CERTIFIED
            WhisperCertificationLevel.SECOND_PASS -> WhisperModelStorageState.SECOND_PASS_ONLY
            WhisperCertificationLevel.REMOTE_RECOMMENDED,
            WhisperCertificationLevel.UNSUPPORTED -> WhisperModelStorageState.UNSUPPORTED
        }
        return WhisperModelStorageSnapshot(state, file, metadata)
    }

    @Synchronized
    fun install(
        sourceFile: File,
        profile: WhisperModelProfile,
        sourceLabel: String,
        availableBytes: Long = capacityProvider(root),
        beforeCommit: () -> Unit = {}
    ): WhisperModelInstallMetadata {
        if (!sourceFile.isFile) {
            throw WhisperModelInstallException(WhisperModelInstallFailure.SOURCE_MISSING, "Model source file is missing")
        }
        val required = safeAdd(profile.expectedSizeBytes, profile.minFreeStorageBytes)
        if (availableBytes in 0 until required) {
            throw WhisperModelInstallException(
                WhisperModelInstallFailure.INSUFFICIENT_SPACE,
                "Model install needs $required free bytes but only $availableBytes are available"
            )
        }
        if (sourceFile.length() != profile.expectedSizeBytes) {
            throw WhisperModelInstallException(
                WhisperModelInstallFailure.SIZE_MISMATCH,
                "Expected ${profile.expectedSizeBytes} bytes but found ${sourceFile.length()}"
            )
        }

        val staged = stagingFile(profile)
        staged.parentFile?.mkdirs()
        staged.delete()
        try {
            copyAndSync(sourceFile, staged)
        } catch (error: Throwable) {
            staged.delete()
            throw WhisperModelInstallException(WhisperModelInstallFailure.COPY_FAILED, "Could not stage the model", error)
        }
        val stagedVerification = WhisperModelVerifier.verify(staged, profile)
        if (!stagedVerification.valid) {
            staged.delete()
            throw verificationException(stagedVerification)
        }

        val destination = finalFile(profile)
        destination.parentFile?.mkdirs()
        try {
            beforeCommit()
        } catch (error: Throwable) {
            staged.delete()
            throw error
        }
        try {
            atomicMove(staged, destination)
        } catch (error: Throwable) {
            staged.delete()
            throw WhisperModelInstallException(
                WhisperModelInstallFailure.ATOMIC_INSTALL_FAILED,
                "Could not atomically install the verified model",
                error
            )
        }
        val metadata = WhisperModelInstallMetadata(
            profileId = profile.id,
            fileName = profile.fileName,
            expectedSizeBytes = profile.expectedSizeBytes,
            sha256 = profile.sha256,
            catalogVersion = catalogVersion,
            installedAtMillis = clock(),
            source = sourceLabel.take(256),
            fileLastModifiedMillis = destination.lastModified(),
            certification = WhisperCertificationLevel.UNTESTED
        )
        writeMetadata(profile, metadata)
        return metadata
    }

    fun verifyForNativeLoad(profile: WhisperModelProfile): WhisperVerificationResult {
        val snapshot = inspect(profile)
        if (!snapshot.installed) {
            return WhisperVerificationResult(
                valid = false,
                failure = WhisperVerificationFailure.MISSING,
                detail = snapshot.detail.ifBlank { "Model is not installed" }
            )
        }
        return WhisperModelVerifier.verify(requireNotNull(snapshot.file), profile)
    }

    @Synchronized
    fun invalidate(profile: WhisperModelProfile) {
        metadataFile(profile).delete()
        finalFile(profile).delete()
    }

    @Synchronized
    fun updateCertification(profile: WhisperModelProfile, certification: WhisperCertificationLevel) {
        val snapshot = inspect(profile)
        require(snapshot.installed) { "Cannot certify a model that is not installed" }
        writeMetadata(profile, requireNotNull(snapshot.metadata).copy(certification = certification))
    }

    @Synchronized
    fun delete(profile: WhisperModelProfile, active: Boolean = false): Boolean {
        if (active) {
            throw WhisperModelInstallException(WhisperModelInstallFailure.MODEL_IN_USE, "Model is currently loaded")
        }
        stagingFile(profile).delete()
        return modelDirectory(profile).deleteRecursively()
    }

    fun cleanupStalePartials(maxAgeMillis: Long): Int {
        val threshold = clock() - maxAgeMillis.coerceAtLeast(0L)
        return root.walkTopDown().filter { file ->
            file.isFile && file.name.endsWith(".partial") && file.lastModified() < threshold
        }.count(File::delete)
    }

    private fun modelDirectory(profile: WhisperModelProfile): File = child(modelsRoot, profile.id)

    private fun readMetadata(profile: WhisperModelProfile): WhisperModelInstallMetadata? = runCatching {
        val file = metadataFile(profile)
        if (!file.isFile) null else WhisperModelInstallMetadata.fromJson(file.readText(Charsets.UTF_8))
    }.getOrNull()

    private fun writeMetadata(profile: WhisperModelProfile, metadata: WhisperModelInstallMetadata) {
        val target = metadataFile(profile)
        target.parentFile?.mkdirs()
        val partial = child(target.parentFile ?: root, "${target.name}.partial")
        partial.delete()
        FileOutputStream(partial).use { output ->
            output.write(metadata.toJson().toByteArray(Charsets.UTF_8))
            output.fd.sync()
        }
        atomicMove(partial, target)
    }

    private fun copyAndSync(source: File, target: File) {
        FileInputStream(source).use { input ->
            FileOutputStream(target).use { output ->
                input.copyTo(output, 1024 * 1024)
                output.fd.sync()
            }
        }
    }

    private fun atomicMove(source: File, target: File) {
        try {
            Files.move(
                source.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING
            )
        } catch (unsupported: AtomicMoveNotSupportedException) {
            Files.move(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun verificationException(result: WhisperVerificationResult): WhisperModelInstallException = when (result.failure) {
        WhisperVerificationFailure.SIZE_MISMATCH -> WhisperModelInstallException(
            WhisperModelInstallFailure.SIZE_MISMATCH,
            result.detail
        )
        WhisperVerificationFailure.SHA256_MISMATCH -> WhisperModelInstallException(
            WhisperModelInstallFailure.SHA256_MISMATCH,
            result.detail
        )
        else -> WhisperModelInstallException(
            WhisperModelInstallFailure.SOURCE_MISSING,
            result.detail.ifBlank { "Model verification failed" }
        )
    }

    private fun child(parent: File, name: String): File {
        val candidate = File(parent, name).canonicalFile
        val prefix = parent.canonicalPath + File.separator
        require(candidate.path.startsWith(prefix)) { "Model path escapes its storage root" }
        return candidate
    }

    private fun safeMultiply(value: Long, multiplier: Long): Long = runCatching {
        Math.multiplyExact(value, multiplier)
    }.getOrDefault(Long.MAX_VALUE)

    private fun safeAdd(left: Long, right: Long): Long = runCatching {
        Math.addExact(left, right)
    }.getOrDefault(Long.MAX_VALUE)
}

private fun WhisperModelInstallMetadata.matches(profile: WhisperModelProfile, expectedCatalogVersion: String): Boolean =
    profileId == profile.id &&
        fileName == profile.fileName &&
        expectedSizeBytes == profile.expectedSizeBytes &&
        sha256 == profile.sha256 &&
        catalogVersion == expectedCatalogVersion
