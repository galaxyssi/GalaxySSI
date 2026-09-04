package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

enum class LocalModelInstallState {
    NOT_INSTALLED,
    QUEUED,
    DOWNLOADING,
    PAUSED,
    VERIFYING,
    INSTALLING,
    READY,
    FAILED
}

data class LocalModelInstallMetadata(
    val profileId: String,
    val repositoryId: String,
    val fileName: String,
    val expectedSizeBytes: Long,
    val sha256: String,
    val installedAtMillis: Long,
    val sourceUrl: String,
    val fileLastModifiedMillis: Long
) {
    fun toJson(): String = JSONObject()
        .put("profile_id", profileId)
        .put("repository_id", repositoryId)
        .put("file_name", fileName)
        .put("expected_size_bytes", expectedSizeBytes)
        .put("sha256", sha256)
        .put("installed_at_millis", installedAtMillis)
        .put("source_url", sourceUrl)
        .put("file_last_modified_millis", fileLastModifiedMillis)
        .toString()

    companion object {
        fun fromJson(encoded: String): LocalModelInstallMetadata {
            val value = JSONObject(encoded)
            return LocalModelInstallMetadata(
                profileId = value.getString("profile_id"),
                repositoryId = value.getString("repository_id"),
                fileName = value.getString("file_name"),
                expectedSizeBytes = value.getLong("expected_size_bytes"),
                sha256 = value.getString("sha256"),
                installedAtMillis = value.getLong("installed_at_millis"),
                sourceUrl = value.getString("source_url"),
                fileLastModifiedMillis = value.getLong("file_last_modified_millis")
            )
        }
    }
}

data class LocalModelStorageSnapshot(
    val installed: Boolean,
    val file: File? = null,
    val metadata: LocalModelInstallMetadata? = null,
    val detail: String = ""
)

class LocalModelStorage internal constructor(rootDirectory: File) {
    constructor(context: Context) : this(File(context.applicationContext.filesDir, "local-llm"))

    private val root = rootDirectory.canonicalFile
    private val modelRoot = child(root, "models")
    private val stagingRoot = child(root, "staging")

    init {
        modelRoot.mkdirs()
        stagingRoot.mkdirs()
    }

    fun finalFile(profile: LocalModelRuntimeProfile): File = child(modelDirectory(profile), profile.fileName)

    fun metadataFile(profile: LocalModelRuntimeProfile): File = child(modelDirectory(profile), "installation.json")

    fun partialFile(profile: LocalModelRuntimeProfile): File = child(stagingRoot, "${profile.id}.gguf.part")

    fun availableBytes(): Long = root.usableSpace

    fun requiredDownloadBytes(profile: LocalModelRuntimeProfile): Long {
        val remaining = (profile.expectedModelFileBytes - partialFile(profile).length()).coerceAtLeast(0L)
        return safeAdd(remaining, MINIMUM_FREE_SPACE_BYTES)
    }

    fun inspect(profile: LocalModelRuntimeProfile): LocalModelStorageSnapshot {
        val file = finalFile(profile)
        val metadata = readMetadata(profile) ?: return LocalModelStorageSnapshot(false)
        if (!metadata.matches(profile) || !file.isFile || file.length() != profile.expectedModelFileBytes ||
            metadata.fileLastModifiedMillis != file.lastModified()
        ) {
            return LocalModelStorageSnapshot(false, file.takeIf(File::exists), metadata, "Installed model metadata is invalid")
        }
        return LocalModelStorageSnapshot(true, file, metadata)
    }

    fun verifyPartial(profile: LocalModelRuntimeProfile): Boolean {
        val partial = partialFile(profile)
        if (!partial.isFile || partial.length() != profile.expectedModelFileBytes || sha256(partial) != profile.sha256) {
            verifiedFiles.remove(profile.id)
            return false
        }
        verifiedFiles[profile.id] = identity(partial, profile)
        return true
    }

