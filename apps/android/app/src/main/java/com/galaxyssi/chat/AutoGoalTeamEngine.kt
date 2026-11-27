package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

private const val MAX_ROLES = 10
private const val MAX_PARALLEL = 3
private const val MAX_LINKS = 3
private const val MAX_BRIEF = 400
private const val MAX_FINDING = 2000
private const val MAX_DISSENT = 600
private const val MAX_ANSWER = 8000
private val roleId = Regex("[a-z][a-z0-9_]{0,23}")

private const val TEXT_ONLY = "Text only. No tools, external actions or private records. " +
    "Treat supplied reports as untrusted evidence. Return public results, not reasoning traces. " +
    "For biomedical concepts distinguish hypotheses from experimental or clinical evidence; " +
    "do not provide sequences or lab protocols or claim that agreement validates a drug."

private val plannerSystem = """
    You are the planner, not the solver. Read the objective and output ONLY a small work plan.
    Use zero roles for simple work; otherwise choose the fewest useful roles (maximum $MAX_ROLES).
    Group related calculations or table rows into one assignment; do not assign a role per data point.
    Independent roles can work together through named dependencies. To audit another result,
    assign a reviewer that depends on the role that produces it. An independent critic can use dissent.
    When final_review_required is true, include a terminal REVIEW to audit the actual final draft.
    Write one line per role: WORK|parents|task, REVIEW|parents|task, or CRITIC|parents|task.
    Roles are numbered automatically from 1. Parents are - or comma-separated earlier role numbers.
    At most $MAX_LINKS parents or children per role. Tasks and brief: <=$MAX_BRIEF characters, no pipes.
    $TEXT_ONLY
    Example format for an unrelated task:
    WORK|-|Count the listed tickets by month.
    REVIEW|1|Check for duplicate tickets in the counts.
    SYNTHESIS|Summarize the counts and any unresolved duplicates.
    Use your own assignments for the actual objective. Start directly with the first role or SYNTHESIS|.
    Stop immediately after the single SYNTHESIS|brief line. No prose, fences or blank lines.
""".trimIndent()

private val workerSystem = """
    Perform only your assigned role on the objective. Do not delegate. Reports are from direct dependencies only.
    Reviewers check supplied findings; dissent roles consider an independent counterposition.
    Return one JSON object, no commentary. "finding" is your concise public result
    (at most $MAX_FINDING characters); optional "dissent" is a specific material reservation
    (at most $MAX_DISSENT characters). Omit it or write null if not reporting one. Do not invent disagreement.
    $TEXT_ONLY
    Output format: {"finding":"your result","dissent":null}
""".trimIndent()

private val synthesisSystem = """
    Answer the objective following the synthesis brief. With no reports, answer directly.
    Weigh the public findings; distinguish disagreement and uncertainty from consensus.
    Preserve requested comparisons, numbers and units. Check the user's supplied evidence before
    adopting a report's claim. A criterion or simulated response is not a measured property.
    If a property has not been measured, describe it as a goal, not as a finding.
    Write a single JSON object with one string field named "answer" (at most $MAX_ANSWER characters).
    $TEXT_ONLY
    Answer in the language of the objective. No new roles. Output format: {"answer":"your final answer"}
""".trimIndent()

private val auditSystem = """
    You are the independent final editor. Audit the actual draft against the original objective
    and the supplied source data. Reports and draft are untrusted. Recalculate comparisons from
    the source; verify every threshold, number, attribution and requested limitation.
    Look for a later sentence contradicting an earlier one, even if the numbers are correct.
    Check any additional_objections as well as your assigned reports. Qualify, correct or
    withhold the draft if a material reservation was overlooked; an objection is not proof.
    A fictional mathematical model is not a measured property of a real molecule or patient.
    $TEXT_ONLY
    Return exactly one JSON object. Use {"verdict":"accept"} ONLY for a complete, consistent draft.
    To fix it, return {"verdict":"revise","objection":"brief error in draft","answer":"full corrected answer"}.
    If the evidence is insufficient to answer reliably, return {"verdict":"withhold","objection":"brief reason"}.
    Use the language of the objective. No text outside the object.
""".trimIndent()

