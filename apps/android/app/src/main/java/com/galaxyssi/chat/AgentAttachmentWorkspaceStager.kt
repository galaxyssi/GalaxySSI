package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

data class AgentStagedAttachment(
    val attachmentId: String,
    val name: String,
    val relativePath: String,
    val mimeType: String,
    val sizeBytes: Long,
    val sha256: String
)

/** Copies user-authorized content into the active conversation's app-private project. */
object AgentAttachmentWorkspaceStager {
    fun stage(
        context: Context,
        conversationId: String,
        turnId: String,
        attachments: List<AgentInputAttachment>
    ): List<AgentStagedAttachment> {
        require(turnId.matches(SAFE_ID)) { "Attachment turn ID is invalid" }
        val workspaceId = AgentWorkspaceScope.id(conversationId)
        return AgentWorkspaceScope.withLock(workspaceId) {
            val projectRoot = File(context.applicationContext.filesDir, "agent-native-workspaces")
            val workspace = File(projectRoot, workspaceId).canonicalFile
            val inputDirectory = File(workspace, "inputs/$turnId").canonicalFile
            require(inputDirectory.path.startsWith(workspace.path + File.separator)) { "Attachment path is unsafe" }
            check(inputDirectory.mkdirs() || inputDirectory.isDirectory) { "Attachment workspace is unavailable" }
            var totalBytes = 0L
            val staged = attachments.mapIndexed { index, attachment ->
                val safeName = uniqueName(inputDirectory, sanitizeName(attachment.displayName), index)
                val target = File(inputDirectory, safeName)
                val temporary = File(inputDirectory, ".$safeName.part")
                val digest = MessageDigest.getInstance("SHA-256")
                var size = 0L
                try {
                    val input = context.contentResolver.openInputStream(attachment.uri)
                        ?: error("Attachment content is unavailable: ${attachment.displayName}")
                    input.buffered().use { source ->
                        temporary.outputStream().buffered().use { destination ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                val read = source.read(buffer)
                                if (read < 0) break
                                size += read
                                totalBytes += read
                                check(size <= MAX_ATTACHMENT_BYTES && totalBytes <= MAX_TURN_BYTES) {
                                    "Attachment input exceeds the workspace limit"
                                }
                                digest.update(buffer, 0, read)
                                destination.write(buffer, 0, read)
                            }
                        }
                    }
                    check(temporary.renameTo(target)) { "Attachment could not be committed" }
                } finally {
                    temporary.delete()
                }
                AgentStagedAttachment(
                    attachmentId = attachment.id,
                    name = attachment.displayName,
                    relativePath = "inputs/$turnId/$safeName",
                    mimeType = attachment.mimeType,
                    sizeBytes = size,
                    sha256 = digest.digest().joinToString("") { "%02x".format(it) }
                )
            }
            writeManifest(inputDirectory, staged)
            staged
        }
    }

    fun restore(
        context: Context,
        conversationId: String,
        turnId: String,
        blocks: List<AgentRichBlock>
    ): List<AgentInputAttachment> {
        if (!turnId.matches(SAFE_ID) || blocks.isEmpty()) return emptyList()
        val workspaceId = AgentWorkspaceScope.id(conversationId)
        return AgentWorkspaceScope.withLock(workspaceId) {
            val projectRoot = File(context.applicationContext.filesDir, "agent-native-workspaces")
            val workspace = File(projectRoot, workspaceId).canonicalFile
            val inputDirectory = File(workspace, "inputs/$turnId").canonicalFile
            if (
                !inputDirectory.path.startsWith(workspace.path + File.separator) ||
                !inputDirectory.isDirectory
            ) return@withLock emptyList()
            val manifest = readManifest(inputDirectory)
            if (manifest.isEmpty()) return@withLock emptyList()
            val unused = manifest.toMutableList()
            blocks.asSequence()
                .filter { block ->
                    block.type in ATTACHMENT_TYPES &&
                        block.metadata["source"].orEmpty() == "user_attachment"
                }
                .take(MAX_RESTORED_ATTACHMENTS)
                .mapNotNull { block ->
                    val record = unused.firstOrNull {
                        it.attachmentId == block.id && block.id.isNotBlank()
                    } ?: unused.firstOrNull {
                        it.name.equals(block.title, ignoreCase = true)
                    } ?: return@mapNotNull null
                    unused.remove(record)
                    val relative = record.relativePath.replace('\\', '/').trim('/')
                    if (!relative.startsWith("inputs/$turnId/")) return@mapNotNull null
                    val source = File(workspace, relative).canonicalFile
                    if (
                        !source.path.startsWith(inputDirectory.path + File.separator) ||
                        !source.isFile ||
                        source.length() != record.sizeBytes ||
                        sha256(source) != record.sha256
                    ) return@mapNotNull null
                    AgentInputAttachment(
                        id = block.id.ifBlank { record.attachmentId },
                        uri = Uri.fromFile(source),
                        displayName = record.name,
                        mimeType = record.mimeType.ifBlank {
                            block.mimeType.ifBlank { "application/octet-stream" }
                        },
                        sizeBytes = record.sizeBytes
                    )
                }
                .toList()
        }
    }

    fun restoreByIds(
        context: Context,
        conversationId: String,
        attachmentIds: Collection<String>
    ): List<AgentInputAttachment> {
        val requested = attachmentIds.asSequence()
            .map(String::trim)
            .filter { it.isNotBlank() && it.length <= 120 }
            .distinct()
            .take(MAX_RESTORED_ATTACHMENTS)
            .toList()
        if (requested.isEmpty()) return emptyList()
        val workspaceId = AgentWorkspaceScope.id(conversationId)
        return AgentWorkspaceScope.withLock(workspaceId) {
            val projectRoot = File(context.applicationContext.filesDir, "agent-native-workspaces")
            val workspace = File(projectRoot, workspaceId).canonicalFile
            val inputsRoot = File(workspace, "inputs").canonicalFile
            if (
                !inputsRoot.path.startsWith(workspace.path + File.separator) ||
                !inputsRoot.isDirectory
            ) return@withLock emptyList()
            val records = inputsRoot.listFiles()
                .orEmpty()
                .filter(File::isDirectory)
                .sortedByDescending(File::lastModified)
                .flatMap { directory ->
                    readManifest(directory).map { record -> directory to record }
                }
            requested.mapNotNull { attachmentId ->
                val (directory, record) = records.firstOrNull { (_, candidate) ->
                    candidate.attachmentId == attachmentId
                } ?: return@mapNotNull null
                restoreRecord(workspace, directory, record, attachmentId)
            }
        }
    }

    private fun restoreRecord(
        workspace: File,
        inputDirectory: File,
        record: AgentStagedAttachment,
        attachmentId: String
    ): AgentInputAttachment? {
        val relative = record.relativePath.replace('\\', '/').trim('/')
        if (!relative.startsWith("inputs/${inputDirectory.name}/")) return null
        val source = File(workspace, relative).canonicalFile
        if (
            !source.path.startsWith(inputDirectory.canonicalPath + File.separator) ||
            !source.isFile ||
            source.length() != record.sizeBytes ||
            sha256(source) != record.sha256
        ) return null
        return AgentInputAttachment(
            id = attachmentId,
            uri = Uri.fromFile(source),
            displayName = record.name,
            mimeType = record.mimeType.ifBlank { "application/octet-stream" },
            sizeBytes = record.sizeBytes
        )
    }

    private fun writeManifest(directory: File, attachments: List<AgentStagedAttachment>) {
        val target = File(directory, MANIFEST_FILE)
        val temporary = File(directory, "$MANIFEST_FILE.tmp")
        val payload = JSONObject()
            .put("version", 1)
            .put("attachments", JSONArray().apply {
                attachments.forEach { attachment ->
                    put(
                        JSONObject()
                            .put("attachment_id", attachment.attachmentId)
                            .put("name", attachment.name)
                            .put("relative_path", attachment.relativePath)
                            .put("mime_type", attachment.mimeType)
                            .put("size_bytes", attachment.sizeBytes)
                            .put("sha256", attachment.sha256)
                    )
                }
            })
            .toString()
        temporary.writeText(payload, Charsets.UTF_8)
        if (target.exists()) target.delete()
        check(temporary.renameTo(target)) { "Attachment manifest could not be committed" }
    }

    private fun readManifest(directory: File): List<AgentStagedAttachment> = runCatching {
        val root = JSONObject(File(directory, MANIFEST_FILE).readText(Charsets.UTF_8))
        require(root.optInt("version") == 1)
        val values = root.optJSONArray("attachments") ?: JSONArray()
        buildList {
            for (index in 0 until minOf(values.length(), MAX_RESTORED_ATTACHMENTS)) {
                val item = values.optJSONObject(index) ?: continue
                val digest = item.optString("sha256").lowercase()
                val size = item.optLong("size_bytes", -1L)
                if (!digest.matches(SHA256) || size !in 1..MAX_ATTACHMENT_BYTES) continue
                add(
                    AgentStagedAttachment(
                        attachmentId = item.optString("attachment_id").take(256),
                        name = item.optString("name").take(180),
                        relativePath = item.optString("relative_path").take(512),
                        mimeType = item.optString("mime_type").take(160),
                        sizeBytes = size,
                        sha256 = digest
                    )
                )
            }
        }
    }.getOrDefault(emptyList())

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun sanitizeName(value: String): String {
        val cleaned = value.trim()
            .replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_")
            .replace(Regex("\\s+"), " ")
            .trim('.', ' ')
            .take(120)
        return cleaned.ifBlank { "attachment" }
    }

    private fun uniqueName(directory: File, baseName: String, index: Int): String {
        if (!File(directory, baseName).exists()) return baseName
        val extension = baseName.substringAfterLast('.', "").takeIf { it.isNotBlank() }
        val stem = if (extension == null) baseName else baseName.removeSuffix(".$extension")
        var suffix = index + 1
        while (true) {
            val candidate = "$stem-$suffix${extension?.let { ".$it" }.orEmpty()}"
            if (!File(directory, candidate).exists()) return candidate
            suffix += 1
        }
    }

    private const val MAX_ATTACHMENT_BYTES = 256L * 1024L * 1024L
    private const val MAX_TURN_BYTES = 512L * 1024L * 1024L
    private const val MAX_RESTORED_ATTACHMENTS = 10
    private const val MANIFEST_FILE = ".galaxyssi-attachments.json"
    private val ATTACHMENT_TYPES = setOf(
        AgentRichBlockType.IMAGE,
        AgentRichBlockType.FILE,
        AgentRichBlockType.VIDEO,
        AgentRichBlockType.AUDIO
    )
    private val SHA256 = Regex("[a-f0-9]{64}")
    private val SAFE_ID = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
}
