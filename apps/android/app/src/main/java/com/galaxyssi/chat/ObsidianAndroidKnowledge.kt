package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import org.json.JSONObject
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

data class ObsidianAndroidSettings(
    val enabled: Boolean = false,
    val treeUri: String = "",
    val vaultName: String = "",
    val lastProjectionAtMillis: Long = 0L,
    val lastError: String = ""
)

enum class ObsidianEditCandidateStatus { PENDING, APPROVED, REJECTED }

data class ObsidianEditCandidate(
    val id: String,
    val sourceKey: String,
    val relativePath: String,
    val title: String,
    val content: String,
    val status: ObsidianEditCandidateStatus = ObsidianEditCandidateStatus.PENDING,
    val detectedAtMillis: Long = System.currentTimeMillis(),
    val reviewedAtMillis: Long = 0L
)

data class ObsidianProjectionResult(
    val configured: Boolean,
    val writtenCount: Int = 0,
    val unchangedCount: Int = 0,
    val candidateCount: Int = 0,
    val remainingCount: Int = 0,
    val error: String = ""
)

internal data class ObsidianProjectionIndexEntry(
    val sourceKey: String,
    val relativePath: String,
    val sourceRevision: String,
    val generatedHash: String,
    val lastModifiedMillis: Long,
    val userModified: Boolean = false
)

internal data class ObsidianProjectionSpec(
    val sourceKey: String,
    val relativePath: String,
    val sourceRevision: String,
    val knowledgeReference: AgentKnowledgeSourceReference? = null,
    val retiredSourceKey: String = "",
    val content: () -> String
)

internal class ObsidianAndroidStateStore(context: Context, databaseName: String = DATABASE, preferencesName: String = PREFERENCES) {
    private val preferences = AgentEncryptedPreferences(context.applicationContext, preferencesName)
    private val database = AgentEncryptedDatabase(context.applicationContext, databaseName)

    fun settings(): ObsidianAndroidSettings = runCatching {
        val json = JSONObject(preferences.readString(KEY_SETTINGS, "{}"))
        ObsidianAndroidSettings(
            enabled = json.optBoolean("enabled"),
            treeUri = json.optString("tree_uri"),
            vaultName = json.optString("vault_name"),
            lastProjectionAtMillis = json.optLong("last_projection_at_millis"),
            lastError = json.optString("last_error")
        )
    }.getOrDefault(ObsidianAndroidSettings())

    fun saveSettings(value: ObsidianAndroidSettings) {
        preferences.writeString(KEY_SETTINGS, JSONObject()
            .put("enabled", value.enabled)
            .put("tree_uri", value.treeUri)
            .put("vault_name", value.vaultName)
            .put("last_projection_at_millis", value.lastProjectionAtMillis)
            .put("last_error", value.lastError.take(600))
            .toString())
    }

    fun index(): List<ObsidianProjectionIndexEntry> = database.entries(INDEX_PREFIX)
        .mapNotNull { (_, raw) -> decodeIndex(raw) }

    fun index(sourceKey: String): ObsidianProjectionIndexEntry? = decodeIndex(
        database.readString("$INDEX_PREFIX$sourceKey", "")
    )

    fun saveIndex(value: ObsidianProjectionIndexEntry, retiredSourceKey: String = "") {
        val encoded = JSONObject()
            .put("source_key", value.sourceKey)
            .put("relative_path", value.relativePath)
            .put("source_revision", value.sourceRevision)
            .put("generated_hash", value.generatedHash)
            .put("last_modified_millis", value.lastModifiedMillis)
            .put("user_modified", value.userModified)
            .toString()
        if (retiredSourceKey.isBlank() || retiredSourceKey == value.sourceKey) {
            database.writeString("$INDEX_PREFIX${value.sourceKey}", encoded)
        } else database.mutateStrings(mapOf("$INDEX_PREFIX${value.sourceKey}" to encoded),
            listOf("$INDEX_PREFIX$retiredSourceKey"))
    }

