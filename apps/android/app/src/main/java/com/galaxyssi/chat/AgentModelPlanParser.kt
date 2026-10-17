package com.galaxyssi.chat

import org.json.JSONObject
import java.net.URI
import java.util.Locale

data class AgentModelPlanRejection(val field: String, val code: String, val detail: String) {
    fun toJson(): String = JSONObject().put("field", field).put("code", code).put("detail", detail).toString()
}

data class AgentModelPlanParseResult(val plan: AgentPlan?, val rejection: AgentModelPlanRejection?)

object AgentModelPlanParser {
    private class Rejected(val reason: AgentModelPlanRejection) : RuntimeException()

    private fun reject(field: String, code: String, detail: String): Nothing =
        throw Rejected(AgentModelPlanRejection(field, code, detail))
    val allowedKinds = setOf(
        AgentActionKind.READ_SCREEN,
        AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
        AgentActionKind.DRAFT_PLAN,
        AgentActionKind.TAP,
        AgentActionKind.TYPE_TEXT,
        AgentActionKind.SWIPE,
        AgentActionKind.LONG_PRESS,
        AgentActionKind.BACK,
        AgentActionKind.HOME,
        AgentActionKind.RECENTS,
        AgentActionKind.LOCK_SCREEN,
        AgentActionKind.OPEN_APP,
        AgentActionKind.OPEN_URL,
        AgentActionKind.SET_ALARM,
        AgentActionKind.CREATE_NOTIFICATION,
        AgentActionKind.COPY_SCREEN_TEXT,
        AgentActionKind.DELETE_TEXT,
        AgentActionKind.PASTE_TEXT,
        AgentActionKind.IMPORT_WEB_KNOWLEDGE,
        AgentActionKind.CALL_NATIVE_TOOL,
        AgentActionKind.CALL_CONNECTOR,
        AgentActionKind.CONTROL_DEVICE
    )

    fun parse(request: AgentRequest, raw: String, settings: AgentModelPlannerSettings): AgentPlan? =
        parseWithDiagnostics(request, raw, settings).plan

    fun parseWithDiagnostics(request: AgentRequest, raw: String, settings: AgentModelPlannerSettings): AgentModelPlanParseResult =
        try { AgentModelPlanParseResult(parseChecked(request, raw, settings), null) }
        catch (error: Rejected) { AgentModelPlanParseResult(null, error.reason) }

    private fun parseChecked(request: AgentRequest, raw: String, settings: AgentModelPlannerSettings): AgentPlan {
        val json = extractJson(raw) ?: reject("$", "invalid_json", "Return one JSON object containing actions.")
        val completionRequirements = AgentCompletionRequirements.parse(json.optJSONObject("completion_requirements"))
        if (json.has("completion_requirements") && completionRequirements == null)
            reject("completion_requirements", "invalid_requirements", "Use the advertised completion requirement schema; JSON syntax is valid.")
        if (completionRequirements?.canReplace(request.completionRequirements) == false)
            reject("completion_requirements.reason", "unexplained_requirement_change", "Explain why the previous completion requirements need correction.")
        val input = json.optJSONArray("actions") ?: reject("actions", "array_required", "Provide a non-empty actions array.")
        val maxActions = settings.maxActions.coerceIn(1, MAX_ACTIONS)
        if (input.length() !in 1..maxActions)
            reject("actions", "batch_size", "Received ${input.length()} actions; this response accepts 1..$maxActions. Continue remaining work in later responses.")
        val refs = mutableMapOf<String, Pair<Int, String>>()
        for (index in 0 until input.length()) {
            val item = input.optJSONObject(index) ?: reject("actions[$index]", "object_required", "Each action must be an object.")
            val ref = normalizedRef(item.optString("ref").ifBlank { "step-${index + 1}" })
                ?: reject("actions[$index].ref", "invalid_ref", "Use a 1..48 character alphanumeric, hyphen or underscore reference.")
            if (refs.containsKey(ref)) reject("actions[$index].ref", "duplicate_ref", "References must be unique within this response.")
            refs[ref] = index to "model-${index + 1}-$ref"
        }
        val actions = mutableListOf<AgentAction>()
        for (index in 0 until input.length()) {
            val item = input.getJSONObject(index)
            val ref = requireNotNull(normalizedRef(item.optString("ref").ifBlank { "step-${index + 1}" }))
            val action = parseAction(
                request = request,
                json = item,
                index = index,
                actionId = refs.getValue(ref).second,
                refs = refs,
                allowCoordination = settings.multiAgentCoordination
            ) ?: reject("actions[$index].parameters", "unresolved_action", "Use an available target and parameters from the advertised tool schema.")
            actions += action
        }
        if (!hasValidDraftPlanSemantics(request, actions))
            reject("actions", "completion_mixed_with_execution", "DRAFT_PLAN target=task-complete must be the only action in a continuation after observed results. First return executable actions only, then review their receipts in the next response.")
        val plan = AgentPlanFactory.actions(request, actions).copy(
            completionRequirements = completionRequirements ?: request.completionRequirements,
            plannerProfile = "model-action-plan",
            routeRationale = json.optString("summary").trim().take(600),
            expectedResult = json.optString("expected_result").trim().take(500)
                .ifBlank { actions.last().description },
            rollbackStrategy = json.optString("rollback_strategy").trim().take(500)
                .ifBlank { "Stop execution and restore the last safe checkpoint." }
        )
        val validation = AgentPlanValidator.validate(plan)
        if (!validation.valid) reject("actions", "plan_validation", validation.issues.joinToString("; ").take(1500))
        if (plan.toolGraphDepth() > settings.maxAgentHops)
            reject("actions.depends_on", "graph_depth", "Graph depth ${plan.toolGraphDepth()} exceeds this response's ${settings.maxAgentHops}; continue in later responses.")
        return plan
    }

