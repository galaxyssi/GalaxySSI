package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

enum class AgentMcpPermissionMode(val wireValue: String) {
    READ_ONLY("read_only"),
    ASK_FOR_CHANGES("ask_for_changes"),
    TRUSTED("trusted"),
    DISABLED("disabled");

    companion object {
        fun fromWireValue(value: String?): AgentMcpPermissionMode =
            entries.firstOrNull { it.wireValue == value?.trim()?.lowercase(Locale.ROOT) }
                ?: ASK_FOR_CHANGES
    }
}

enum class AgentMcpToolRisk(val wireValue: String) {
    LOW("low"),
    MEDIUM("medium"),
    HIGH("high")
}

data class AgentMcpToolAssessment(
    val risk: AgentMcpToolRisk,
    val permissions: Set<String>,
    val reason: String,
    val parameterPreview: AgentNativeJsonObject,
    val inputSha256: String
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "risk" to risk.wireValue,
        "permissions" to permissions.sorted(),
        "reason" to reason,
        "parameter_preview" to parameterPreview,
        "input_sha256" to inputSha256
    )
}

data class AgentMcpPermissionDecision(
    val allowed: Boolean,
    val code: String,
    val message: String,
    val requiredUserAction: String = ""
)

object AgentMcpToolSecurityPolicy {
    fun provisionalRisk(toolName: String): AgentMcpToolRisk {
        val tokens = nameTokens(toolName)
        return when {
            tokens.any(HIGH_RISK_TERMS::contains) -> AgentMcpToolRisk.HIGH
            tokens.any(READ_ONLY_TERMS::contains) && tokens.none(MUTATING_TERMS::contains) -> AgentMcpToolRisk.LOW
            else -> AgentMcpToolRisk.MEDIUM
        }
    }

    fun assess(
        tool: AgentMcpTool,
        arguments: AgentNativeJsonObject,
        transport: AgentMcpTransportKind
    ): AgentMcpToolAssessment {
        val tokens = nameTokens(tool.name)
        val readOnly = tool.annotations.boolean("readOnlyHint", "read_only_hint")
        val destructive = tool.annotations.boolean("destructiveHint", "destructive_hint")
        val openWorld = tool.annotations.boolean("openWorldHint", "open_world_hint")
        val risk: AgentMcpToolRisk
        val reason: String
        when {
            destructive == true || tokens.any(HIGH_RISK_TERMS::contains) -> {
                risk = AgentMcpToolRisk.HIGH
                reason = "The tool is destructive or controls a sensitive external action."
            }
            readOnly == true && tokens.none(MUTATING_TERMS::contains) -> {
                risk = AgentMcpToolRisk.LOW
                reason = "The MCP server declares this tool read-only."
            }
            tokens.any(READ_ONLY_TERMS::contains) && tokens.none(MUTATING_TERMS::contains) -> {
                risk = AgentMcpToolRisk.LOW
                reason = "The tool name describes a read-only operation."
            }
            else -> {
                risk = AgentMcpToolRisk.MEDIUM
                reason = "The MCP tool can change data or external state."
            }
        }

        val keys = buildSet { collectKeys(arguments, this) }
        val permissions = buildSet {
            add("mcp.data.read")
            add(if (transport == AgentMcpTransportKind.LOCAL_STDIO) "mcp.process.execute" else "mcp.network.connect")
            if (risk != AgentMcpToolRisk.LOW) add("mcp.data.write")
            if (risk == AgentMcpToolRisk.HIGH) add("mcp.destructive")
            if (openWorld == true) add("mcp.network.open_world")
            if (keys.any { SECRET_KEY_PATTERN.containsMatchIn(it) }) add("mcp.secrets.use")
            if (keys.any { PATH_KEY_PATTERN.containsMatchIn(it) }) add("mcp.files.access")
        }
        return AgentMcpToolAssessment(
            risk = risk,
            permissions = permissions,
            reason = reason,
            parameterPreview = AgentMcpParameterRedactor.sanitize(arguments),
            inputSha256 = AgentNativeJsonCodec.sha256(arguments)
        )
    }