    fun removeIndex(sourceKey: String) = database.remove("$INDEX_PREFIX$sourceKey")

    fun projectionCheckpoint() = ObsidianProjectionCheckpoint.decode(database.readString("knowledge_projection_cursor_v1", ""))
    fun saveProjectionCheckpoint(value: ObsidianProjectionCheckpoint?) {
        if (value == null) database.remove("knowledge_projection_cursor_v1")
        else database.writeString("knowledge_projection_cursor_v1", value.encode())
    }

    fun candidates(status: ObsidianEditCandidateStatus? = null): List<ObsidianEditCandidate> =
        database.entries(CANDIDATE_PREFIX)
            .mapNotNull { (_, raw) -> decodeCandidate(raw) }
            .filter { status == null || it.status == status }
            .sortedByDescending(ObsidianEditCandidate::detectedAtMillis)

    fun saveCandidate(value: ObsidianEditCandidate) {
        database.writeString("$CANDIDATE_PREFIX${value.id}", JSONObject()
            .put("id", value.id)
            .put("source_key", value.sourceKey)
            .put("relative_path", value.relativePath)
            .put("title", value.title)
            .put("content", value.content)
            .put("status", value.status.name)
            .put("detected_at_millis", value.detectedAtMillis)
            .put("reviewed_at_millis", value.reviewedAtMillis)
            .toString())
    }

    fun editScanPage(limit: Int): Pair<List<ObsidianProjectionIndexEntry>, String> {
        require(limit in 1..50)
        val after = database.readString(KEY_EDIT_SCAN_CURSOR, "").takeIf { it.startsWith(INDEX_PREFIX) }.orEmpty()
        val keys = database.keysAfter(INDEX_PREFIX, after, limit + 1)
        val selected = keys.take(limit)
        return selected.mapNotNull { decodeIndex(database.readString(it, "")) } to
            if (keys.size > limit) selected.last() else ""
    }

    fun saveEditScanCursor(value: String) = database.writeString(KEY_EDIT_SCAN_CURSOR, value)

    private fun decodeIndex(raw: String): ObsidianProjectionIndexEntry? = runCatching {
        if (raw.isBlank()) return@runCatching null
        val json = JSONObject(raw)
        ObsidianProjectionIndexEntry(
            sourceKey = json.getString("source_key"),
            relativePath = json.getString("relative_path"),
            sourceRevision = json.optString("source_revision"),
            generatedHash = json.optString("generated_hash"),
            lastModifiedMillis = json.optLong("last_modified_millis"),
            userModified = json.optBoolean("user_modified")
        )
    }.getOrNull()

    private fun decodeCandidate(raw: String): ObsidianEditCandidate? = runCatching {
        val json = JSONObject(raw)
        ObsidianEditCandidate(
            id = json.getString("id"),
            sourceKey = json.getString("source_key"),
            relativePath = json.getString("relative_path"),
            title = json.optString("title"),
            content = json.optString("content"),
            status = enumValues<ObsidianEditCandidateStatus>().firstOrNull {
                it.name == json.optString("status")
            } ?: ObsidianEditCandidateStatus.PENDING,
            detectedAtMillis = json.optLong("detected_at_millis"),
            reviewedAtMillis = json.optLong("reviewed_at_millis")
        )
    }.getOrNull()

    private companion object {
        const val PREFERENCES = "galaxyssi_obsidian_android_settings_v1"
        const val DATABASE = "galaxyssi_obsidian_android_v1"
        const val KEY_SETTINGS = "settings"
        const val KEY_EDIT_SCAN_CURSOR = "state:edit_scan_key_cursor_v2"
        const val INDEX_PREFIX = "projection:"
        const val CANDIDATE_PREFIX = "candidate:"
    }
}

object ObsidianProjectionPrivacyPolicy {
    fun safeKnowledge(value: String): Boolean = value.isNotBlank() && !sensitive(value)

    fun safeMetadata(value: String): Boolean = value.isBlank() || (
        !sensitive(value) && !METADATA_SECRET_PATTERN.containsMatchIn(value)
    )