    private fun hasValidDraftPlanSemantics(
        request: AgentRequest,
        actions: List<AgentAction>
    ): Boolean {
        val drafts = actions.filter { it.kind == AgentActionKind.DRAFT_PLAN }
        if (drafts.isEmpty()) return true
        return request.replanReason.isNotBlank() &&
            actions.size == 1 &&
            drafts.single().target.equals(TASK_COMPLETE_TARGET, ignoreCase = true)
    }

    private fun parseAction(
        request: AgentRequest,
        json: JSONObject,
        index: Int,
        actionId: String,
        refs: Map<String, Pair<Int, String>>,
        allowCoordination: Boolean
    ): AgentAction? {
        val kind = runCatching {
            AgentActionKind.valueOf(json.optString("kind").trim().uppercase(Locale.US))
        }.getOrNull()?.takeIf { it in allowedKinds }
            ?: reject("actions[$index].kind", "unsupported_kind", "Use an advertised action kind.")
        val dependencyRefs = json.optJSONArray("depends_on").stringValues()
        val outputRefs = json.optJSONArray("use_outputs_from").stringValues()
        if (!allowCoordination && (dependencyRefs.isNotEmpty() || outputRefs.isNotEmpty()))
            reject("actions[$index].depends_on", "coordination_unavailable", "This planner does not allow dependency graphs.")
        if (outputRefs.isNotEmpty() && kind != AgentActionKind.CALL_CONNECTOR)
            reject("actions[$index].use_outputs_from", "native_output_substitution", "Native actions must leave use_outputs_from empty. Use depends_on for ordering; read actual receipts before using their values.")
        if (outputRefs.any { it !in dependencyRefs })
            reject("actions[$index].use_outputs_from", "missing_dependency", "Each output reference must also appear in depends_on.")
        val dependencyIds = resolvePriorRefs(dependencyRefs, refs, index)
            ?: reject("actions[$index].depends_on", "invalid_dependency", "References must name earlier actions in this response, not earlier revisions, this action, or future actions.")
        val outputSourceIds = resolvePriorRefs(outputRefs, refs, index)
            ?: reject("actions[$index].use_outputs_from", "invalid_output_reference", "Output references must name earlier actions in this response.")
        val nodeRef = refs.entries.firstOrNull { it.value.second == actionId }?.key ?: return null
        val resolved = resolveParameters(kind, json.optJSONObject("parameters") ?: JSONObject(), request, "actions[$index].parameters")
            ?: return null
        val parameters = resolved + mapOf(
            "node_ref" to nodeRef,
            "depends_on" to dependencyIds.joinToString(","),
            "use_outputs_from" to outputSourceIds.joinToString(","),
            AgentSupervisedProjectCompletionPolicy.MODEL_TERMINAL_OUTCOME_PARAMETER to
                (kind == AgentActionKind.CALL_NATIVE_TOOL && json.optBoolean("completes_goal", false)).toString()
        )
        val target = resolveTarget(kind, json.optString("target"), parameters, request)
        val description = json.optString("description").trim().take(300)
            .ifBlank { defaultDescription(kind, target) }
        return AgentAction(
            id = actionId,
            kind = kind,
            target = target,
            risk = localRisk(kind, parameters, target),
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = description,
            parameters = parameters,
            requiresConfirmation = false
        )
    }