    @Synchronized
    fun commitVerifiedPartial(profile: LocalModelRuntimeProfile, sourceUrl: String): File {
        val partial = partialFile(profile)
        require(isCachedVerification(partial, profile) || verifyPartial(profile)) {
            "Downloaded model failed size or SHA-256 verification"
        }
        val destination = finalFile(profile)
        destination.parentFile?.mkdirs()
        atomicMove(partial, destination)
        val metadata = LocalModelInstallMetadata(
            profileId = profile.id,
            repositoryId = profile.repositoryId,
            fileName = profile.fileName,
            expectedSizeBytes = profile.expectedModelFileBytes,
            sha256 = profile.sha256,
            installedAtMillis = System.currentTimeMillis(),
            sourceUrl = sourceUrl.take(1_024),
            fileLastModifiedMillis = destination.lastModified()
        )
        writeAtomically(metadataFile(profile), metadata.toJson())
        verifiedFiles[profile.id] = identity(destination, profile)
        return destination
    }

    fun verifyForNativeLoad(profile: LocalModelRuntimeProfile): File {
        val snapshot = inspect(profile)
        val file = snapshot.file.takeIf { snapshot.installed }
            ?: throw IllegalStateException("Local model is not installed")
        if (isCachedVerification(file, profile)) return file
        require(sha256(file) == profile.sha256) { "Installed model SHA-256 verification failed" }
        verifiedFiles[profile.id] = identity(file, profile)
        return file
    }

    fun delete(profile: LocalModelRuntimeProfile, modelLoaded: Boolean) {
        require(!modelLoaded) { "Unload the local model before deleting it" }
        verifiedFiles.remove(profile.id)
        partialFile(profile).delete()
        modelDirectory(profile).deleteRecursively()
    }

    private fun isCachedVerification(file: File, profile: LocalModelRuntimeProfile): Boolean =
        verifiedFiles[profile.id] == identity(file, profile)

    private fun identity(file: File, profile: LocalModelRuntimeProfile): VerifiedFileIdentity = VerifiedFileIdentity(
        canonicalPath = file.canonicalPath,
        length = file.length(),
        lastModifiedMillis = file.lastModified(),
        expectedSha256 = profile.sha256
    )

    private fun modelDirectory(profile: LocalModelRuntimeProfile): File = child(modelRoot, profile.id)

    private fun readMetadata(profile: LocalModelRuntimeProfile): LocalModelInstallMetadata? = runCatching {
        LocalModelInstallMetadata.fromJson(metadataFile(profile).readText(Charsets.UTF_8))
    }.getOrNull()

    private fun LocalModelInstallMetadata.matches(profile: LocalModelRuntimeProfile): Boolean =
        profileId == profile.id && repositoryId == profile.repositoryId && fileName == profile.fileName &&
            expectedSizeBytes == profile.expectedModelFileBytes && sha256 == profile.sha256

    private fun child(parent: File, name: String): File {
        val candidate = File(parent, name).canonicalFile
        require(candidate.path.startsWith(root.path + File.separator) || candidate == root) {
            "Local model path escapes app-private storage"
        }
        return candidate
    }

    private fun writeAtomically(target: File, content: String) {
        target.parentFile?.mkdirs()
        val partial = File(target.parentFile, ".${target.name}.part")
        FileOutputStream(partial).use { output ->
            output.write(content.toByteArray(Charsets.UTF_8))
            output.fd.sync()
        }
        atomicMove(partial, target)
    }

    private fun atomicMove(source: File, target: File) {
        target.parentFile?.mkdirs()
        try {
            Files.move(
                source.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    companion object {
        const val MINIMUM_FREE_SPACE_BYTES = 1_073_741_824L

        private data class VerifiedFileIdentity(
            val canonicalPath: String,
            val length: Long,
            val lastModifiedMillis: Long,
            val expectedSha256: String
        )

        private val verifiedFiles = ConcurrentHashMap<String, VerifiedFileIdentity>()

        fun sha256(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { input ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (read > 0) digest.update(buffer, 0, read)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }

        private fun safeAdd(left: Long, right: Long): Long =
            if (Long.MAX_VALUE - left < right) Long.MAX_VALUE else left + right
    }
}