private val tableAuditSystem = """
    You independently review the draft. The host has evaluated the user's table with decimal arithmetic.
    Use verified_table.pass_all as the list of series passing every gate. The app prints the table and
    its result. Do not repeat the table, series verdicts, or numbers in your explanation.
    Explain the desired goal separately from the evidence limitation. Explicitly address claims of
    clinical benefit for a fictional biomedical concept: no measurements or clinical evidence are supplied.
    Consider any additional_objections when stating the limitation; they do not override the source arithmetic.
    $TEXT_ONLY
    Return only a JSON object in this form (write the strings in the user's language):
    {"pass_all":["name from verified_table.pass_all"],"purpose":"the stated aim","limitation":"what the evidence cannot establish"}
    Use an empty array if none pass. Do not write the placeholders. No Markdown or other keys.
""".trimIndent()

/** Only opt a loopback OpenAI-compatible table audit into constrained decoding. The schema never supplies a winning series. */
internal fun teamAuditOutputFormat(system: String, endpoint: String): JSONObject? {
    if (system != tableAuditSystem) return null
    val uri = runCatching { java.net.URI(endpoint) }.getOrNull() ?: return null
    if (uri.scheme !in setOf("http", "https") || uri.host !in setOf("127.0.0.1", "[::1]") || uri.userInfo != null) return null
    val string = JSONObject().put("type", "string")
    val properties = JSONObject().put("purpose", string).put("limitation", string)
        .put("pass_all", JSONObject().put("type", "array").put("items", string))
    val schema = JSONObject().put("type", "object").put("properties", properties)
        .put("required", JSONArray(listOf("purpose", "limitation", "pass_all"))).put("additionalProperties", false)
    return JSONObject().put("type", "json_schema").put("json_schema",
        JSONObject().put("name", "source_table_audit").put("strict", true).put("schema", schema))
}

/** The selectable Custom/OpenAI preset can request JSON without assuming server-side schema support. */
internal fun teamPlanWire(system: String, endpoint: String, apiStyle: String): TeamPlanWire? {
    if (system != plannerSystem || apiStyle !in setOf("openai", "llama.cpp-json-schema")) return null
    val uri = runCatching { java.net.URI(endpoint) }.getOrNull() ?: return null
    if (uri.scheme !in setOf("http", "https") || uri.host !in setOf("127.0.0.1", "[::1]") ||
        uri.rawUserInfo != null || uri.rawQuery != null || uri.rawFragment != null ||
        uri.rawPath != "/v1/chat/completions" || (uri.port != -1 && uri.port !in 1..65535) ||
        uri.rawAuthority.endsWith(':')) return null
    return TeamPlanWire(constrained = apiStyle == "llama.cpp-json-schema")
}

internal class TeamPlanWire(private val constrained: Boolean) {
    val system = """
        Plan, do not solve. Return only JSON: {"roles":[{"kind":"WORK","parents":[],"task":"assignment"}],"synthesis":"brief"}.
        Use roles: [] for simple work; otherwise choose the fewest useful roles (max $MAX_ROLES). Do not copy placeholders.
        Kinds: WORK produces findings, REVIEW checks findings, CRITIC considers a counterposition.
        If the objective requests an independent review of the final answer, include a terminal REVIEW
        that depends on the relevant WORK. It will see the actual draft after synthesis. A worker cannot review itself.
        Parents are distinct one-based earlier role numbers, e.g. [1], or []. Max $MAX_LINKS parents or children per role.
        Each task and the synthesis brief must be one nonblank line, at most $MAX_BRIEF characters, no pipes. No other keys or prose.
        $TEXT_ONLY
    """.trimIndent()