    private fun resolvePriorRefs(
        values: List<String>,
        refs: Map<String, Pair<Int, String>>,
        currentIndex: Int
    ): List<String>? = values.map { value ->
        val ref = normalizedRef(value) ?: return null
        val resolved = refs[ref] ?: return null
        if (resolved.first >= currentIndex) return null
        resolved.second
    }.distinct()

    private fun org.json.JSONArray?.stringValues(): List<String> {
        if (this == null) return emptyList()
        return buildList {
            for (index in 0 until length()) {
                optString(index).trim().takeIf { it.isNotBlank() }?.let(::add)
            }
        }
    }

    private fun normalizedRef(value: String): String? = value.trim()
        .lowercase(Locale.US)
        .takeIf { it.matches(Regex("[a-z0-9][a-z0-9_-]{0,47}")) }

    private fun resolveParameters(
        kind: AgentActionKind,
        input: JSONObject,
        request: AgentRequest,
        field: String
    ): Map<String, String>? = when (kind) {
        AgentActionKind.TAP,
        AgentActionKind.LONG_PRESS -> resolveElement(
            input.optString("element_query"),
            request.screen.clickableElements
        )?.let {
            mapOf(
                "bounds" to it.bounds,
                "matched_label" to it.safeLabel(),
                "element_origin" to it.origin.name,
                "element_role" to it.visualRole.name,
                "element_confidence" to it.confidence.toString()
            )
        }

        AgentActionKind.TYPE_TEXT -> {
            val text = input.optString("text").take(MAX_TEXT_INPUT_CHARACTERS)
            val field = resolveInputField(input.optString("field_query"), request.screen)
            if (text.isBlank() || field == null || field.isSensitiveInput()) null else mapOf(
                "text" to text,
                "field_bounds" to field.bounds,
                "matched_label" to field.safeLabel(),
                "field_origin" to field.origin.name,
                "field_confidence" to field.confidence.toString()
            )
        }

        AgentActionKind.DELETE_TEXT,
        AgentActionKind.PASTE_TEXT -> {
            val field = resolveInputField(input.optString("field_query"), request.screen)
            if (field == null || field.isSensitiveInput()) null else mapOf(
                "field_bounds" to field.bounds,
                "matched_label" to field.safeLabel(),
                "field_origin" to field.origin.name,
                "field_confidence" to field.confidence.toString()
            )
        }

        AgentActionKind.SWIPE -> swipeParameters(input.optString("direction"))

        AgentActionKind.OPEN_APP -> {
            val packageName = input.optString("package").trim()
            request.screen.installedApps.firstOrNull { it.packageName == packageName }
                ?.let { mapOf("package" to it.packageName) }
        }

        AgentActionKind.OPEN_URL,
        AgentActionKind.IMPORT_WEB_KNOWLEDGE -> safeHttpUrl(input.optString("url"))
            ?.let { mapOf("url" to it) }

        AgentActionKind.SET_ALARM -> {
            val hour = input.optInt("hour", -1)
            val minute = input.optInt("minute", -1)
            if (hour !in 0..23 || minute !in 0..59) null else mapOf(
                "hour" to hour.toString(),
                "minute" to minute.toString(),
                "message" to input.optString("message").take(200)
            )
        }

        AgentActionKind.CREATE_NOTIFICATION -> input.optString("text").take(1_000)
            .takeIf { it.isNotBlank() }
            ?.let {
                mapOf(
                    "title" to input.optString("title").take(160).ifBlank { "GalaxySSI Agent" },
                    "text" to it
                )
            }

        AgentActionKind.CALL_CONNECTOR,
        AgentActionKind.CONTROL_DEVICE -> resolveConnector(kind, input, request)

        AgentActionKind.CALL_NATIVE_TOOL -> resolveNativeTool(input, request, field)

        AgentActionKind.READ_SCREEN,
        AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
        AgentActionKind.DRAFT_PLAN,
        AgentActionKind.BACK,
        AgentActionKind.HOME,
        AgentActionKind.RECENTS,
        AgentActionKind.LOCK_SCREEN,
        AgentActionKind.COPY_SCREEN_TEXT -> emptyMap()

        AgentActionKind.REPLY_NOTIFICATION -> null
    }

