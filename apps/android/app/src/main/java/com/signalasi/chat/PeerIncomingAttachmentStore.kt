package com.signalasi.chat

import android.content.Context
import android.net.Uri
import android.util.Base64
import androidx.core.content.FileProvider
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Durable, integrity-checked receive side of phone-to-phone attachment transfer. */
internal object PeerIncomingAttachmentStore {
    private const val ROOT = "peer-incoming-attachments-v1"
    private const val MANIFEST = "manifest.json"
    private const val CHUNKS = "chunks"
    private const val DATA = "data.bin"
    private const val MAX_AGE_MILLIS = 30L * 24L * 60L * 60L * 1_000L
    private val sha256Pattern = Regex("[a-f0-9]{64}")

    @Synchronized
    fun ingest(
        context: Context,
        payload: JSONObject,
        sourceId: String,
        routes: SignalASILinkProtocol.Routes
    ): JSONObject? {
        prune(context)
        return when (payload.optString("type")) {
            "input_attachment_manifest" -> ingestManifest(context, payload, sourceId, routes)
            "input_attachment_chunk" -> ingestChunk(context, payload, sourceId, routes)
            else -> null
        }
    }

    @Synchronized
    fun resolveMessageAttachments(
        context: Context,
        sourceId: String,
        payload: JSONObject
    ): JSONArray? {
        val source = payload.optJSONArray("attachments") ?: return JSONArray()
        val resolved = JSONArray()
        for (index in 0 until source.length()) {
            val descriptor = source.optJSONObject(index) ?: return null
            val transferId = descriptor.optString("transfer_id").lowercase()
            val stored = storedAttachment(context, transferId, sourceId) ?: return null
            if (descriptor.optString("sha256").lowercase() != stored.sha256 ||
                descriptor.optLong("size", descriptor.optLong("size_bytes")) != stored.sizeBytes
            ) return null
            resolved.put(JSONObject(descriptor.toString()).apply {
                put("name", stored.name)
                put("mime_type", stored.mimeType)
                put("size_bytes", stored.sizeBytes)
                put("uri", contentUri(context, stored.dataFile).toString())
                payload.optLong("duration_ms", 0L).takeIf { stored.mimeType.startsWith("audio/") }
                    ?.let { put("duration_ms", it) }
            })
        }
        return resolved
    }

    @Synchronized
    fun saveToDownloads(context: Context, attachment: PeerChatAttachment): Result<String> = runCatching {
        val source = attachment.resolvedUri(context) ?: error("Attachment is unavailable")
        val resolver = context.contentResolver
        val values = android.content.ContentValues().apply {
            put(android.provider.MediaStore.Downloads.DISPLAY_NAME, safeName(attachment.name))
            put(android.provider.MediaStore.Downloads.MIME_TYPE, attachment.mimeType)
            put(
                android.provider.MediaStore.Downloads.RELATIVE_PATH,
                android.os.Environment.DIRECTORY_DOWNLOADS + "/SignalASI"
            )
            put(android.provider.MediaStore.Downloads.IS_PENDING, 1)
        }
        val destination = resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("Downloads is unavailable")
        try {
            resolver.openInputStream(source)?.use { input ->
                resolver.openOutputStream(destination)?.use(input::copyTo)
                    ?: error("Download destination is unavailable")
            } ?: error("Attachment is unavailable")
            resolver.update(
                destination,
                android.content.ContentValues().apply {
                    put(android.provider.MediaStore.Downloads.IS_PENDING, 0)
                },
                null,
                null
            )
            destination.toString()
        } catch (error: Throwable) {
            resolver.delete(destination, null, null)
            throw error
        }
    }

    @Synchronized
    fun deleteLocalCopies(context: Context, attachments: List<PeerChatAttachment>) {
        attachments.forEach { attachment ->
            attachment.transferId.lowercase()
                .takeIf { it.matches(sha256Pattern) }
                ?.let { transferDirectory(context, it).deleteRecursively() }

            val localUri = runCatching { Uri.parse(attachment.uri) }.getOrNull()
            if (localUri?.scheme != "file") return@forEach
            val localFile = localUri.path?.let(::File) ?: return@forEach
            val canonical = runCatching { localFile.canonicalFile }.getOrNull() ?: return@forEach
            val privateRoots = listOf(context.cacheDir, context.filesDir).mapNotNull { root ->
                runCatching { root.canonicalFile }.getOrNull()
            }
            if (privateRoots.any { root -> canonical.toPath().startsWith(root.toPath()) }) {
                canonical.delete()
            }
        }
    }