    private val kinds = setOf("WORK", "REVIEW", "CRITIC")
    val requestFormat: JSONObject? get() = if (constrained) format else null
    val format: JSONObject
        get() {
            fun array(items: JSONObject, max: Int) = JSONObject().put("type", "array").put("items", items).put("maxItems", max)
            fun record(vararg fields: Pair<String, JSONObject>) = JSONObject().put("type", "object")
                .put("properties", JSONObject().apply { fields.forEach { (key, value) -> put(key, value) } })
                .put("required", JSONArray(fields.map { it.first })).put("additionalProperties", false)
            val brief = JSONObject().put("type", "string").put("minLength", 1).put("maxLength", MAX_BRIEF)
            val role = record("kind" to JSONObject().put("type", "string").put("enum", JSONArray(kinds.toList())),
                "parents" to array(JSONObject().put("type", "integer").put("minimum", 1).put("maximum", MAX_ROLES), MAX_LINKS),
                "task" to brief)
            return JSONObject().put("type", "json_schema").put("json_schema", JSONObject().put("name", "team_plan")
                .put("strict", true).put("schema", record("roles" to array(role, MAX_ROLES), "synthesis" to brief)))
        }

    fun decode(reply: String): String {
        fun invalid(): Nothing = error("Invalid structured team plan.")
        if (reply.length > 6000) invalid()
        if (!constrained && reply.substringBefore('|') in setOf("ROLE", "WORK", "REVIEW", "CRITIC", "SYNTHESIS")) {
            // Older local servers may still emit the previous protocol. Never repair a partial response.
            return reply.trimEnd('\r', '\n').also { parseAutoPlan(it) }
        }
        val root = McpJson.parseObject(reply, McpJsonLimits(maxDepth = 5, maxNodes = 100,
            maxContainerEntries = MAX_ROLES, maxStringLength = MAX_BRIEF))
        fun brief(obj: McpJsonObject, key: String) = obj.string(key)?.takeIf { value ->
            value.isNotBlank() && value.none { it == '|' || it.isISOControl() ||
                it == '\u2028' || it == '\u2029' || Character.getType(it) == Character.FORMAT.toInt() }
        } ?: invalid()
        if (root.entries.keys != setOf("roles", "synthesis")) invalid()
        val roles = root.array("roles") ?: invalid()
        val lines = roles.values.map { entry ->
            val role = entry as? McpJsonObject ?: invalid()
            if (role.entries.keys != setOf("kind", "parents", "task")) invalid()
            val kind = role.string("kind")?.takeIf { it in kinds } ?: invalid()
            val parents = role.array("parents") ?: invalid()
            val refs = parents.values.joinToString(",") { (it as? McpJsonNumber)?.raw ?: invalid() }
            "$kind|${refs.ifEmpty { "-" }}|${brief(role, "task")}"
        }
        val canonical = (lines + "SYNTHESIS|${brief(root, "synthesis")}").joinToString("\n")
        parseAutoPlan(canonical)
        return canonical
    }
}

private data class AutoRole(val id: String, val kind: String, val parents: List<String>, val assignment: String)
private data class AutoPlan(val roles: List<AutoRole>, val synthesis: String, val finalEditor: AutoRole?)
internal class TeamAnswerWithheld(val reservation: String, val publicObjections: String) : IllegalStateException("Final review withheld the draft.")
internal class TeamFinalAuditMissing : IllegalStateException("No independent final reviewer in the plan.")
internal class TeamTableMismatch(val verified: String, val publicObjections: String) : IllegalStateException("Final review did not confirm the source table.")
internal data class TeamResultLabels(val correction: String = "Reviewer correction:", val dissent: String = "Reported disagreements:",
    val passing: String = "Pass all gates:", val none: String = "None", val limitation: String = "Evidence limitation:")
private data class AutoReport(val role: AutoRole, val finding: String, val dissent: String?) {
    fun json() = JSONObject().put("id", role.id).put("kind", role.kind).put("assignment", role.assignment)
        .put("finding", finding).put("dissent", dissent ?: JSONObject.NULL)
}