    @Suppress("UNUSED_PARAMETER")
    fun decide(
        mode: AgentMcpPermissionMode,
        assessment: AgentMcpToolAssessment,
        explicitlyApproved: Boolean
    ): AgentMcpPermissionDecision {
        return AgentMcpPermissionDecision(
            allowed = true,
            code = "allowed_unrestricted",
            message = "GalaxySSI internal approval gates are disabled."
        )
    }

    private fun McpJsonObject?.boolean(vararg names: String): Boolean? {
        val source = this ?: return null
        names.forEach { name -> (source[name] as? McpJsonBoolean)?.value?.let { return it } }
        return null
    }

    private fun collectKeys(value: Any?, target: MutableSet<String>) {
        when (value) {
            is Map<*, *> -> value.forEach { (key, child) ->
                target += key.toString().lowercase(Locale.ROOT)
                collectKeys(child, target)
            }
            is Iterable<*> -> value.forEach { collectKeys(it, target) }
            is Array<*> -> value.forEach { collectKeys(it, target) }
        }
    }

    private fun nameTokens(value: String): Set<String> = value.lowercase(Locale.ROOT)
        .replace(Regex("[^a-z0-9]+"), " ")
        .trim()
        .split(Regex("\\s+"))
        .filter(String::isNotBlank)
        .toSet()

    private val READ_ONLY_TERMS = setOf(
        "get", "list", "read", "search", "query", "find", "inspect", "status",
        "describe", "fetch", "lookup", "view", "download"
    )
    private val MUTATING_TERMS = setOf(
        "set", "create", "update", "write", "edit", "send", "post", "put", "patch",
        "upload", "execute", "run", "start", "stop", "control", "toggle", "install",
        "approve", "merge", "comment", "reply", "publish"
    )
    private val HIGH_RISK_TERMS = setOf(
        "delete", "remove", "destroy", "drop", "wipe", "reset", "payment", "purchase",
        "transfer", "credential", "permission", "shell", "terminal", "sudo", "lock",
        "unlock", "reboot", "shutdown", "deploy", "release"
    )
    private val SECRET_KEY_PATTERN = Regex(
        "(^|[_.-])(password|passwd|passphrase|secret|token|api[_-]?key|authorization|cookie|otp|totp|private[_-]?key)($|[_.-])",
        RegexOption.IGNORE_CASE
    )
    private val PATH_KEY_PATTERN = Regex(
        "(^|[_.-])(path|file|folder|directory|uri|url)($|[_.-])",
        RegexOption.IGNORE_CASE
    )
}

object AgentMcpParameterRedactor {
    fun sanitize(arguments: AgentNativeJsonObject): AgentNativeJsonObject {
        val sanitized = sanitizeValue(arguments, "", 0) as? Map<*, *> ?: return emptyMap()
        return sanitized.entries.mapNotNull { (key, value) ->
            (key as? String)?.let { it to value }
        }.toMap()
    }

    fun sanitizeText(value: String, limit: Int = 500): String {
        var text = BEARER_PATTERN.replace(value, "Bearer [REDACTED]")
        text = ASSIGNMENT_PATTERN.replace(text) { "${it.groupValues[1]}=[REDACTED]" }
        text = URL_IN_TEXT_PATTERN.replace(text) {
            it.value.substringBefore('?').substringBefore('#')
        }
        return text.take(limit.coerceIn(0, 2_000))
    }

    private fun sanitizeValue(value: Any?, key: String, depth: Int): Any? {
        if (SECRET_KEY_PATTERN.containsMatchIn(key)) return "[REDACTED]"
        if (depth >= MAX_DEPTH) return "[TRUNCATED]"
        return when (value) {
            is Map<*, *> -> value.entries.take(MAX_ITEMS).associate { (childKey, child) ->
                childKey.toString().take(128) to sanitizeValue(child, childKey.toString(), depth + 1)
            }
            is Iterable<*> -> value.take(MAX_ITEMS).map { sanitizeValue(it, key, depth + 1) }
            is Array<*> -> value.take(MAX_ITEMS).map { sanitizeValue(it, key, depth + 1) }
            is String -> sanitizeString(value)
            null, is Boolean, is Number -> value
            else -> value.toString().take(MAX_STRING)
        }
    }

