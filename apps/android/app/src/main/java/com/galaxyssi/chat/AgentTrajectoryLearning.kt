package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

data class AgentFailureMemory(
    val id: String = UUID.randomUUID().toString(),
    val taskFamily: String,
    val resourceId: String,
    val failureReasons: List<String>,
    val inapplicableConditions: Set<String>,
    val evidenceRunIds: List<String>,
    val evidenceCount: Int,
    val firstObservedAtMillis: Long,
    val lastObservedAtMillis: Long,
    val revalidateAfterMillis: Long,
    val resolvedAtMillis: Long = 0L
) {
    val active: Boolean get() = resolvedAtMillis <= 0L
}

class AgentFailureMemoryStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun observe(run: AgentRecordedRun, sample: AgentEvalSample): AgentFailureMemory? {
        if (sample.passed || sample.failureReasons.isEmpty()) return null
        val family = AgentLearningAnalyzer.taskFamily(run.originalRequest)
        if (family.isBlank() || AgentLearningAnalyzer.containsSensitiveData(run.originalRequest)) return null
        val key = AgentLearningAnalyzer.stableKey("$family|${sample.resourceId}")
        val current = getByKey(key)
        val now = sample.completedAtMillis.takeIf { it > 0L } ?: System.currentTimeMillis()
        val updated = AgentFailureMemory(
            id = current?.id ?: UUID.randomUUID().toString(),
            taskFamily = family,
            resourceId = sample.resourceId,
            failureReasons = (current?.failureReasons.orEmpty() + sample.failureReasons)
                .distinct().takeLast(MAX_REASONS),
            inapplicableConditions = (current?.inapplicableConditions.orEmpty() +
                sample.failureReasons.map(::conditionFromReason) + sample.condition.wireValue)
                .filter(String::isNotBlank).toSet().take(MAX_CONDITIONS).toSet(),
            evidenceRunIds = (current?.evidenceRunIds.orEmpty() + run.runId).distinct().takeLast(MAX_EVIDENCE),
            evidenceCount = (current?.evidenceCount ?: 0) + 1,
            firstObservedAtMillis = current?.firstObservedAtMillis ?: now,
            lastObservedAtMillis = now,
            revalidateAfterMillis = now + revalidationDelay(sample),
            resolvedAtMillis = 0L
        )
        database.writeString(key(KEY_PREFIX, key), encode(updated).toString())
        prune()
        return updated
    }

    @Synchronized
    fun resolve(taskFamily: String, resourceId: String, atMillis: Long = System.currentTimeMillis()): Boolean {
        val stable = AgentLearningAnalyzer.stableKey("$taskFamily|$resourceId")
        val current = getByKey(stable) ?: return false
        database.writeString(key(KEY_PREFIX, stable), encode(current.copy(resolvedAtMillis = atMillis)).toString())
        return true
    }

    @Synchronized
    fun list(activeOnly: Boolean = false, limit: Int = MAX_ITEMS): List<AgentFailureMemory> =
        database.entries(KEY_PREFIX).mapNotNull { decode(it.second) }
            .filter { !activeOnly || it.active }
            .sortedByDescending(AgentFailureMemory::lastObservedAtMillis)
            .take(limit.coerceIn(1, MAX_ITEMS))

    @Synchronized
    fun dueForRevalidation(nowMillis: Long = System.currentTimeMillis()): List<AgentFailureMemory> =
        list(activeOnly = true).filter { it.revalidateAfterMillis <= nowMillis }

    private fun getByKey(stable: String): AgentFailureMemory? =
        decode(database.readString(key(KEY_PREFIX, stable), ""))

    private fun prune() {
        val retained = list(limit = MAX_ITEMS).mapTo(hashSetOf()) { item ->
            key(KEY_PREFIX, AgentLearningAnalyzer.stableKey("${item.taskFamily}|${item.resourceId}"))
        }
        database.removeAll(database.keys(KEY_PREFIX).filterNot(retained::contains))
    }

    private fun encode(value: AgentFailureMemory) = JSONObject()
        .put("id", value.id)
        .put("task_family", value.taskFamily)
        .put("resource_id", value.resourceId)
        .put("failure_reasons", JSONArray(value.failureReasons))
        .put("inapplicable_conditions", JSONArray(value.inapplicableConditions.toList()))
        .put("evidence_run_ids", JSONArray(value.evidenceRunIds))
        .put("evidence_count", value.evidenceCount)
        .put("first_observed_at_millis", value.firstObservedAtMillis)
        .put("last_observed_at_millis", value.lastObservedAtMillis)
        .put("revalidate_after_millis", value.revalidateAfterMillis)
        .put("resolved_at_millis", value.resolvedAtMillis)

    private fun decode(raw: String): AgentFailureMemory? = runCatching {
        val json = JSONObject(raw)
        AgentFailureMemory(
            id = json.getString("id"),
            taskFamily = json.getString("task_family"),
            resourceId = json.getString("resource_id"),
            failureReasons = json.getJSONArray("failure_reasons").strings(),
            inapplicableConditions = json.getJSONArray("inapplicable_conditions").strings().toSet(),
            evidenceRunIds = json.getJSONArray("evidence_run_ids").strings(),
            evidenceCount = json.optInt("evidence_count").coerceAtLeast(1),
            firstObservedAtMillis = json.optLong("first_observed_at_millis"),
            lastObservedAtMillis = json.optLong("last_observed_at_millis"),
            revalidateAfterMillis = json.optLong("revalidate_after_millis"),
            resolvedAtMillis = json.optLong("resolved_at_millis")
        )
    }.getOrNull()

    private fun JSONArray.strings(): List<String> = buildList {
        for (index in 0 until length()) optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
    }

    private fun conditionFromReason(reason: String): String = reason.substringBefore(':').trim()

    private fun revalidationDelay(sample: AgentEvalSample): Long = when (sample.condition) {
        AgentEvalCondition.NETWORK_LOSS, AgentEvalCondition.PROCESS_DEATH -> 24L * 60L * 60_000L
        AgentEvalCondition.DOZE, AgentEvalCondition.REBOOT -> 3L * 24L * 60L * 60_000L
        AgentEvalCondition.NORMAL -> 7L * 24L * 60L * 60_000L
    }

    private fun key(prefix: String, suffix: String) = "$prefix$suffix"

    private companion object {
        const val DATABASE = "galaxyssi_agent_failure_memory_v1"
        const val KEY_PREFIX = "failure:"
        const val MAX_ITEMS = 1_000
        const val MAX_REASONS = 24
        const val MAX_CONDITIONS = 16
        const val MAX_EVIDENCE = 40
    }
}

