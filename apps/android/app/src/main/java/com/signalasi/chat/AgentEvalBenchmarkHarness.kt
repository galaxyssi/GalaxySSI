package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject

internal data class AgentBenchmarkPlannedTool(
    val id: String,
    val input: AgentNativeJsonObject
)

internal object AgentBenchmarkHarnessProtocol {
    fun toolsFor(case: AgentBenchmarkCase, trialId: String): List<AgentBenchmarkPlannedTool> = when (case.id) {
        "plan-tool-01" -> listOf(tool(AgentSystemEvidenceNativeTools.DEVICE_INFO))
        "plan-tool-02" -> listOf(tool(AgentSystemEvidenceNativeTools.APP_INFO))
        "plan-tool-03" -> listOf(tool(AgentHardwareNativeTools.NETWORK_STATUS))
        "plan-tool-04" -> listOf(tool(AgentHardwareNativeTools.BATTERY_STATUS))
        "plan-tool-05" -> listOf(tool(AgentHardwareNativeTools.STORAGE_STATUS))
        "plan-tool-06" -> listOf(tool(AgentSystemEvidenceNativeTools.LOCAL_TIME))
        "plan-tool-07" -> fileIntegrityTools(trialId)
        "plan-tool-08" -> listOf(tool(AgentHardwareNativeTools.MEMORY_STATUS))
        "plan-tool-09" -> listOf(tool(
            AgentWebIntelligenceNativeTools.RESEARCH,
            mapOf(
                "query" to "Android app process lifecycle and WorkManager official documentation",
                "evidence_limit" to 4,
                "profile" to "balanced",
                "use_cache" to true,
                "early_complete" to true
            )
        ))
        "plan-tool-10" -> listOf(tool(
            AgentSystemEvidenceNativeTools.JSON_VALIDATE,
            mapOf("json" to "{\"status\":\"ready\",\"count\":3}")
        ))
        else -> emptyList()
    }

    fun planningPrompt(case: AgentBenchmarkCase, tools: List<AgentBenchmarkPlannedTool>): String = buildString {
        append(case.taggedPrompt)
        append("\n\n这是一次真实 Agent Harness 执行。先规划，不得声称工具已经执行。")
        if (tools.isNotEmpty()) {
            append("\n运行时已根据权限和任务约束选择以下真实工具：")
            tools.forEachIndexed { index, tool ->
                append("\n").append(index + 1).append(". ").append(tool.id)
            }
        } else if (case.dimension == AgentBenchmarkDimension.ANDROID_WORLD) {
            append("\n运行时将通过 AndroidWorld 适配器读取真机系统状态。")
        }
        append("\n只输出一个 JSON 对象，格式为 {\"plan\":[{\"step\":\"...\"}]}。")
    }

    fun finalPrompt(
        case: AgentBenchmarkCase,
        planJson: String,
        receipts: List<AgentToolCallRecord>
    ): String = buildString {
        append(case.taggedPrompt)
        append("\n\n以下是刚才真实执行产生的不可变工具回执。只能依据回执回答，不得编造数值。")
        append("\n计划：").append(planJson.take(MAX_PLAN_PROMPT_CHARS))
        receipts.forEachIndexed { index, receipt ->
            append("\n\n回执 ").append(index + 1).append(" [").append(receipt.toolName).append("]")
            append(" 状态=").append(receipt.status.name.lowercase())
            append("\n").append(receiptResultForPrompt(receipt))
            receipt.errorMessage.takeIf(String::isNotBlank)?.let { append("\n错误：").append(it) }
        }
        append("\n\n直接给出最终结论，并明确引用回执中的真实观测值和工具名称。")
    }

    internal fun boundedToolResult(toolName: String, raw: String, maxChars: Int): String {
        if (raw.length <= maxChars && toolName !in AgentWebIntelligenceNativeTools.toolIds) return raw
        if (toolName in AgentWebIntelligenceNativeTools.toolIds) {
            compactWebResult(raw)?.let { compact ->
                if (compact.length <= maxChars) return compact
            }
        }
        return raw.take(maxChars)
    }