    private fun sanitizeString(value: String): String {
        var text = BEARER_PATTERN.replace(value, "Bearer [REDACTED]")
        text = ASSIGNMENT_PATTERN.replace(text) { "${it.groupValues[1]}=[REDACTED]" }
        if (text.startsWith("https://", true) || text.startsWith("http://", true)) {
            text = text.substringBefore('?').substringBefore('#')
        }
        return text.take(MAX_STRING) + if (text.length > MAX_STRING) "..." else ""
    }

    private const val MAX_DEPTH = 6
    private const val MAX_ITEMS = 64
    private const val MAX_STRING = 320
    private val SECRET_KEY_PATTERN = Regex(
        "(^|[_.-])(password|passwd|passphrase|secret|token|api[_-]?key|authorization|cookie|otp|totp|private[_-]?key)($|[_.-])",
        RegexOption.IGNORE_CASE
    )
    private val BEARER_PATTERN = Regex("\\bBearer\\s+[A-Za-z0-9._~+/=-]{8,}", RegexOption.IGNORE_CASE)
    private val ASSIGNMENT_PATTERN = Regex(
        "\\b(password|passwd|secret|token|api[_-]?key|authorization)\\s*=\\s*[^\\s,;]+",
        RegexOption.IGNORE_CASE
    )
    private val URL_IN_TEXT_PATTERN = Regex("https?://[^\\s<>\"]+", RegexOption.IGNORE_CASE)
}

data class AgentMcpAuditRecord(
    val auditId: String = UUID.randomUUID().toString(),
    val timestampMillis: Long = System.currentTimeMillis(),
    val connectionId: String,
    val connectionName: String,
    val toolName: String,
    val transport: String,
    val source: String,
    val callerId: String,
    val taskId: String,
    val conversationId: String,
    val risk: String,
    val permissions: List<String>,
    val permissionMode: String,
    val permissionDecision: String,
    val parameterPreview: AgentNativeJsonObject,
    val inputSha256: String,
    val status: String,
    val durationMillis: Long,
    val outputSha256: String = "",
    val errorCode: String = "",
    val errorMessage: String = ""
)

interface AgentMcpAuditStore {
    fun append(record: AgentMcpAuditRecord)
    fun list(connectionId: String = "", limit: Int = 100): List<AgentMcpAuditRecord>
    fun clear(connectionId: String = ""): Int
}

class InMemoryAgentMcpAuditStore : AgentMcpAuditStore {
    private val records = mutableListOf<AgentMcpAuditRecord>()

    @Synchronized
    override fun append(record: AgentMcpAuditRecord) {
        records += record
        while (records.size > MAX_RECORDS) records.removeAt(0)
    }

    @Synchronized
    override fun list(connectionId: String, limit: Int): List<AgentMcpAuditRecord> = records
        .asSequence()
        .filter { connectionId.isBlank() || it.connectionId == connectionId }
        .toList()
        .takeLast(limit.coerceIn(1, 500))
        .asReversed()

    @Synchronized
    override fun clear(connectionId: String): Int {
        val before = records.size
        if (connectionId.isBlank()) records.clear() else records.removeAll { it.connectionId == connectionId }
        return before - records.size
    }

    companion object {
        const val MAX_RECORDS = 1_000
    }
}

class EncryptedAgentMcpAuditStore(context: android.content.Context) : AgentMcpAuditStore {
    private val preferences = AgentEncryptedPreferences(context.applicationContext, PREFERENCES_NAME)

    @Synchronized
    override fun append(record: AgentMcpAuditRecord) {
        val records = read().toMutableList().apply {
            add(record)
            if (size > InMemoryAgentMcpAuditStore.MAX_RECORDS) {
                subList(0, size - InMemoryAgentMcpAuditStore.MAX_RECORDS).clear()
            }
        }
        write(records)
    }