    private fun ingestManifest(
        context: Context,
        payload: JSONObject,
        sourceId: String,
        routes: SignalASILinkProtocol.Routes
    ): JSONObject? {
        val normalized = normalizedManifest(payload, sourceId, routes) ?: return null
        val transferId = normalized.getString("transfer_id")
        val directory = transferDirectory(context, transferId)
        val existing = readManifest(directory)
        if (existing != null && !sameTransfer(existing, normalized)) {
            directory.deleteRecursively()
        }
        if (!directory.exists() && !directory.mkdirs()) return null
        writeJson(File(directory, MANIFEST), normalized)
        File(directory, CHUNKS).mkdirs()
        val stored = storedAttachment(context, transferId, sourceId)
        if (stored != null) return receipt(normalized, "stored")
        if (!payload.optBoolean("resume")) return null
        return receipt(normalized, "missing").put(
            "missing_ranges",
            AgentAttachmentTransferProtocol.missingRanges(missingChunkIndices(directory, normalized))
        )
    }

    private fun ingestChunk(
        context: Context,
        payload: JSONObject,
        sourceId: String,
        routes: SignalASILinkProtocol.Routes
    ): JSONObject? {
        val transferId = payload.optString("transfer_id").lowercase()
        if (!transferId.matches(sha256Pattern)) return null
        val directory = transferDirectory(context, transferId)
        val manifest = readManifest(directory) ?: return null
        if (!manifestMatchesPayload(manifest, payload, sourceId, routes)) return null
        val chunkCount = manifest.getInt("chunk_count")
        val index = payload.optInt("chunk_index", -1)
        if (index !in 0 until chunkCount) return null
        val bytes = runCatching { Base64.decode(payload.getString("data_b64"), Base64.DEFAULT) }
            .getOrNull() ?: return null
        val expectedSize = expectedChunkSize(manifest.getLong("size_bytes"), index)
        if (bytes.size != expectedSize ||
            payload.optInt("chunk_size", -1) != expectedSize ||
            payload.optString("chunk_sha256").lowercase() != sha256(bytes)
        ) return null
        val chunkFile = chunkFile(directory, index)
        if (!chunkFile.isFile || chunkFile.length() != bytes.size.toLong() || sha256(chunkFile) != sha256(bytes)) {
            val temporary = File(chunkFile.parentFile, ".${chunkFile.name}.tmp")
            temporary.writeBytes(bytes)
            if (chunkFile.exists()) chunkFile.delete()
            if (!temporary.renameTo(chunkFile)) {
                temporary.delete()
                return null
            }
        }
        if (missingChunkIndices(directory, manifest).isNotEmpty()) return null
        val assembled = File(directory, ".assembling")
        assembled.outputStream().buffered().use { output ->
            for (chunkIndex in 0 until chunkCount) {
                chunkFile(directory, chunkIndex).inputStream().buffered().use { it.copyTo(output) }
            }
        }
        if (assembled.length() != manifest.getLong("size_bytes") ||
            sha256(assembled) != manifest.getString("sha256")
        ) {
            assembled.delete()
            File(directory, CHUNKS).deleteRecursively()
            File(directory, CHUNKS).mkdirs()
            return receipt(manifest, "missing").put(
                "missing_ranges",
                AgentAttachmentTransferProtocol.missingRanges((0 until chunkCount).toList())
            )
        }
        val destination = File(directory, DATA)
        destination.delete()
        if (!assembled.renameTo(destination)) {
            assembled.delete()
            return null
        }
        File(directory, CHUNKS).deleteRecursively()
        return receipt(manifest, "stored")
    }

    private fun normalizedManifest(
        payload: JSONObject,
        sourceId: String,
        routes: SignalASILinkProtocol.Routes
    ): JSONObject? = runCatching {
        val transferId = payload.getString("transfer_id").lowercase()
        val digest = payload.getString("sha256").lowercase()
        val size = payload.getLong("size_bytes")
        val chunkCount = payload.getInt("chunk_count")
        require(transferId.matches(sha256Pattern) && digest.matches(sha256Pattern))
        require(size in 1..AgentOutboundAttachmentTransferStore.MAX_ATTACHMENT_BYTES)
        require(chunkCount == ((size + AgentOutboundAttachmentTransferStore.CHUNK_BYTES - 1) /
            AgentOutboundAttachmentTransferStore.CHUNK_BYTES).toInt())
        require(chunkCount in 1..AgentOutboundAttachmentTransferStore.MAX_CHUNKS)
        require(payload.optString("client_route_id") == routes.clientRouteId)
        require(payload.optString("contact_id") == SignalASICrypto.localSignalasiId())
        require(sourceId.isNotBlank())
        JSONObject(payload.toString())
            .put("source_id", sourceId)
            .put("received_at", System.currentTimeMillis())
            .put("name", safeName(payload.optString("name").ifBlank { "attachment" }))
            .put("mime_type", payload.optString("mime_type").ifBlank { "application/octet-stream" })
    }.getOrNull()