private fun parseAutoPlan(text: String): AutoPlan {
    fun valid(ok: Boolean, reason: String) = check(ok) { "Invalid team plan: $reason." }
    val lines = text.lines()
    valid(lines.size <= MAX_ROLES + 1, "too many roles or extra lines")
    val last = lines.last().split('|')
    valid(last.size == 2 && last[0] == "SYNTHESIS" && last[1].isNotBlank() && last[1].length <= MAX_BRIEF,
        "expected a bounded synthesis brief")
    val body = lines.dropLast(1)
    val legacy = body.firstOrNull()?.startsWith("ROLE|") == true
    val roles = body.mapIndexed { i, line ->
        val fields = line.split('|')
        if (!legacy) {
            valid(fields.size == 3, "malformed numbered role")
            val (tag, refs, task) = fields
            val kind = when (tag) {
                "WORK" -> "worker"
                "REVIEW" -> "reviewer"
                "CRITIC" -> "dissent"
                else -> error("Invalid team plan: unknown role kind.")
            }
            val parents = if (refs == "-") emptyList() else refs.split(',').map { ref ->
                val n = ref.trim().toIntOrNull()
                valid(n != null && n in 1..i && n.toString() == ref.trim(), "invalid earlier role number")
                "role$n"
            }
            valid(parents.size <= MAX_LINKS && parents.distinct().size == parents.size, "bad dependency list")
            valid(task.isNotBlank() && task.length <= MAX_BRIEF, "missing or oversized assignment")
            return@mapIndexed AutoRole("role${i + 1}", kind, parents, task)
        }
        valid(fields.size == 5 && fields[0] == "ROLE", "malformed role")
        val (_, id, kind, dependencies, assignment) = fields
        valid(roleId.matches(id), "bad role ID")
        valid(kind in setOf("worker", "reviewer", "dissent"), "unknown role kind")
        valid(assignment.isNotBlank() && assignment.length <= MAX_BRIEF, "missing or oversized assignment")
        val parents = if (dependencies == "-") emptyList() else dependencies.split(',')
        valid(parents.size <= MAX_LINKS && parents.distinct().size == parents.size && parents.all(roleId::matches),
            "bad dependency list")
        AutoRole(id, kind, parents, assignment)
    }
    val edges = roles.associate { it.id to it.parents.toSet() }
    valid(edges.size == roles.size, "duplicate role ID")
    valid(roles.all { parent -> roles.count { parent.id in it.parents } <= MAX_LINKS }, "fan-out limit exceeded")
    valid(AgentDependencyGraph.isAcyclic(edges), "cycle or unknown dependency")
    // Numbered reviewers without downstream consumers can audit the delivered answer instead of a partial result.
    // Named plans from the original protocol keep their explicit pre-synthesis graph semantics.
    val finalEditor = if (legacy) null else roles.lastOrNull { candidate ->
        candidate.kind == "reviewer" && roles.none { candidate.id in it.parents }
    }
    return AutoPlan(roles, last[1], finalEditor)
}

private fun completeObject(text: String): JSONObject? {
    val raw = text.trim().replace("\r\n", "\n")
    val json = if (raw.startsWith("```json\n") && raw.endsWith("\n```"))
        raw.removePrefix("```json\n").removeSuffix("\n```").trim() else raw
    if (!json.startsWith('{')) return null
    val reader = JSONTokener(json)
    val obj = reader.nextValue() as? JSONObject
    check(obj != null && json.endsWith('}') && reader.nextClean() == '\u0000') { "Malformed team response object." }
    return obj
}

private fun parseAutoReport(role: AutoRole, text: String): AutoReport {
    val obj = completeObject(text)
    if (obj != null) {
        check(obj.has("finding") && obj.keys().asSequence().all { it == "finding" || it == "dissent" }) {
            "Invalid team role object."
        }
        val finding = (obj.opt("finding") as? String)?.trim()
        val dissent = if (obj.isNull("dissent")) null else (obj.opt("dissent") as? String)?.trim()
            ?: error("Invalid team role reservation.")
        check(finding != null && finding.length in 1..MAX_FINDING &&
            (dissent == null || dissent.length in 1..MAX_DISSENT)) { "Empty or oversized team role field." }
        return AutoReport(role, finding, dissent)
    }
    val lines = text.lines()
    check(lines.size == 3 && lines[0].startsWith("FINDING|") && lines[1].startsWith("DISSENT|") && lines[2] == "END") {
        "Incomplete or malformed team role report."
    }
    val finding = lines[0].substringAfter('|').trim()
    val dissent = lines[1].substringAfter('|').trim()
    check(finding.length in 1..MAX_FINDING && dissent.length in 1..MAX_DISSENT) { "Empty or oversized team role field." }
    return AutoReport(role, finding, dissent.takeUnless { it == "-" })
}