    @Synchronized
    override fun list(connectionId: String, limit: Int): List<AgentMcpAuditRecord> = read()
        .asSequence()
        .filter { connectionId.isBlank() || it.connectionId == connectionId }
        .toList()
        .takeLast(limit.coerceIn(1, 500))
        .asReversed()

    @Synchronized
    override fun clear(connectionId: String): Int {
        val records = read()
        val kept = if (connectionId.isBlank()) emptyList() else records.filterNot { it.connectionId == connectionId }
        write(kept)
        return records.size - kept.size
    }

    private fun read(): List<AgentMcpAuditRecord> = runCatching {
        val root = JSONObject(preferences.readString(KEY_RECORDS, EMPTY_DOCUMENT))
        val values = root.optJSONArray("records") ?: JSONArray()
        (0 until values.length()).mapNotNull { index -> values.optJSONObject(index)?.toRecord() }
    }.getOrDefault(emptyList())

    private fun write(records: List<AgentMcpAuditRecord>) {
        preferences.writeString(
            KEY_RECORDS,
            JSONObject().put("version", 1).put(
                "records",
                JSONArray().apply { records.forEach { put(it.toJson()) } }
            ).toString()
        )
    }

    private fun AgentMcpAuditRecord.toJson() = JSONObject()
        .put("audit_id", auditId)
        .put("timestamp_ms", timestampMillis)
        .put("connection_id", connectionId)
        .put("connection_name", connectionName)
        .put("tool_name", toolName)
        .put("transport", transport)
        .put("source", source)
        .put("caller_id", callerId)
        .put("task_id", taskId)
        .put("conversation_id", conversationId)
        .put("risk", risk)
        .put("permissions", JSONArray(permissions))
        .put("permission_mode", permissionMode)
        .put("permission_decision", permissionDecision)
        .put("parameter_preview", JSONObject(parameterPreview))
        .put("input_sha256", inputSha256)
        .put("status", status)
        .put("duration_ms", durationMillis)
        .put("output_sha256", outputSha256)
        .put("error_code", errorCode)
        .put("error_message", AgentMcpParameterRedactor.sanitizeText(errorMessage))

    private fun JSONObject.toRecord(): AgentMcpAuditRecord? {
        val connectionId = optString("connection_id").trim()
        val toolName = optString("tool_name").trim()
        if (connectionId.isBlank() || toolName.isBlank()) return null
        return AgentMcpAuditRecord(
            auditId = optString("audit_id").ifBlank { UUID.randomUUID().toString() },
            timestampMillis = optLong("timestamp_ms"),
            connectionId = connectionId,
            connectionName = optString("connection_name"),
            toolName = toolName,
            transport = optString("transport"),
            source = optString("source"),
            callerId = optString("caller_id"),
            taskId = optString("task_id"),
            conversationId = optString("conversation_id"),
            risk = optString("risk"),
            permissions = optJSONArray("permissions").toStringList(),
            permissionMode = optString("permission_mode"),
            permissionDecision = optString("permission_decision"),
            parameterPreview = optJSONObject("parameter_preview").toNativeMap(),
            inputSha256 = optString("input_sha256"),
            status = optString("status"),
            durationMillis = optLong("duration_ms"),
            outputSha256 = optString("output_sha256"),
            errorCode = optString("error_code"),
            errorMessage = optString("error_message")
        )
    }

    private fun JSONArray?.toStringList(): List<String> = if (this == null) emptyList() else
        (0 until length()).mapNotNull { optString(it).takeIf(String::isNotBlank) }

    private fun JSONObject?.toNativeMap(): AgentNativeJsonObject = if (this == null) emptyMap() else
        keys().asSequence().associateWith { key -> toNativeValue(opt(key)) }

    private fun toNativeValue(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.toNativeMap()
        is JSONArray -> (0 until value.length()).map { toNativeValue(value.opt(it)) }
        is String, is Number, is Boolean -> value
        else -> value.toString()
    }

    companion object {
        private const val PREFERENCES_NAME = "galaxyssi_mcp_tool_audit"
        private const val KEY_RECORDS = "records"
        private const val EMPTY_DOCUMENT = "{\"version\":1,\"records\":[]}"
    }
}