    private fun manifestMatchesPayload(
        manifest: JSONObject,
        payload: JSONObject,
        sourceId: String,
        routes: SignalASILinkProtocol.Routes
    ): Boolean = manifest.optString("source_id") == sourceId &&
        manifest.optString("client_route_id") == routes.clientRouteId &&
        manifest.optString("transfer_id") == payload.optString("transfer_id").lowercase() &&
        manifest.optString("sha256") == payload.optString("sha256").lowercase() &&
        manifest.optLong("size_bytes") == payload.optLong("size_bytes") &&
        manifest.optInt("chunk_count") == payload.optInt("chunk_count")

    private fun sameTransfer(first: JSONObject, second: JSONObject): Boolean =
        first.optString("source_id") == second.optString("source_id") &&
            first.optString("sha256") == second.optString("sha256") &&
            first.optLong("size_bytes") == second.optLong("size_bytes") &&
            first.optInt("chunk_count") == second.optInt("chunk_count")

    private fun receipt(manifest: JSONObject, status: String): JSONObject = JSONObject()
        .put("type", "input_attachment_receipt")
        .put("status", status)
        .put("transfer_id", manifest.getString("transfer_id"))
        .put("sha256", manifest.getString("sha256"))
        .put("client_route_id", manifest.getString("client_route_id"))
        .put("conversation_id", manifest.getString("conversation_id"))
        .put("task_id", manifest.getString("task_id"))
        .put("turn_id", manifest.getString("turn_id"))
        .put("contact_id", SignalASICrypto.localSignalasiId())
        .put("source_message_id", manifest.optString("client_message_id"))
        .put("peer_chat", true)
        .put("time", System.currentTimeMillis())

    private data class StoredAttachment(
        val name: String,
        val mimeType: String,
        val sizeBytes: Long,
        val sha256: String,
        val dataFile: File
    )

    private fun storedAttachment(context: Context, transferId: String, sourceId: String): StoredAttachment? {
        if (!transferId.matches(sha256Pattern)) return null
        val directory = transferDirectory(context, transferId)
        val manifest = readManifest(directory) ?: return null
        val data = File(directory, DATA)
        if (manifest.optString("source_id") != sourceId ||
            !data.isFile || data.length() != manifest.optLong("size_bytes") ||
            sha256(data) != manifest.optString("sha256")
        ) return null
        return StoredAttachment(
            manifest.optString("name", "attachment"),
            manifest.optString("mime_type", "application/octet-stream"),
            data.length(),
            manifest.getString("sha256"),
            data
        )
    }

    private fun missingChunkIndices(directory: File, manifest: JSONObject): List<Int> =
        (0 until manifest.getInt("chunk_count")).filter { index ->
            val file = chunkFile(directory, index)
            !file.isFile || file.length() != expectedChunkSize(manifest.getLong("size_bytes"), index).toLong()
        }

    private fun expectedChunkSize(size: Long, index: Int): Int = minOf(
        AgentOutboundAttachmentTransferStore.CHUNK_BYTES.toLong(),
        size - index.toLong() * AgentOutboundAttachmentTransferStore.CHUNK_BYTES
    ).toInt()

    private fun contentUri(context: Context, file: File): Uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.files",
        file
    )

    private fun root(context: Context): File = File(context.filesDir, ROOT).apply { mkdirs() }
    private fun transferDirectory(context: Context, transferId: String) = File(root(context), transferId)
    private fun chunkFile(directory: File, index: Int) =
        File(File(directory, CHUNKS).apply { mkdirs() }, "chunk-${index.toString().padStart(6, '0')}.bin")

    private fun readManifest(directory: File): JSONObject? = runCatching {
        JSONObject(File(directory, MANIFEST).readText(Charsets.UTF_8))
    }.getOrNull()

    private fun writeJson(file: File, value: JSONObject) {
        val temporary = File(file.parentFile, ".${file.name}.tmp")
        temporary.writeText(value.toString(), Charsets.UTF_8)
        file.delete()
        check(temporary.renameTo(file)) { "Attachment manifest could not be committed" }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }

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

    private fun safeName(value: String): String = value
        .replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_")
        .trim().take(160).ifBlank { "attachment" }

    private fun prune(context: Context, now: Long = System.currentTimeMillis()) {
        root(context).listFiles().orEmpty().filter(File::isDirectory).forEach { directory ->
            val manifest = readManifest(directory)
            val receivedAt = manifest?.optLong("received_at", directory.lastModified()) ?: 0L
            if (PeerMessageAttachmentStore.shouldPruneIncoming(
                    receivedAt = receivedAt,
                    hasCompletedData = File(directory, DATA).isFile,
                    now = now,
                    maxAgeMillis = MAX_AGE_MILLIS
                )
            ) {
                directory.deleteRecursively()
            }
        }
    }
}