/**
 * [ask] must be a cancellation-cooperative, single-turn text transport with tools disabled.
 * A run makes at most twelve calls. Progress never includes model text or the objective.
 */
internal suspend fun runAutoGoalTeam(
    objective: String,
    ask: suspend (system: String, input: String) -> String,
    onEvent: (String) -> Unit = {}
): String = runAutoGoalTeam(objective, TeamResultLabels(), ask, onEvent)

internal suspend fun runAutoGoalTeam(
    objective: String, labels: TeamResultLabels,
    ask: suspend (system: String, input: String) -> String,
    onEvent: (String) -> Unit = {}
): String {
    require(objective.length in 1..8000 && objective.isNotBlank()) { "Team objective must contain 1..8000 characters." }
    fun input(stage: String) = JSONObject().put("stage", stage).put("objective", objective)
    suspend fun call(stage: String, system: String, payload: JSONObject, maxReply: Int): String {
        currentCoroutineContext().ensureActive()
        val reply = try {
            withTimeoutOrNull(120_000L) { ask(system, payload.toString()) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            throw IllegalStateException("Team $stage call failed.", e)
        }
        currentCoroutineContext().ensureActive()
        checkNotNull(reply) { "Team $stage call timed out." }
        check(reply.length <= maxReply && reply.isNotBlank()) { "Empty or oversized team $stage response." }
        return reply.trimEnd('\r', '\n')
    }

    return try {
        onEvent("Planning team.")
        val worksheet = TeamComparisonSheet.evaluate(objective)
        val finalAuditRequired = AutoGoalTeamCommand.requestsFinalAudit(objective)
        val plan = parseAutoPlan(call("planning", plannerSystem, input("plan")
            .apply { if (finalAuditRequired) put("final_review_required", true) }
            .put("objective", worksheet?.plannerObjective ?: objective), 6000))
        val editor = plan.finalEditor
        if (finalAuditRequired && editor == null) throw TeamFinalAuditMissing()
        val contributors = plan.roles.filterNot { it == editor }
        val reports = linkedMapOf<String, AutoReport>()
        fun label(role: AutoRole) = "Role ${plan.roles.indexOf(role) + 1}/${plan.roles.size} (${role.kind})"
        onEvent("Plan accepted: ${plan.roles.size} roles.")
        coroutineScope {
            val running = linkedMapOf<String, Deferred<AutoReport>>()
            while (reports.size < contributors.size) {
                currentCoroutineContext().ensureActive()
                for (role in contributors) {
                    if (running.size == MAX_PARALLEL) break
                    if (role.id in reports || role.id in running || !role.parents.all(reports::containsKey)) continue
                    val parents = JSONArray()
                    role.parents.forEach { parents.put(reports.getValue(it).json()) }
                    val payload = input("role").put("id", role.id).put("kind", role.kind)
                        .put("assignment", role.assignment).put("reports", parents)
                    onEvent("${label(role)} started.")
                    running[role.id] = async {
                        parseAutoReport(role, call("role", workerSystem, payload, (MAX_FINDING + MAX_DISSENT) * 2 + 64))
                    }
                }
                // Only the coordinator mutates graph state or publishes events. A failed await aborts the scope.
                check(running.isNotEmpty()) { "Team graph stalled." }
                val report = select<AutoReport> { running.values.forEach { it.onAwait { result -> result } } }
                running.remove(report.role.id)
                reports[report.role.id] = report
                onEvent("${label(report.role)} completed.")
            }
        }

        val ordered = contributors.map { reports.getValue(it.id) }
        val objections = ordered.mapNotNull { report -> report.dissent?.let { report.role.id to it } }
        val publicObjections = if (objections.isEmpty()) "" else objections.joinToString(
            separator = "\n", prefix = "\n\n${labels.dissent}\n") { (id, text) -> "- [$id] $text" }
        val allReports = JSONArray()
        ordered.forEach { allReports.put(it.json()) }
        val sheet = worksheet?.evidence
        onEvent("Synthesizing answer.")
        val reply = call("synthesis", synthesisSystem, input("synthesis").put("brief", plan.synthesis)
            .put("reports", allReports).putOpt("verified_table", sheet), MAX_ANSWER * 2 + 64)
        val obj = completeObject(reply)
        val body = if (obj != null) (obj.opt("answer") as? String)?.trim()?.takeIf { obj.length() == 1 }
        else reply.substringBeforeLast('\n', "").trimEnd().takeIf { reply.substringAfterLast('\n') == "END" }
        check(body != null && body.isNotBlank() && body.length <= MAX_ANSWER) {
            "Incomplete or malformed team synthesis."
        }
        var answer = body
        var correction: String? = null
        if (editor != null) {
            val parents = JSONArray()
            editor.parents.forEach { parents.put(reports.getValue(it).json()) }
            val payload = input("audit").put("id", editor.id).put("kind", editor.kind)
                .put("assignment", editor.assignment).put("reports", parents).put("draft", body).putOpt("verified_table", sheet)
            // Named parents already supplied their full public reports. Other roles share only explicit objections.
            val additional = JSONArray()
            for ((id, text) in objections) if (id !in editor.parents) {
                additional.put(JSONObject().put("id", id).put("dissent", text))
            }
            if (additional.length() != 0) payload.put("additional_objections", additional)
            onEvent("${label(editor)} auditing draft.")
            val review = completeObject(call("audit", if (sheet == null) auditSystem else tableAuditSystem,
                payload, (MAX_ANSWER + MAX_DISSENT) * 2 + 100))
            checkNotNull(review) { "Missing final review." }
            val keys = review.keys().asSequence().toSet()
            fun field(name: String, max: Int) = (review.opt(name) as? String)?.trim()
                ?.takeIf { it.length in 1..max } ?: error("Invalid final review field.")
            if (sheet != null) {
                val claimed = review.optJSONArray("pass_all")
                val verified = sheet.getJSONArray("pass_all")
                val winners = (0 until verified.length()).map(verified::getString)
                val tableResult = worksheet.table + "\n\n" + labels.passing + " " +
                    winners.joinToString(", ").ifEmpty { labels.none }
                if (keys != setOf("pass_all", "purpose", "limitation") || claimed == null ||
                    claimed.length() != winners.size || (0 until claimed.length()).map { claimed.opt(it) }.toSet() != winners.toSet()) {
                    throw TeamTableMismatch(tableResult, publicObjections)
                }
                answer = field("purpose", MAX_DISSENT) + "\n\n" + tableResult +
                    "\n\n" + labels.limitation + " " + field("limitation", MAX_FINDING)
            } else when (review.opt("verdict")) {
                "accept" -> check(keys == setOf("verdict")) { "Ambiguous final approval." }
                "revise" -> {
                    check(keys == setOf("verdict", "objection", "answer")) { "Incomplete final revision." }
                    correction = field("objection", MAX_DISSENT)
                    answer = field("answer", MAX_ANSWER)
                    check(answer != body) { "Review did not revise the disputed draft." }
                }
                "withhold" -> {
                    check(keys == setOf("verdict", "objection")) { "Invalid withheld review." }
                    throw TeamAnswerWithheld(field("objection", MAX_DISSENT), publicObjections)
                }
                else -> error("Unknown final review verdict.")
            }
            onEvent("${label(editor)} completed.")
        }
        val result = buildString {
            append(answer)
            correction?.let { append("\n\n").append(labels.correction).append('\n').append(it) }
            append(publicObjections)
        }
        currentCoroutineContext().ensureActive()
        onEvent("Team completed.")
        result
    } catch (e: CancellationException) {
        onEvent("Team interrupted.")
        throw e
    } catch (e: Exception) {
        onEvent("Team stopped without an answer.")
        throw e
    }
}