data class AgentSkillMarkdownInspection(
    val manifest: AgentSkillManifest,
    val signed: Boolean,
    val signatureValid: Boolean,
    val signerFingerprint: String = "",
    val warnings: List<String> = emptyList()
)

object AgentSkillMarkdownCodec {
    private const val JSON_BLOCK_START = "```galaxyssi-skill-json"
    private const val JSON_BLOCK_END = "```"

    fun encode(manifest: AgentSkillManifest): String = buildString {
        appendLine("---")
        appendLine("name: ${yamlScalar(manifest.id)}")
        appendLine("description: ${yamlScalar(manifest.description.ifBlank { manifest.title })}")
        appendLine("version: ${yamlScalar(manifest.version)}")
        appendLine("author: ${yamlScalar(manifest.author)}")
        appendLine("---")
        appendLine()
        appendLine("# ${manifest.title}")
        appendLine()
        appendLine(manifest.instructions.trim())
        appendLine()
        appendLine("## GalaxySSI Workflow")
        appendLine()
        appendLine(JSON_BLOCK_START)
        appendLine(AgentSkillManifestCodec.encode(manifest))
        appendLine(JSON_BLOCK_END)
    }.take(MAX_MARKDOWN_CHARS)

    fun decode(markdown: String): AgentSkillManifest? {
        val clean = markdown.trim().take(MAX_MARKDOWN_CHARS)
        if (clean.isBlank()) return null
        embeddedManifest(clean)?.let { return it.copy(source = "repository", autoInvoke = false) }
        val frontmatter = frontmatter(clean)
        val id = frontmatter["name"].orEmpty().normalizeSkillId()
        val description = frontmatter["description"].orEmpty().trim().take(1_000)
        if (id.isBlank() || description.isBlank()) return null
        val version = frontmatter["version"].orEmpty().takeIf(VERSION::matches) ?: "1.0.0"
        val body = clean.substringAfter("---", "").substringAfter("---", "").trim()
            .replace(Regex("(?m)^#\\s+.+$"), "").trim().take(32_000)
        if (body.isBlank()) return null
        return AgentSkillManifest(
            id = id,
            version = version,
            title = id.replace('-', ' ').replace('_', ' ').trim().replaceFirstChar(Char::uppercase),
            instructions = body,
            nativeTools = setOf(AGENT_ORCHESTRATION_TOOL_ID),
            parameters = AgentSkillParameterSchema.objectSchema(
                properties = mapOf(
                    "request" to AgentSkillParameterSchema.string(minLength = 1, maxLength = 8_000)
                ),
                required = setOf("request")
            ),
            steps = listOf(
                AgentSkillStep(
                    id = "step_1",
                    toolId = AGENT_ORCHESTRATION_TOOL_ID,
                    input = mapOf("request" to "{{parameters.request}}")
                )
            ),
            description = description,
            author = frontmatter["author"].orEmpty().ifBlank { "External Skill" }.take(200),
            source = "repository",
            autoInvoke = false,
            triggerExamples = listOf(description)
        )
    }