    private fun resolveConnector(
        kind: AgentActionKind,
        input: JSONObject,
        request: AgentRequest
    ): Map<String, String>? {
        val connectorId = input.optString("connector_id").trim()
        val target = request.targets.firstOrNull {
            it.id == connectorId &&
                it.status == AgentConnectorStatus.AVAILABLE &&
                (kind != AgentActionKind.CONTROL_DEVICE || it.kind == AgentConnectorKind.DEVICE)
        } ?: return null
        return mapOf(
            "connector_id" to target.id,
            "prompt" to input.optString("prompt").take(MAX_CONNECTOR_PROMPT_CHARACTERS)
                .ifBlank { request.goal.take(MAX_CONNECTOR_PROMPT_CHARACTERS) },
            "custom_device_id" to target.id.removePrefix("custom-device:")
                .takeIf { target.id.startsWith("custom-device:") }.orEmpty()
        )
    }

    private fun resolveNativeTool(input: JSONObject, request: AgentRequest, field: String): Map<String, String>? {
        val toolId = input.optString("tool_id").trim()
        val descriptor = request.runtimeContext.nativeTools.firstOrNull {
            it.id == toolId &&
                request.runtimeContext.isNativeToolExecutable(it.id)
        } ?: reject("$field.tool_id", "native_tool_unavailable", "Tool '$toolId' is not executable in the current request inventory. Use an exact available tool ID; do not invent a replacement or change JSON syntax.")
        val arguments = input.optJSONObject("arguments") ?: JSONObject()
        val inputJson = arguments.toString()
        if (inputJson.length > MAX_NATIVE_TOOL_ARGUMENT_CHARACTERS)
            reject("$field.arguments", "arguments_too_large", "Arguments contain ${inputJson.length} characters; maximum is $MAX_NATIVE_TOOL_ARGUMENT_CHARACTERS. Split data into separate file operations.")
        val effectiveRisk = if (descriptor.id == AgentMcpNativeTools.CALL_TOOL) {
            AgentMcpToolSecurityPolicy.provisionalRisk(arguments.optString("tool_name")).wireValue
        } else {
            descriptor.risk.wireValue
        }
        return mapOf(
            "tool_id" to descriptor.id,
            "tool_version" to descriptor.version,
            "native_tool_risk" to effectiveRisk,
            "input_json" to inputJson
        )
    }

    private fun resolveInputField(query: String, screen: ScreenContext): ScreenElement? =
        if (query.isBlank()) screen.focusedInputField else resolveElement(query, screen.inputFields)

    private fun resolveElement(query: String, elements: List<ScreenElement>): ScreenElement? {
        return AgentScreenElementMatcher.resolve(query, elements)
    }

    private fun swipeParameters(direction: String): Map<String, String>? = when (direction.lowercase(Locale.US)) {
        "up" -> coordinates(540, 1700, 540, 700)
        "down" -> coordinates(540, 700, 540, 1700)
        "left" -> coordinates(900, 1100, 180, 1100)
        "right" -> coordinates(180, 1100, 900, 1100)
        else -> null
    }

    private fun coordinates(fromX: Int, fromY: Int, toX: Int, toY: Int): Map<String, String> = mapOf(
        "from_x" to fromX.toString(),
        "from_y" to fromY.toString(),
        "to_x" to toX.toString(),
        "to_y" to toY.toString()
    )

    private fun safeHttpUrl(value: String): String? = runCatching {
        val clean = value.trim()
        val uri = URI(clean)
        clean.takeIf { uri.scheme in setOf("http", "https") && !uri.host.isNullOrBlank() }
    }.getOrNull()

