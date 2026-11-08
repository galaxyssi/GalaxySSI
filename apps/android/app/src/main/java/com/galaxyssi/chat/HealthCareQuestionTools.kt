package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal object HealthCareQuestionTools {
    const val READ = "galaxyssi.health.questions.read"
    const val PROPOSE = "galaxyssi.health.questions.propose"
    val ids = setOf(READ, PROPOSE)
    fun definitions(execute: (String, AgentNativeToolInvocationContext, AgentNativeJsonObject) -> JSONObject) = listOf(READ, PROPOSE).map { id ->
        val read = id == READ
        AgentNativeToolDefinition(AgentNativeToolDescriptor(id, "1.0.0",
            if (read) "Read this health concern's question ledger" else "Record a necessary health clarification question",
            if (read) "Read up to 30 questions in the authorized concern and profile sharing scope. Use next as after_id. " +
                "Respect answered, deferred, declined, conflicting and stale states; no arbitrary patient or concern selector."
            else "Retain a decision-relevant question and its purpose for explicit user review in Personal Health. " +
                "Reuse the same stable semantic key for the same gap across retries and models; never bypass declined/deferred questions by paraphrasing. " +
                "Known detection fields use context.<field> from clarification_context. Selected profile fields use profile.<lowercase field>. " +
                "This tool cannot record an answer, confirm a clinical fact or schedule reminders. It does not send a notification.",
            AgentNativeToolLocation.PHONE,
            if (read) AgentNativeJsonSchema.objectSchema(properties = mapOf("after_id" to AgentNativeJsonSchema.string(maxLength = 36)), additionalProperties = false)
            else AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "key" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 80, description = "Stable lowercase semantic key: letters, digits, underscores and dots. Not the wording of the question."),
                "question" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 500),
                "purpose" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 1000, description = "Why this missing fact changes the next decision; do not ask for unrelated history.")
            ), required = setOf("key", "question", "purpose"), additionalProperties = false),
            AgentNativeJsonSchema.objectSchema(additionalProperties = true), if (read) AgentNativeToolRisk.LOW else AgentNativeToolRisk.MEDIUM,
            capabilities = setOf(if (read) "health.questions.read" else "health.questions.propose"),
            effect = if (read) AgentNativeToolEffect.READ_ONLY else AgentNativeToolEffect.MUTATION,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
            AgentNativeToolExecutor { call ->
                try { AgentNativeToolExecutionResult.success(execute(id, call.context, call.input).toNativeObject()) }
                catch (_: HealthCareConflict) { AgentNativeToolExecutionResult.failure("health_scope_changed",
                    "The authorized concern, sources or sharing scope changed. Review the current concern; do not retry stale answers.") }
                catch (_: IllegalArgumentException) { AgentNativeToolExecutionResult.failure("invalid_health_question",
                    "Read with the exact next cursor, or propose key, question and decision-relevant purpose only. No answer or confirmation fields.") }
            })
    }
    fun definitions(context: Context) = definitions { id, invocation, input ->
        if (!HealthCareDiscussion.bound(context, invocation.conversationId) ||
            HealthCareDiscussion.rejection(context, invocation.conversationId, invocation.turnId) != null) throw HealthCareConflict()
        val result = execute(context, HealthOverviewDatabases(), id, invocation, input)
        if (HealthCareDiscussion.rejection(context, invocation.conversationId, invocation.turnId) != null) throw HealthCareConflict()
        result
    }
    internal fun execute(context: Context, names: HealthOverviewDatabases, id: String,
        invocation: AgentNativeToolInvocationContext, input: AgentNativeJsonObject, now: Long = System.currentTimeMillis()): JSONObject {
        require(id in ids)
        return HealthCareStore(context, names.care).use { care ->
            val grant = care.discussionGrant(invocation.turnId) ?: throw HealthCareConflict()
            val issue = care.concern(grant.concernId) ?: throw HealthCareConflict()
            val settings = care.settings()
            val permission = HealthPrivacyStore(context, names.privacy).use { it.policy() }
            fun current() = grant.questionsShared && HealthCareDiscussionPolicy.permitted(grant, invocation.conversationId, invocation.turnId, issue,
                settings, permission, grant.destination, now) && care.discussion(invocation.conversationId) == issue.id &&
                care.researchGrantCurrent(grant) && care.concern(issue.id)?.revision == issue.revision && care.settings() == settings &&
                HealthPrivacyStore(context, names.privacy).use { it.policy() } == permission &&
                HealthCareProfileAccess.current(context, issue.profileLink, names) &&
                HealthRecordStore(context, names.records).use { issue.inputVersion == HealthCareEngine.inputVersion(settings.version, permission.version, it.metricVersion(issue.metric)) }
            if (!current()) throw HealthCareConflict()
            val profile = issue.profileLink?.let { HealthCareProfileAccess.capture(context, it, names) }
            val result = if (id == READ) {
                require(input.keys.all { it == "after_id" })
                HealthCareQuestionPolicy.snapshot(care.questions(issue, input["after_id"] as? String ?: ""), issue, profile)
                    .put("protocol", HealthCareQuestionObservation.PROTOCOL).put("page_start", input["after_id"] ?: JSONObject.NULL)
            } else {
                require(input.keys == setOf("key", "question", "purpose"))
                val row = care.proposeQuestion(grant, input["key"] as? String ?: "", input["question"] as? String ?: "",
                    input["purpose"] as? String ?: "", now)
                val view = HealthCareQuestionPolicy.view(row, issue, HealthCareQuestionPolicy.known(issue, profile))
                JSONObject().put("id", row.id).put("revision", row.revision).put("key", row.key)
                    .put("state", view.getString("state")).put("ask_again", view.getBoolean("ask_again"))
                    .put("user_reopen_required", view.getBoolean("user_reopen_required"))
                    .put("retained", true).put("answer_saved_by_tool", false).put("notification_sent", false)
            }
            if (!current()) throw HealthCareConflict()
            result
        }
    }
}