    private fun embeddedManifest(markdown: String): AgentSkillManifest? {
        val payload = markdown.substringAfter(JSON_BLOCK_START, "")
            .substringBefore(JSON_BLOCK_END, "").trim()
        return payload.takeIf(String::isNotBlank)?.let(AgentSkillManifestCodec::decode)
    }

    private fun frontmatter(markdown: String): Map<String, String> {
        if (!markdown.startsWith("---")) return emptyMap()
        val raw = markdown.removePrefix("---").substringBefore("---", "")
        return raw.lineSequence().mapNotNull { line ->
            val key = line.substringBefore(':', "").trim().lowercase(Locale.ROOT)
            val value = line.substringAfter(':', "").trim().trim('"', '\'')
            if (key.isBlank() || value.isBlank()) null else key to value
        }.toMap()
    }

    private fun String.normalizeSkillId(): String = lowercase(Locale.ROOT)
        .replace(Regex("[^a-z0-9._-]+"), "-")
        .trim('-', '.', '_')
        .take(96)

    private fun yamlScalar(value: String): String = "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")
        .replace("\r", " ").replace("\n", " ").take(1_000)}\""

    private val VERSION = Regex("[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][A-Za-z0-9._-]+)?")
    private const val MAX_MARKDOWN_CHARS = 128_000
}

object AgentSkillMarkdownSigner {
    fun sign(markdown: String): String {
        val payload = markdown.trim().toByteArray(Charsets.UTF_8)
        require(payload.isNotEmpty()) { "SKILL.md content is empty" }
        return JSONObject()
            .put("format", "galaxyssi-signed-skill-md-v1")
            .put("skill_md", payload.toString(Charsets.UTF_8))
            .put("signer_fingerprint", GalaxySSICrypto.localIdentitySha256())
            .put("signer_public_key", GalaxySSICrypto.localIdentityPublicKey())
            .put("signature", GalaxySSICrypto.signLocalIdentity(payload))
            .toString()
    }

    fun inspect(raw: String): AgentSkillMarkdownInspection? {
        val envelope = runCatching { JSONObject(raw) }.getOrNull()
        val signed = envelope?.optString("format") == "galaxyssi-signed-skill-md-v1"
        val markdown = if (signed) envelope?.optString("skill_md").orEmpty() else raw
        val manifest = AgentSkillMarkdownCodec.decode(markdown) ?: return null
        if (!signed) {
            return AgentSkillMarkdownInspection(
                manifest = manifest,
                signed = false,
                signatureValid = false,
                warnings = listOf("Unsigned SKILL.md requires review and installs disabled")
            )
        }
        val publicKey = envelope?.optString("signer_public_key").orEmpty()
        val fingerprint = envelope?.optString("signer_fingerprint").orEmpty()
        val signature = envelope?.optString("signature").orEmpty()
        val valid = GalaxySSICrypto.verifyPublicIdentitySignature(
            identityPublicKey = publicKey,
            expectedFingerprint = fingerprint,
            payload = markdown.trim().toByteArray(Charsets.UTF_8),
            signature = signature
        )
        return AgentSkillMarkdownInspection(
            manifest = manifest,
            signed = true,
            signatureValid = valid,
            signerFingerprint = fingerprint,
            warnings = if (valid) emptyList() else listOf("SKILL.md signature verification failed")
        )
    }
}

class AgentSkillMarkdownInstaller(private val runtime: AgentSkillRuntime) {
    fun inspect(raw: String): AgentSkillMarkdownInspection {
        val inspected = AgentSkillMarkdownSigner.inspect(raw)
            ?: throw AgentSkillPackageException("SKILL.md is malformed")
        val validation = runtime.validate(inspected.manifest)
        if (!validation.isValid) throw AgentSkillValidationException(validation)
        return inspected
    }

    fun installForReview(raw: String): AgentSkillInstallation {
        val inspected = inspect(raw)
        require(!inspected.signed || inspected.signatureValid) { "SKILL.md signature is invalid" }
        return runtime.install(inspected.manifest.copy(autoInvoke = false), enabled = false)
    }

    fun approveSignAndInstall(markdown: String): AgentSkillInstallation {
        val signed = AgentSkillMarkdownSigner.sign(markdown)
        val inspected = inspect(signed)
        require(inspected.signed && inspected.signatureValid) { "Local SKILL.md signing failed" }
        return runtime.install(inspected.manifest.copy(autoInvoke = false), enabled = true)
    }
}

object AgentTrajectoryLearningService {
    fun observe(context: Context, run: AgentRecordedRun, sample: AgentEvalSample) {
        if (!sample.passed) AgentFailureMemoryStore(context).observe(run, sample)
        AgentKnowledgeGapDetector.observe(AgentCognitiveGovernanceStore(context), run, sample)?.let { gap ->
            AgentKnowledgeGapResearchBridge.observe(context, gap)
        }
        if (sample.passed) {
            AgentFailureMemoryStore(context).resolve(
                AgentLearningAnalyzer.taskFamily(run.originalRequest),
                sample.resourceId
            )
        }
    }
}