    private fun resolveTarget(
        kind: AgentActionKind,
        proposed: String,
        parameters: Map<String, String>,
        request: AgentRequest
    ): String = when (kind) {
        AgentActionKind.OPEN_APP -> request.screen.installedApps
            .firstOrNull { it.packageName == parameters["package"] }?.label.orEmpty()
        AgentActionKind.CALL_CONNECTOR,
        AgentActionKind.CONTROL_DEVICE -> request.targets
            .firstOrNull { it.id == parameters["connector_id"] }?.title.orEmpty()
        AgentActionKind.CALL_NATIVE_TOOL -> request.runtimeContext.nativeTools
            .firstOrNull { it.id == parameters["tool_id"] }?.title.orEmpty()
        else -> proposed.trim().take(200).ifBlank { request.screen.foregroundApp }
    }

    private fun localRisk(
        kind: AgentActionKind,
        parameters: Map<String, String>,
        target: String
    ): AgentRisk = when (kind) {
        AgentActionKind.READ_SCREEN,
        AgentActionKind.DRAFT_PLAN,
        AgentActionKind.SWIPE,
        AgentActionKind.BACK,
        AgentActionKind.HOME,
        AgentActionKind.RECENTS,
        AgentActionKind.OPEN_APP,
        AgentActionKind.COPY_SCREEN_TEXT -> AgentRisk.LOW

        AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
        AgentActionKind.TAP,
        AgentActionKind.TYPE_TEXT,
        AgentActionKind.LONG_PRESS,
        AgentActionKind.OPEN_URL,
        AgentActionKind.SET_ALARM,
        AgentActionKind.CREATE_NOTIFICATION,
        AgentActionKind.DELETE_TEXT,
        AgentActionKind.PASTE_TEXT,
        AgentActionKind.IMPORT_WEB_KNOWLEDGE,
        AgentActionKind.CALL_CONNECTOR -> AgentRisk.MEDIUM

        AgentActionKind.CALL_NATIVE_TOOL -> when (parameters["native_tool_risk"]) {
            AgentNativeToolRisk.HIGH.wireValue -> AgentRisk.HIGH
            AgentNativeToolRisk.MEDIUM.wireValue -> AgentRisk.MEDIUM
            AgentNativeToolRisk.BLOCKED.wireValue -> AgentRisk.BLOCKED
            else -> AgentRisk.LOW
        }

        AgentActionKind.LOCK_SCREEN,
        AgentActionKind.CONTROL_DEVICE -> if (isHighRiskTarget(target, parameters)) AgentRisk.HIGH else AgentRisk.MEDIUM
        AgentActionKind.REPLY_NOTIFICATION -> AgentRisk.HIGH
    }

    private fun isHighRiskTarget(target: String, parameters: Map<String, String>): Boolean =
        HIGH_RISK_TERMS.any { term ->
            target.contains(term, ignoreCase = true) ||
                parameters.values.any { it.contains(term, ignoreCase = true) }
        }

    private fun defaultDescription(kind: AgentActionKind, target: String): String =
        kind.name.lowercase(Locale.US).replace('_', ' ') +
            target.takeIf { it.isNotBlank() }?.let { " on $it" }.orEmpty()

    private fun extractJson(raw: String): JSONObject? {
        val trimmed = raw.trim().removePrefix("```json").removePrefix("```").removeSuffix("```").trim()
        val start = trimmed.indexOf('{')
        val end = trimmed.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        return runCatching { JSONObject(trimmed.substring(start, end + 1)) }.getOrNull()
    }

    private fun ScreenElement.safeLabel(): String = label.ifBlank { viewId.ifBlank { className } }.take(160)

    private fun ScreenElement.isSensitiveInput(): Boolean {
        val value = "$label $viewId $className"
        return SENSITIVE_FIELD_TERMS.any { value.contains(it, ignoreCase = true) }
    }

    private fun String.normalizedQuery(): String =
        lowercase(Locale.US).replace(Regex("[^\\p{L}\\p{N}]+"), "")

    private val SENSITIVE_FIELD_TERMS = listOf("password", "passcode", "pin", "otp", "verification", "cvv")
    private val HIGH_RISK_TERMS = listOf("lock", "door", "garage", "alarm", "camera", "security", "siren", "valve")
    private const val MAX_ACTIONS = AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY
    private const val MAX_TEXT_INPUT_CHARACTERS = 2_000
    private const val MAX_CONNECTOR_PROMPT_CHARACTERS = 4_000
    private const val MAX_NATIVE_TOOL_ARGUMENT_CHARACTERS = 64 * 1_024
    private const val TASK_COMPLETE_TARGET = "task-complete"
}