    internal fun verifiedSources(
        receipt: AgentToolCallRecord,
        maximum: Int = MAX_VERIFIED_SOURCES
    ): List<JSONObject> {
        if (receipt.status != AgentToolCallStatus.SUCCEEDED ||
            receipt.toolName !in AgentWebIntelligenceNativeTools.toolIds) return emptyList()
        val output = runCatching { JSONObject(receipt.resultJson).optJSONObject("output") }.getOrNull()
            ?: return emptyList()
        val candidates = buildList {
            addAll(sourceObjects(output.optJSONArray("documents"), "content"))
            addAll(sourceObjects(output.optJSONArray("results"), "excerpt"))
        }
        return candidates.distinctBy { it.optString("url").ifBlank { it.optString("citation_id") } }
            .filter { it.optString("url").isNotBlank() || it.optString("citation_id").isNotBlank() }
            .take(maximum)
            .map { source ->
                JSONObject()
                    .put("tool_id", receipt.toolName)
                    .put("receipt_id", receipt.id)
                    .put("citation_id", source.optString("citation_id"))
                    .put("title", source.optString("title"))
                    .put("url", source.optString("url"))
                    .put("published_at", source.optString("published_at"))
                    .put("retrieved_at_millis", source.optLong("retrieved_at_millis"))
            }
    }

    fun planJson(raw: String): String {
        val clean = raw.trim().take(MAX_RAW_PLAN_CHARS)
        if (clean.isBlank()) return "[]"
        val objectCandidate = clean.substringAfter('{', "").substringBeforeLast('}', "")
            .takeIf(String::isNotBlank)?.let { "{$it}" }
        val fromObject = objectCandidate?.let { candidate ->
            runCatching { JSONObject(candidate).optJSONArray("plan") }.getOrNull()
        }
        val directArray = runCatching {
            val start = clean.indexOf('[')
            val end = clean.lastIndexOf(']')
            if (start >= 0 && end > start) JSONArray(clean.substring(start, end + 1)) else null
        }.getOrNull()
        val source = fromObject ?: directArray
        val normalized = JSONArray()
        if (source != null) {
            for (index in 0 until minOf(source.length(), MAX_PLAN_STEPS)) {
                val item = source.optJSONObject(index)
                val step = item?.optString("step").orEmpty().ifBlank { source.optString(index) }
                    .trim().take(MAX_PLAN_STEP_CHARS)
                if (step.isNotBlank()) normalized.put(JSONObject().put("step", step))
            }
        }
        if (normalized.length() == 0) {
            normalized.put(JSONObject().put("step", clean.take(MAX_PLAN_STEP_CHARS)))
        }
        return normalized.toString()
    }

    fun androidWorldReceipt(result: AgentAndroidWorldResult): AgentToolCallRecord {
        val output = JSONObject()
            .put("task_id", result.taskId)
            .put("passed", result.passed)
            .put("captured_at_millis", result.capturedAtMillis)
            .put("verifiers", JSONArray().apply {
                result.verifierResults.forEach { verifier ->
                    put(JSONObject()
                        .put("id", verifier.verifierId)
                        .put("passed", verifier.passed)
                        .put("actual", verifier.actual)
                        .put("reason", verifier.reason))
                }
            })
            .toString()
        return AgentToolCallRecord(
            id = "androidworld:${result.id}",
            toolName = "signalasi.androidworld.observe.${result.taskId}",
            status = if (result.passed) AgentToolCallStatus.SUCCEEDED else AgentToolCallStatus.FAILED,
            argumentsJson = JSONObject().put("task_id", result.taskId).toString(),
            resultJson = output,
            errorMessage = result.verifierResults.filterNot(AgentAndroidWorldVerifierResult::passed)
                .joinToString("; ") { it.reason },
            startedAtMillis = result.capturedAtMillis,
            completedAtMillis = result.capturedAtMillis
        )
    }

    private fun fileIntegrityTools(trialId: String): List<AgentBenchmarkPlannedTool> {
        val workspace = "evalops"
        val directory = "file-integrity"
        val path = "$directory/${trialId.filter(Char::isLetterOrDigit).take(48)}.txt"
        val text = "SignalASI real Agent benchmark\ntrial=$trialId\n"
        return listOf(
            tool(AgentPhoneNativeToolCatalog.WORKSPACE_INITIALIZE, mapOf("workspace_id" to workspace)),
            tool(AgentPhoneNativeToolCatalog.WORKSPACE_MKDIR, mapOf(
                "workspace_id" to workspace,
                "path" to directory,
                "recursive" to true
            )),
            tool(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT, mapOf(
                "workspace_id" to workspace,
                "path" to path,
                "text" to text
            )),
            tool(AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT, mapOf(
                "workspace_id" to workspace,
                "path" to path
            )),
            tool(AgentPhoneNativeToolCatalog.WORKSPACE_SHA256, mapOf(
                "workspace_id" to workspace,
                "path" to path
            ))
        )
    }