    fun transcriptText(value: String): String = if (sensitive(value)) {
        "[Sensitive content omitted by GalaxySSI]"
    } else value.trim()

    private fun sensitive(value: String): Boolean {
        val normalized = value.lowercase(Locale.ROOT)
        return AgentLearningAnalyzer.containsSensitiveData(value) || SENSITIVE_TERMS.any(normalized::contains)
    }

    private val SENSITIVE_TERMS = listOf(
        "identity_key", "identity key", "identity_key_sha256", "private key", "mnemonic",
        "mqtt password", "mqtt_password", "api key", "api_key", "access token", "access_token",
        "refresh token", "refresh_token",
        "galaxyssi fingerprint", "身份指纹", "私钥", "助记词", "mqtt 密码", "api 密钥"
    )
    private val METADATA_SECRET_PATTERN = Regex(
        "(?:[?&]|^)(?:access_token|refresh_token|token|api_key|key|password)=[^&\\s]+",
        RegexOption.IGNORE_CASE
    )
}

object ObsidianAndroidBridge {
    fun settings(context: Context): ObsidianAndroidSettings = ObsidianAndroidStateStore(context).settings()

    fun configure(context: Context, treeUri: Uri): ObsidianAndroidSettings {
        context.contentResolver.takePersistableUriPermission(
            treeUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        val root = requireNotNull(DocumentFile.fromTreeUri(context, treeUri)) { "Vault folder is unavailable" }
        val store = ObsidianAndroidStateStore(context)
        return ObsidianAndroidSettings(
            enabled = true,
            treeUri = treeUri.toString(),
            vaultName = root.name.orEmpty().ifBlank { "Obsidian Vault" }
        ).also {
            store.saveSettings(it)
            AndroidCognitionScheduler.requestObsidianProjection(context)
        }
    }

    fun disconnect(context: Context) {
        val store = ObsidianAndroidStateStore(context)
        val settings = store.settings()
        if (settings.treeUri.isNotBlank()) runCatching {
            context.contentResolver.releasePersistableUriPermission(
                Uri.parse(settings.treeUri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        }
        store.saveSettings(settings.copy(enabled = false, treeUri = "", vaultName = ""))
    }

    fun pendingCandidates(context: Context): List<ObsidianEditCandidate> =
        ObsidianAndroidStateStore(context).candidates(ObsidianEditCandidateStatus.PENDING)

    fun approveCandidate(context: Context, candidateId: String): Boolean {
        val store = ObsidianAndroidStateStore(context)
        val candidate = store.candidates(ObsidianEditCandidateStatus.PENDING)
            .firstOrNull { it.id == candidateId } ?: return false
        val body = stripFrontMatter(candidate.content).trim()
        if (!ObsidianProjectionPrivacyPolicy.safeKnowledge(body)) return false
        SharedPreferencesAgentKnowledgeStore(context).upsert(AgentKnowledgeItem(
            kind = AgentKnowledgeKind.NOTE,
            title = candidate.title.ifBlank { candidate.relativePath.substringAfterLast('/').removeSuffix(".md") },
            content = body,
            source = "obsidian-edit://${candidate.relativePath}",
            tags = listOf("obsidian", "reviewed"),
            cloudAccess = AgentKnowledgeCloudAccess.DENY,
            agentAccess = AgentKnowledgeAgentAccess.LOCAL_ONLY
        ))
        store.saveCandidate(candidate.copy(
            status = ObsidianEditCandidateStatus.APPROVED,
            reviewedAtMillis = System.currentTimeMillis()
        ))
        store.removeIndex(candidate.sourceKey)
        AndroidCognitionScheduler.requestObsidianProjection(context)
        return true
    }

    fun rejectCandidate(context: Context, candidateId: String): Boolean {
        val store = ObsidianAndroidStateStore(context)
        val candidate = store.candidates(ObsidianEditCandidateStatus.PENDING)
            .firstOrNull { it.id == candidateId } ?: return false
        store.saveCandidate(candidate.copy(
            status = ObsidianEditCandidateStatus.REJECTED,
            reviewedAtMillis = System.currentTimeMillis()
        ))
        store.removeIndex(candidate.sourceKey)
        AndroidCognitionScheduler.requestObsidianProjection(context)
        return true
    }

    @Synchronized fun projectIncrementally(context: Context, maximumWrites: Int = 12): ObsidianProjectionResult {
        val store = ObsidianAndroidStateStore(context)
        val settings = store.settings()
        if (!settings.enabled || settings.treeUri.isBlank()) return ObsidianProjectionResult(false)
        return runCatching {
            val root = requireNotNull(DocumentFile.fromTreeUri(context, Uri.parse(settings.treeUri)))
            val newCandidates = scanUserEdits(context, root, store)
            val limit = maximumWrites.coerceIn(1, 32)
            val batch = ObsidianKnowledgeProjection.run(SQLiteAgentKnowledgeStore(context), store, settings.treeUri, limit,
                { spec -> ObsidianLegacyProjection.findIndex(context, root, store, spec) }) { spec, content ->
                store.saveIndex(writeProjection(context, root, spec, content), spec.retiredSourceKey)
            }
            val other = ObsidianProjectionBatch.run(otherProjectionSpecs(context).asSequence(), limit - batch.written, store::index) { spec, content ->
                store.saveIndex(writeProjection(context, root, spec, content))
            }
            store.saveSettings(settings.copy(
                lastProjectionAtMillis = System.currentTimeMillis(),
                lastError = ""
            ))
            ObsidianProjectionResult(true, batch.written + other.written, batch.unchanged + other.unchanged,
                newCandidates, batch.remaining + other.remaining)
        }.getOrElse { error ->
            store.saveSettings(settings.copy(lastError = error.message.orEmpty().take(600)))
            ObsidianProjectionResult(true, error = error.message.orEmpty().take(600))
        }
    }

    internal fun writeProjection(context: Context, root: DocumentFile, spec: ObsidianProjectionSpec,
        content: String): ObsidianProjectionIndexEntry {
        val document = findOrCreateFile(root, spec.relativePath)
        val bytes = content.toByteArray(Charsets.UTF_8)
        try {
            context.contentResolver.openOutputStream(document.uri, "wt")?.use { it.write(bytes) }
                ?: error("Cannot write ${spec.relativePath}")
        } finally { bytes.fill(0) }
        return ObsidianProjectionIndexEntry(spec.sourceKey, spec.relativePath, spec.sourceRevision,
            sha256(content), document.lastModified(), userModified = false)
    }

    internal fun scanUserEdits(
        context: Context,
        root: DocumentFile,
        store: ObsidianAndroidStateStore
    ): Int {
        val (page, next) = store.editScanPage(MAX_EDIT_SCANS)
        val selected = page.filterNot(ObsidianProjectionIndexEntry::userModified)
        var found = 0
        selected.forEach { entry ->
            val document = findFile(root, entry.relativePath) ?: return@forEach
            if (document.lastModified() > 0L && document.lastModified() == entry.lastModifiedMillis) return@forEach
            val content = context.contentResolver.openInputStream(document.uri)?.bufferedReader()?.use { it.readText() }
                ?: return@forEach
            val currentHash = sha256(content)
            if (currentHash == entry.generatedHash) {
                store.saveIndex(entry.copy(lastModifiedMillis = document.lastModified()))
                return@forEach
            }
            val existing = store.candidates(ObsidianEditCandidateStatus.PENDING)
                .any { it.sourceKey == entry.sourceKey && sha256(it.content) == currentHash }
            if (!existing) {
                store.saveCandidate(ObsidianEditCandidate(
                    id = UUID.randomUUID().toString(),
                    sourceKey = entry.sourceKey,
                    relativePath = entry.relativePath,
                    title = entry.relativePath.substringAfterLast('/').removeSuffix(".md"),
                    content = content.take(MAX_CANDIDATE_CHARACTERS)
                ))
                found += 1
            }
            store.saveIndex(entry.copy(userModified = true, lastModifiedMillis = document.lastModified()))
        }
        store.saveEditScanCursor(next)
        return found
    }

    private fun otherProjectionSpecs(context: Context): List<ObsidianProjectionSpec> = buildList {
        EncryptedAgentSkillStore(context).list().forEach { installation ->
            val manifest = installation.manifest
            val sourceKey = "skill:${manifest.id}:${manifest.version}"
            val revision = GlobalAgentText.stableKey(sourceKey, installation.updatedAtMillis.toString(), manifest.instructions)
            add(ObsidianProjectionSpec(sourceKey, "30 Skills/${fileName(manifest.title, sourceKey)}", revision) {
                note(
                    sourceKey,
                    "skill",
                    manifest.title,
                    manifest.source,
                    installation.updatedAtMillis,
                    listOf("skill"),
                    buildString {
                        if (manifest.description.isNotBlank()) append(manifest.description).append("\n\n")
                        append(manifest.instructions)
                        if (manifest.steps.isNotEmpty()) {
                            append("\n\n## Steps\n")
                            manifest.steps.forEachIndexed { index, step ->
                                append(index + 1).append(". `").append(step.toolId).append("`\n")
                            }
                        }
                    }
                )
            })
        }

        val runtime = GlobalSuperAgentRuntime.get(context)
        val world = runtime.worldSnapshot()
        val planItems = world.items.filter { item ->
            item.kind in setOf(GlobalWorldItemKind.GOAL, GlobalWorldItemKind.TASK, GlobalWorldItemKind.DECISION) &&
                item.status != GlobalWorldItemStatus.SUPERSEDED
        }
        if (planItems.isNotEmpty()) {
            add(ObsidianProjectionSpec("plans:current", "50 Plans/GalaxySSI plans.md", world.updatedAtMillis.toString()) {
                note("plans:current", "plan", "GalaxySSI plans", "GalaxySSI world model", world.updatedAtMillis, listOf("plan"),
                    planItems.joinToString("\n") { item -> "- [${if (item.status == GlobalWorldItemStatus.COMPLETED) "x" else " "}] ${item.value}" })
            })
        }

        val insights = runtime.proactiveInboxItems(limit = 100)
        if (insights.isNotEmpty()) {
            val revision = GlobalAgentText.stableKey(insights.joinToString("|") {
                "${it.key}:${it.messageIds.sorted().joinToString(",")}:${it.viewedAtMillis}:${it.feedbackKind}"
            })
            add(ObsidianProjectionSpec("insights:current", "40 Insights/GalaxySSI insights.md", revision) {
                note("insights:current", "insight", "GalaxySSI insights", "GalaxySSI proactive cognition", System.currentTimeMillis(), listOf("insight"),
                    insights.joinToString("\n\n") { insight -> "## ${insight.title}\n${insight.content}" })
            })
        }

        val transcriptStore = AgentTranscriptStore(context)
        transcriptStore.conversations(includeArchived = true)
            .filterNot { it.privateMode || it.trackingPaused }
            .forEach { conversation ->
                val sourceKey = "agent-conversation:${conversation.id}"
                val revision = GlobalAgentText.stableKey(
                    conversation.updatedAt.toString(),
                    conversation.latestMessageEntryId,
                    conversation.latestMessageTimestampMillis.toString()
                )
                add(ObsidianProjectionSpec(
                    sourceKey,
                    "70 Agent Conversations/${fileName(conversation.title, sourceKey)}",
                    revision
                ) {
                    val body = transcriptStore.list(conversation.id)
                        .filter { it.role in setOf(AgentTranscriptRole.USER, AgentTranscriptRole.ASSISTANT) }
                        .joinToString("\n\n") { entry ->
                            val role = if (entry.role == AgentTranscriptRole.USER) "You" else "GalaxySSI"
                            "### $role\n${ObsidianProjectionPrivacyPolicy.transcriptText(entry.text)}"
                        }
                    note(sourceKey, "agent_conversation", conversation.title, "GalaxySSI Agent", conversation.updatedAt,
                        listOf("agent-conversation"), body)
                })
            }
    }

    internal fun note(
        sourceKey: String,
        type: String,
        title: String,
        source: String,
        updatedAtMillis: Long,
        tags: List<String>,
        body: String
    ): String {
        val cleanBody = ObsidianProjectionPrivacyPolicy.transcriptText(body).trim()
        val cleanTitle = title.trim()
            .takeIf(ObsidianProjectionPrivacyPolicy::safeMetadata)
            .orEmpty()
            .ifBlank { "GalaxySSI" }
        val cleanSource = source.trim().takeIf(ObsidianProjectionPrivacyPolicy::safeMetadata).orEmpty()
        val cleanTags = tags.filter(ObsidianProjectionPrivacyPolicy::safeMetadata)
        return buildString {
            append("---\n")
            append("galaxyssi_id: \"").append(yaml(sourceKey)).append("\"\n")
            append("galaxyssi_type: \"").append(yaml(type)).append("\"\n")
            append("status: current\n")
            append("title: \"").append(yaml(cleanTitle)).append("\"\n")
            if (cleanSource.isNotBlank()) append("source: \"").append(yaml(cleanSource)).append("\"\n")
            append("updated_at: \"").append(isoDate(updatedAtMillis)).append("\"\n")
            append("content_hash: \"").append(sha256(cleanBody)).append("\"\n")
            append("managed_by: galaxyssi\n")
            if (cleanTags.isNotEmpty()) append("tags: [").append(cleanTags.joinToString(", ") { "\"${yaml(it)}\"" }).append("]\n")
            append("---\n\n# ").append(cleanTitle).append("\n\n")
            append(cleanBody)
            append('\n')
        }
    }

    private fun findOrCreateFile(root: DocumentFile, relativePath: String): DocumentFile {
        val segments = relativePath.split('/').filter(String::isNotBlank)
        require(segments.isNotEmpty())
        var directory = root
        segments.dropLast(1).forEach { name ->
            directory = directory.findFile(name)?.takeIf { it.isDirectory }
                ?: requireNotNull(directory.createDirectory(name)) { "Cannot create $name" }
        }
        val name = segments.last()
        return directory.findFile(name) ?: requireNotNull(directory.createFile("text/markdown", name)) {
            "Cannot create $relativePath"
        }.also { created ->
            if (created.name != name && !(created.renameTo(name) && created.name == name)) {
                runCatching { created.delete() }
                error("Cannot preserve projection filename $name")
            }
        }
    }

    private fun findFile(root: DocumentFile, relativePath: String): DocumentFile? {
        var current: DocumentFile = root
        relativePath.split('/').filter(String::isNotBlank).forEach { segment ->
            current = current.findFile(segment) ?: return null
        }
        return current
    }

    internal fun fileName(title: String, sourceKey: String): String {
        val safeTitle = title.takeIf(ObsidianProjectionPrivacyPolicy::safeMetadata).orEmpty()
        val clean = safeTitle.replace(Regex("[\\\\/:*?\"<>|]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim(' ', '.')
            .take(80)
            .ifBlank { "GalaxySSI" }
        return "$clean-${GlobalAgentText.stableKey(sourceKey).take(8)}.md"
    }

    private fun stripFrontMatter(value: String): String {
        if (!value.startsWith("---")) return value
        val end = value.indexOf("\n---", startIndex = 3)
        return if (end < 0) value else value.substring(end + 4).trimStart()
    }

    private fun yaml(value: String): String = value.replace("\\", "\\\\").replace("\"", "\\\"").take(1_000)

    private fun isoDate(timestampMillis: Long): String = SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ssXXX",
        Locale.US
    ).format(Date(timestampMillis.takeIf { it > 0L } ?: System.currentTimeMillis()))

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }

    private const val MAX_EDIT_SCANS = 8
    private const val MAX_CANDIDATE_CHARACTERS = 256_000
}