    private fun tool(id: String, input: AgentNativeJsonObject = emptyMap()) =
        AgentBenchmarkPlannedTool(id, input)

    private fun receiptResultForPrompt(receipt: AgentToolCallRecord): String =
        boundedToolResult(receipt.toolName, receipt.resultJson, MAX_RECEIPT_PROMPT_CHARS)

    private fun compactWebResult(raw: String): String? = runCatching {
        val root = JSONObject(raw)
        val output = root.optJSONObject("output") ?: return@runCatching null
        val compactOutput = JSONObject()
        copyScalars(output, compactOutput, "operation", "status", "query")
        compactOutput.put("documents", compactSourceArray(output.optJSONArray("documents"), "content"))
        compactOutput.put("results", compactSourceArray(output.optJSONArray("results"), "excerpt"))
        compactOutput.put("receipts", compactReceiptArray(output.optJSONArray("receipts")))
        output.optJSONObject("research")?.let { research ->
            compactOutput.put("research", JSONObject()
                .put("citation_count", research.optInt("citation_count"))
                .put("evidence_brief", research.optString("evidence_brief").take(MAX_EVIDENCE_BRIEF_CHARS))
                .put("synthesis_contract", research.optJSONObject("synthesis_contract")))
        }
        JSONObject()
            .put("status", root.optString("status"))
            .put("output", compactOutput)
            .put("message", root.optString("message"))
            .put("receipt", root.optJSONObject("receipt"))
            .toString()
    }.getOrNull()

    private fun compactSourceArray(source: JSONArray?, textKey: String): JSONArray = JSONArray().apply {
        sourceObjects(source, textKey).take(MAX_PROMPT_SOURCES).forEach(::put)
    }

    private fun sourceObjects(source: JSONArray?, textKey: String): List<JSONObject> = buildList {
        if (source == null) return@buildList
        repeat(minOf(source.length(), MAX_SOURCE_SCAN)) { index ->
            val item = source.optJSONObject(index) ?: return@repeat
            add(JSONObject().also { compact ->
                copyScalars(
                    item,
                    compact,
                    "citation_id",
                    "url",
                    "title",
                    "published_at",
                    "retrieved_at_millis",
                    "content_sha256"
                )
                item.optString(textKey).takeIf(String::isNotBlank)?.let {
                    compact.put(textKey, it.take(MAX_SOURCE_EXCERPT_CHARS))
                }
            })
        }
    }

    private fun compactReceiptArray(source: JSONArray?): JSONArray = JSONArray().apply {
        if (source == null) return@apply
        repeat(minOf(source.length(), MAX_SOURCE_RECEIPTS)) { index ->
            val item = source.optJSONObject(index) ?: return@repeat
            put(JSONObject().also { compact ->
                copyScalars(
                    item,
                    compact,
                    "source_id",
                    "status",
                    "duration_millis",
                    "result_count",
                    "error_code"
                )
            })
        }
    }

    private fun copyScalars(source: JSONObject, target: JSONObject, vararg keys: String) {
        keys.forEach { key -> if (source.has(key) && !source.isNull(key)) target.put(key, source.opt(key)) }
    }

    private const val MAX_PLAN_STEPS = 12
    private const val MAX_PLAN_STEP_CHARS = 800
    private const val MAX_RAW_PLAN_CHARS = 12_000
    private const val MAX_PLAN_PROMPT_CHARS = 8_000
    private const val MAX_RECEIPT_PROMPT_CHARS = 12_000
    private const val MAX_EVIDENCE_BRIEF_CHARS = 3_000
    private const val MAX_SOURCE_EXCERPT_CHARS = 700
    private const val MAX_PROMPT_SOURCES = 4
    private const val MAX_SOURCE_SCAN = 12
    private const val MAX_SOURCE_RECEIPTS = 12
    private const val MAX_VERIFIED_SOURCES = 8
}
